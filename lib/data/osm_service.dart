import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/geo.dart';
import '../core/osm_builder.dart';
import 'profile.dart';
import 'storage.dart';

const _userAgent = 'Strassenkunde-Lernapp/1.0 (Ortskunde-Trainer Feuerwehr)';
const _nominatim = 'https://nominatim.openstreetmap.org/search';
const _overpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

class AddressResult {
  final String label;
  final double lat, lon;
  AddressResult(this.label, this.lat, this.lon);
}

class OsmException implements Exception {
  final String message;
  OsmException(this.message);
  @override
  String toString() => message;
}

String _kindLabel(String? addresstype, String? type) {
  switch (addresstype ?? type) {
    case 'state':
      return 'Bundesland';
    case 'state_district':
      return 'Regierungsbezirk';
    case 'county':
      return 'Landkreis';
    case 'municipality':
      return 'Gemeinde/Verbandsgemeinde';
    case 'city':
      return 'Stadt';
    case 'town':
      return 'Stadt';
    case 'village':
      return 'Gemeinde/Ort';
    case 'borough':
    case 'city_district':
    case 'suburb':
    case 'quarter':
    case 'neighbourhood':
      return 'Stadtteil';
    case 'hamlet':
      return 'Ortsteil';
    default:
      return 'Verwaltungsgebiet';
  }
}

class OsmService {
  final http.Client _client;
  OsmService([http.Client? client]) : _client = client ?? http.Client();

  Future<List<dynamic>> _nominatimSearch(Map<String, String> params) async {
    final uri = Uri.parse(_nominatim).replace(queryParameters: {
      'format': 'jsonv2',
      'accept-language': 'de',
      ...params,
    });
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw OsmException('Keine Internetverbindung.');
    } on TimeoutException {
      throw OsmException('Zeitüberschreitung bei der Suche.');
    }
    if (res.statusCode != 200) {
      throw OsmException('Suche fehlgeschlagen (HTTP ${res.statusCode}).');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
  }

  /// Sucht Verwaltungsgebiete (Stadtteil, Stadt, Verbandsgemeinde,
  /// Landkreis) mit Umriss.
  Future<List<AreaItem>> searchAreas(String query) async {
    final list = await _nominatimSearch({
      'q': query,
      'polygon_geojson': '1',
      'polygon_threshold': '0.0002',
      'limit': '15',
    });
    final out = <AreaItem>[];
    for (final r in list) {
      final m = r as Map<String, dynamic>;
      final geo = m['geojson'] as Map<String, dynamic>?;
      if (geo == null) continue;
      if (geo['type'] != 'Polygon' && geo['type'] != 'MultiPolygon') continue;
      final rings = AreaPolygon.ringsFromGeoJson(geo);
      if (rings.isEmpty) continue;
      out.add(AreaItem(
        m['display_name'] as String? ?? m['name'] as String? ?? query,
        _kindLabel(m['addresstype'] as String?, m['type'] as String?),
        m['osm_type'] as String? ?? '',
        (m['osm_id'] as num?)?.toInt() ?? 0,
        rings,
      ));
    }
    return out;
  }

  /// Sucht eine Adresse (für den Startpunkt).
  Future<List<AddressResult>> searchAddress(String query) async {
    final list = await _nominatimSearch({'q': query, 'limit': '8'});
    return [
      for (final r in list)
        AddressResult(
          (r as Map<String, dynamic>)['display_name'] as String,
          double.parse(r['lat'] as String),
          double.parse(r['lon'] as String),
        )
    ];
  }

