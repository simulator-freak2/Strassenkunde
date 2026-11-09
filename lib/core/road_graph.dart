import 'dart:math' as math;
import 'dart:typed_data';

import 'geo.dart';
import 'text_norm.dart';

/// Straßenklassen (Reihenfolge = gespeicherter Index, nicht ändern!).
enum RoadClass {
  motorway,
  trunk,
  primary,
  secondary,
  tertiary,
  unclassified,
  residential,
  livingStreet,
  service,
  road,
  motorwayLink,
  trunkLink,
  primaryLink,
  secondaryLink,
  tertiaryLink,
}

const Map<String, RoadClass> highwayToClass = {
  'motorway': RoadClass.motorway,
  'trunk': RoadClass.trunk,
  'primary': RoadClass.primary,
  'secondary': RoadClass.secondary,
  'tertiary': RoadClass.tertiary,
  'unclassified': RoadClass.unclassified,
  'residential': RoadClass.residential,
  'living_street': RoadClass.livingStreet,
  'service': RoadClass.service,
  'road': RoadClass.road,
  'motorway_link': RoadClass.motorwayLink,
  'trunk_link': RoadClass.trunkLink,
  'primary_link': RoadClass.primaryLink,
  'secondary_link': RoadClass.secondaryLink,
  'tertiary_link': RoadClass.tertiaryLink,
};

/// Typische Durchschnittsgeschwindigkeit PKW in km/h, wenn kein Tempolimit
/// in den Kartendaten steht.
const Map<RoadClass, double> _defaultSpeedPkw = {
  RoadClass.motorway: 115,
  RoadClass.trunk: 90,
  RoadClass.primary: 60,
  RoadClass.secondary: 55,
  RoadClass.tertiary: 45,
  RoadClass.unclassified: 40,
  RoadClass.residential: 30,
  RoadClass.livingStreet: 10,
  RoadClass.service: 15,
  RoadClass.road: 30,
  RoadClass.motorwayLink: 60,
  RoadClass.trunkLink: 50,
  RoadClass.primaryLink: 40,
  RoadClass.secondaryLink: 35,
  RoadClass.tertiaryLink: 30,
};

enum Vehicle { pkw, lkw }

extension VehicleLabel on Vehicle {
  String get label => this == Vehicle.pkw ? 'PKW' : 'LKW';
}

enum PoiCategory { hotel, school, nursingHome, hospital }

extension PoiCategoryLabel on PoiCategory {
  String get label => switch (this) {
        PoiCategory.hotel => 'Hotel',
        PoiCategory.school => 'Schule',
        PoiCategory.nursingHome => 'Alten-/Pflegeheim',
        PoiCategory.hospital => 'Krankenhaus',
      };
}

class Poi {
  final String name;
  final PoiCategory category;
  final double lat, lon;
  final String address;
  final String? street;
  final bool inArea;

  /// Kante, an der das Objekt liegt (wird beim Laden berechnet).
  int edge = -1;

  Poi(this.name, this.category, this.lat, this.lon, this.address, this.street,
      this.inArea);

  Map<String, dynamic> toJson() => {
        'n': name,
        'c': category.index,
        'la': lat,
        'lo': lon,
        'a': address,
        if (street != null) 's': street,
        'i': inArea ? 1 : 0,
      };

  factory Poi.fromJson(Map<String, dynamic> j) => Poi(
      j['n'] as String,
      PoiCategory.values[j['c'] as int],
      (j['la'] as num).toDouble(),
      (j['lo'] as num).toDouble(),
      j['a'] as String,
      j['s'] as String?,
      j['i'] == 1);
}

/// Kompakter Straßengraph. Knoten sind Kreuzungen/Endpunkte, Kanten sind
/// Straßenstücke dazwischen (mit Geometrie).
///
/// Gerichtete Kanten: d = e*2 (in Digitalisierungsrichtung) bzw. e*2+1
/// (Gegenrichtung).
class RoadGraph {
  final List<String> names; // Straßennamen
  final List<String> refs; // Straßennummern (z. B. "B 9")
  final List<String> localities; // Orte/Ortsteile
  final Float64List nodeLat, nodeLon;
  final Int32List eFrom, eTo, eName, eRef, eLoc;
  final Uint8List eCls, eOneway, eLkw, eInArea;
  final Int16List eMaxspeed; // 0 = unbekannt
  final Int32List eGeomStart; // Länge E+1
  final Float64List gLat, gLon;
  final List<Poi> pois;
  final List<String> areaNames;
  final List<List<double>> areaRings;

  // ---- abgeleitete Daten ----
  late final int nodeCount = nodeLat.length;
  late final int edgeCount = eFrom.length;
  late final Float64List eLength;
  late final Float64List _bearStart, _bearEnd;
  late final Int32List _outStart, _outList, _degree;
  late final AreaPolygon area;
  late final BBox bbox;
  late final Map<String, Set<int>> nameIndex; // normalisiert -> Namens-IDs
  late final Map<String, Set<int>> refIndex; // normalisiert -> Ref-IDs
  late final List<List<int>> _grid;
  late final double _gridLat0, _gridLon0;
  late final int _gridW, _gridH;
  static const double _cellDeg = 0.004;

  RoadGraph({
    required this.names,
    required this.refs,
    required this.localities,
    required this.nodeLat,
    required this.nodeLon,
    required this.eFrom,
    required this.eTo,
    required this.eName,
    required this.eRef,
    required this.eLoc,
    required this.eCls,
    required this.eOneway,
    required this.eLkw,
    required this.eInArea,
    required this.eMaxspeed,
    required this.eGeomStart,
    required this.gLat,
    required this.gLon,
    required this.pois,
    required this.areaNames,
    required this.areaRings,
  }) {
    _derive();
  }

  void _derive() {
    final e = edgeCount;
    eLength = Float64List(e);
    _bearStart = Float64List(e);
    _bearEnd = Float64List(e);
    bbox = BBox.empty();
    for (var i = 0; i < e; i++) {
      final s = eGeomStart[i], t = eGeomStart[i + 1];
      var len = 0.0;
      for (var k = s; k < t; k++) {
        bbox.extend(gLat[k], gLon[k]);
        if (k > s) len += distanceM(gLat[k - 1], gLon[k - 1], gLat[k], gLon[k]);
      }
      eLength[i] = math.max(len, 1.0);
      _bearStart[i] = _bearingAlong(s, t, true);
      _bearEnd[i] = _bearingAlong(s, t, false);
    }
    // Adjazenz (nur befahrbare Richtungen)
    final counts = Int32List(nodeCount + 1);
    _degree = Int32List(nodeCount);
    for (var i = 0; i < e; i++) {
      counts[eFrom[i]]++;
      _degree[eFrom[i]]++;
      _degree[eTo[i]]++;
      if (eOneway[i] == 0) counts[eTo[i]]++;
    }
    _outStart = Int32List(nodeCount + 1);
    for (var n = 0; n < nodeCount; n++) {
      _outStart[n + 1] = _outStart[n] + counts[n];
    }
    _outList = Int32List(_outStart[nodeCount]);
    final fill = Int32List(nodeCount);
    for (var i = 0; i < e; i++) {
      final a = eFrom[i];
      _outList[_outStart[a] + fill[a]++] = i * 2;
      if (eOneway[i] == 0) {
        final b = eTo[i];
        _outList[_outStart[b] + fill[b]++] = i * 2 + 1;
      }
    }
    area = AreaPolygon(areaRings);
    // Namensindex
    nameIndex = {};
    for (var i = 0; i < names.length; i++) {
      nameIndex.putIfAbsent(normalizeStreet(names[i]), () => {}).add(i);
    }
    refIndex = {};
    for (var i = 0; i < refs.length; i++) {
      for (final part in splitOsmValues(refs[i])) {
        refIndex.putIfAbsent(normalizeStreet(part), () => {}).add(i);
      }
    }
    // Raster für Suche nach nächster Kante
    if (bbox.isEmpty) bbox.extend(0, 0);
    _gridLat0 = bbox.south;
    _gridLon0 = bbox.west;
    _gridW = math.max(1, ((bbox.east - bbox.west) / _cellDeg).ceil() + 1);
    _gridH = math.max(1, ((bbox.north - bbox.south) / _cellDeg).ceil() + 1);
    _grid = List.generate(_gridW * _gridH, (_) => <int>[]);
    for (var i = 0; i < e; i++) {
      final cells = <int>{};
      for (var k = eGeomStart[i]; k < eGeomStart[i + 1]; k++) {
        cells.add(_cell(gLat[k], gLon[k]));
      }
      for (final c in cells) {
        _grid[c].add(i);
      }
    }
    for (final p in pois) {
      p.edge = nearestEdge(p.lat, p.lon, preferName: p.street);
    }
  }

  double _bearingAlong(int s, int t, bool atStart) {
    // Richtung über die ersten/letzten ~15 m bestimmen
    if (t - s < 2) return 0;
    if (atStart) {
      var k = s + 1;
      while (k < t - 1 && distanceM(gLat[s], gLon[s], gLat[k], gLon[k]) < 15) {
        k++;
      }
      return bearingDeg(gLat[s], gLon[s], gLat[k], gLon[k]);
    } else {
      var k = t - 2;
      while (k > s &&
          distanceM(gLat[k], gLon[k], gLat[t - 1], gLon[t - 1]) < 15) {
        k--;
      }
      return bearingDeg(gLat[k], gLon[k], gLat[t - 1], gLon[t - 1]);
    }
  }