  static String _tileQuery(BBox b) {
    final bb = '${b.south},${b.west},${b.north},${b.east}';
    return '''
[out:json][timeout:240][maxsize:1073741824];
way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|road|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)\$"]($bb)->.roads;
.roads out body;
.roads >;
out skel qt;
(
  nwr["amenity"~"^(school|hospital|nursing_home)\$"]($bb);
  nwr["tourism"~"^(hotel|motel)\$"]($bb);
  nwr["social_facility"~"^(nursing_home|assisted_living)\$"]($bb);
  nwr["healthcare"="nursing_home"]($bb);
  node["place"~"^(city|town|village|suburb|borough|quarter|hamlet)\$"]($bb);
);
out center;
''';
  }

  Future<String> _overpass(String query, void Function(String) status) async {
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      final endpoint = _overpassEndpoints[attempt % _overpassEndpoints.length];
      try {
        final res = await _client
            .post(Uri.parse(endpoint),
                headers: {'User-Agent': _userAgent},
                body: {'data': query})
            .timeout(const Duration(minutes: 5));
        final body = utf8.decode(res.bodyBytes);
        if (res.statusCode == 200 && !body.contains('"remark": "runtime error')) {
          return body;
        }
        lastError = 'HTTP ${res.statusCode}';
      } on SocketException catch (e) {
        lastError = e.message;
      } on TimeoutException {
        lastError = 'Zeitüberschreitung';
      } on http.ClientException catch (e) {
        lastError = e.message;
      }
      final wait = Duration(seconds: 5 * (attempt + 1));
      status('Server ausgelastet ($lastError) – neuer Versuch in '
          '${wait.inSeconds} s …');
      await Future<void>.delayed(wait);
    }
    throw OsmException('Download fehlgeschlagen: $lastError. '
        'Bitte später erneut versuchen.');
  }

  /// Lädt Straßen und Objekte des Profil-Gebiets und speichert die
  /// fertige Karte. Rückgabe: (Straßenanzahl, Objektanzahl).
  Future<(int, int)> downloadProfileData(
    Storage storage,
    Profile profile,
    void Function(String text, double? progress) onProgress,
  ) async {
    if (profile.areas.isEmpty) throw OsmException('Kein Gebiet gewählt.');
    final rings = [for (final a in profile.areas) ...a.rings];
    final areaBox = AreaPolygon(rings).bbox.expanded(profile.bufferM);
    final tiles = areaBox.tiles(0.1);
    final dir = storage.downloadDir(profile);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final files = <String>[];
    for (var i = 0; i < tiles.length; i++) {
      onProgress('Lade Kartendaten (Teil ${i + 1} von ${tiles.length}) …',
          i / (tiles.length + 1));
      final body = await _overpass(
          _tileQuery(tiles[i]), (s) => onProgress(s, i / (tiles.length + 1)));
      final f = File(p.join(dir.path, 'teil_$i.json'));
      await f.writeAsString(body);
      files.add(f.path);
      if (i < tiles.length - 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    onProgress('Verarbeite Straßennetz …', tiles.length / (tiles.length + 1));
    final out = storage.graphFile(profile).path;
    final names = [for (final a in profile.areas) a.name.split(',').first];
    final result = await Isolate.run(() => _buildAndSave(files, rings, names, out));
    await dir.delete(recursive: true);
    onProgress('Fertig', 1);
    return result;
  }
}

(int, int) _buildAndSave(List<String> files, List<List<double>> rings,
    List<String> names, String outPath) {
  final b = OsmGraphBuilder();
  for (final f in files) {
    final json = jsonDecode(File(f).readAsStringSync()) as Map<String, dynamic>;
    b.addOverpassElements(json['elements'] as List);
  }
  final g = b.build(areaRings: rings, areaNames: names);
  if (g.edgeCount == 0) {
    throw OsmException('Im gewählten Gebiet wurden keine Straßen gefunden.');
  }
  encodeGraphFile(g, outPath);
  final streetNames = <int>{};
  for (var e = 0; e < g.edgeCount; e++) {
    if (g.eInArea[e] == 1 && g.eName[e] >= 0) streetNames.add(g.eName[e]);
  }
  return (streetNames.length, g.pois.where((p) => p.inArea).length);
}