  int _cell(double lat, double lon) {
    final x = ((lon - _gridLon0) / _cellDeg).floor().clamp(0, _gridW - 1);
    final y = ((lat - _gridLat0) / _cellDeg).floor().clamp(0, _gridH - 1);
    return y * _gridW + x;
  }

  // ---- Zugriff gerichtete Kanten ----
  static int edgeOf(int d) => d >> 1;
  static bool isForward(int d) => (d & 1) == 0;
  int startNode(int d) => isForward(d) ? eFrom[d >> 1] : eTo[d >> 1];
  int endNode(int d) => isForward(d) ? eTo[d >> 1] : eFrom[d >> 1];
  double startBearing(int d) =>
      isForward(d) ? _bearStart[d >> 1] : (_bearEnd[d >> 1] + 180) % 360;
  double endBearing(int d) =>
      isForward(d) ? _bearEnd[d >> 1] : (_bearStart[d >> 1] + 180) % 360;
  int degree(int node) => _degree[node];

  /// Gerichtete Kanten, die von [node] aus befahrbar sind (Einbahnstraßen
  /// beachtet).
  Iterable<int> outgoing(int node) sync* {
    for (var k = _outStart[node]; k < _outStart[node + 1]; k++) {
      yield _outList[k];
    }
  }

  /// Alle (auch nicht befahrbaren) Kanten an einem Knoten.
  List<int> edgesAtNode(int node) {
    final res = <int>[];
    for (var k = _outStart[node]; k < _outStart[node + 1]; k++) {
      res.add(_outList[k] >> 1);
    }
    // Einbahnstraßen, die hier enden, stehen nicht in der Ausgangsliste.
    // Für Beschreibungen suchen wir sie über das Raster.
    for (final e in _edgesNear(nodeLat[node], nodeLon[node])) {
      if ((eFrom[e] == node || eTo[e] == node) && !res.contains(e)) res.add(e);
    }
    return res;
  }

  Iterable<int> _edgesNear(double lat, double lon) sync* {
    final c = _cell(lat, lon);
    final cx = c % _gridW, cy = c ~/ _gridW;
    for (var y = cy - 1; y <= cy + 1; y++) {
      for (var x = cx - 1; x <= cx + 1; x++) {
        if (x < 0 || y < 0 || x >= _gridW || y >= _gridH) continue;
        yield* _grid[y * _gridW + x];
      }
    }
  }

  /// Anzeigename einer Kante ("Hauptstraße", "B 9" oder null).
  String? label(int e) {
    if (eName[e] >= 0) return names[eName[e]];
    if (eRef[e] >= 0) return refs[eRef[e]];
    return null;
  }

  bool isUnnamed(int e) => eName[e] < 0 && eRef[e] < 0;

  /// Mittelpunkt einer Kante (Geometrie-Mitte).
  (double, double) edgeMid(int e) {
    final s = eGeomStart[e], t = eGeomStart[e + 1];
    final k = s + (t - s) ~/ 2;
    if ((t - s).isEven && t - s >= 2) {
      return ((gLat[k - 1] + gLat[k]) / 2, (gLon[k - 1] + gLon[k]) / 2);
    }
    return (gLat[k], gLon[k]);
  }

  /// Fahrzeit über eine Kante in Sekunden.
  double edgeTime(int e, Vehicle v) => eLength[e] / (speedKmh(e, v) / 3.6);

  double speedKmh(int e, Vehicle v) {
    final cls = RoadClass.values[eCls[e]];
    final def = _defaultSpeedPkw[cls]!;
    var s = def;
    final m = eMaxspeed[e];
    if (m > 0) {
      // Durchschnitt liegt unter dem Tempolimit (Kreuzungen, Verkehr)
      s = m * (m <= 50 ? 0.8 : 0.85);
      if (cls == RoadClass.residential ||
          cls == RoadClass.livingStreet ||
          cls == RoadClass.service) {
        s = math.min(s, def * 1.2);
      }
    }
    if (v == Vehicle.lkw) {
      final cap = (cls == RoadClass.motorway || cls == RoadClass.trunk) ? 80.0 : 60.0;
      s = math.min(s * 0.9, cap);
    }
    return math.max(s, 5.0);
  }

  bool allowed(int e, Vehicle v) => v == Vehicle.pkw || eLkw[e] == 1;

  /// Nächstgelegene Kante zu einer Koordinate. Wenn [preferName] gesetzt ist,
  /// wird eine Kante mit diesem Namen im Umkreis von 250 m bevorzugt.
  int nearestEdge(double lat, double lon, {String? preferName}) {
    final prefNorm = preferName == null ? null : normalizeStreet(preferName);
    var best = -1, bestPref = -1;
    var bestD = double.infinity, bestPrefD = double.infinity;
    final c = _cell(lat, lon);
    final cx = c % _gridW, cy = c ~/ _gridW;
    for (var r = 0; r < 40; r++) {
      for (var y = cy - r; y <= cy + r; y++) {
        for (var x = cx - r; x <= cx + r; x++) {
          if (x < 0 || y < 0 || x >= _gridW || y >= _gridH) continue;
          if (r > 0 && y != cy - r && y != cy + r && x != cx - r && x != cx + r) {
            continue;
          }
          for (final e in _grid[y * _gridW + x]) {
            final d = _distToEdge(e, lat, lon);
            if (d < bestD) {
              bestD = d;
              best = e;
            }
            if (prefNorm != null &&
                eName[e] >= 0 &&
                d < bestPrefD &&
                normalizeStreet(names[eName[e]]) == prefNorm) {
              bestPrefD = d;
              bestPref = e;
            }
          }
        }
      }
      // Genug gesucht, wenn bereits ein Treffer klar näher ist als der Rand.
      final searched = r * _cellDeg * 110540.0;
      if (best >= 0 && bestD < searched && (prefNorm == null || searched > 250)) {
        break;
      }
    }
    if (bestPref >= 0 && bestPrefD < 250) return bestPref;
    return best;
  }

  double _distToEdge(int e, double lat, double lon) {
    var best = double.infinity;
    final s = eGeomStart[e], t = eGeomStart[e + 1];
    for (var k = s; k + 1 < t; k++) {
      final d = pointSegmentDistanceM(
          lat, lon, gLat[k], gLon[k], gLat[k + 1], gLon[k + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  /// Name einer Querstraße an einem Knoten (nicht [exceptName]), oder null.
  String? crossStreetAt(int node, int exceptEdge) {
    final own = eName[exceptEdge];
    final ownRef = eRef[exceptEdge];
    String? fallback;
    for (final e in edgesAtNode(node)) {
      if (e == exceptEdge) continue;
      if (eName[e] >= 0 && eName[e] != own) return names[eName[e]];
      if (eName[e] < 0 && eRef[e] >= 0 && eRef[e] != ownRef) {
        fallback ??= refs[eRef[e]];
      }
    }
    return fallback;
  }

  // ---- Serialisierung ----
  Map<String, dynamic> toJson() {
    List<int> e6(Float64List l) => [for (final v in l) (v * 1e6).round()];
    return {
      'version': 1,
      'names': names,
      'refs': refs,
      'localities': localities,
      'nodeLat': e6(nodeLat),
      'nodeLon': e6(nodeLon),
      'eFrom': eFrom,
      'eTo': eTo,
      'eName': eName,
      'eRef': eRef,
      'eLoc': eLoc,
      'eCls': eCls,
      'eOneway': eOneway,
      'eLkw': eLkw,
      'eInArea': eInArea,
      'eMaxspeed': eMaxspeed,
      'eGeomStart': eGeomStart,
      'gLat': e6(gLat),
      'gLon': e6(gLon),
      'pois': [for (final p in pois) p.toJson()],
      'areaNames': areaNames,
      'areaRings': [
        for (final r in areaRings) [for (final v in r) (v * 1e6).round()]
      ],
    };
  }

  factory RoadGraph.fromJson(Map<String, dynamic> j) {
    Float64List f6(String k) {
      final l = j[k] as List;
      final out = Float64List(l.length);
      for (var i = 0; i < l.length; i++) {
        out[i] = (l[i] as int) / 1e6;
      }
      return out;
    }

    Int32List i32(String k) => Int32List.fromList((j[k] as List).cast<int>());
    Uint8List u8(String k) => Uint8List.fromList((j[k] as List).cast<int>());

    return RoadGraph(
      names: (j['names'] as List).cast<String>(),
      refs: (j['refs'] as List).cast<String>(),
      localities: (j['localities'] as List).cast<String>(),
      nodeLat: f6('nodeLat'),
      nodeLon: f6('nodeLon'),
      eFrom: i32('eFrom'),
      eTo: i32('eTo'),
      eName: i32('eName'),
      eRef: i32('eRef'),
      eLoc: i32('eLoc'),
      eCls: u8('eCls'),
      eOneway: u8('eOneway'),
      eLkw: u8('eLkw'),
      eInArea: u8('eInArea'),
      eMaxspeed: Int16List.fromList((j['eMaxspeed'] as List).cast<int>()),
      eGeomStart: i32('eGeomStart'),
      gLat: f6('gLat'),
      gLon: f6('gLon'),
      pois: [
        for (final p in j['pois'] as List) Poi.fromJson(p as Map<String, dynamic>)
      ],
      areaNames: (j['areaNames'] as List).cast<String>(),
      areaRings: [
        for (final r in j['areaRings'] as List)
          [for (final v in r as List) (v as int) / 1e6]
      ],
    );
  }
}
