import 'dart:math' as math;
import 'dart:typed_data';

import 'geo.dart';
import 'road_graph.dart';

/// Baut aus Overpass-JSON-Antworten einen [RoadGraph].
///
/// Die Overpass-Abfragen liefern Wege (mit Knoten-IDs), die zugehörigen
/// Knoten (mit Koordinaten), Ortsnamen (place=*) und Objekte (mit Mittelpunkt).
class OsmGraphBuilder {
  final Map<int, Map<String, dynamic>> _ways = {};
  final Map<int, int> _nodeIndex = {};
  final List<double> _nodeLat = [], _nodeLon = [];
  final Map<String, Map<String, dynamic>> _pois = {};
  final Map<int, Map<String, dynamic>> _places = {};

  /// Fügt die Elemente einer Overpass-Antwort hinzu (Duplikate aus
  /// überlappenden Kacheln werden ignoriert).
  void addOverpassElements(List elements) {
    for (final raw in elements) {
      final el = raw as Map<String, dynamic>;
      final type = el['type'];
      final id = el['id'] as int;
      final tags = (el['tags'] as Map?)?.cast<String, dynamic>();
      if (type == 'node') {
        if (!_nodeIndex.containsKey(id) && el['lat'] != null) {
          _nodeIndex[id] = _nodeLat.length;
          _nodeLat.add((el['lat'] as num).toDouble());
          _nodeLon.add((el['lon'] as num).toDouble());
        }
        if (tags != null) {
          if (tags['place'] != null && tags['name'] != null) {
            _places[id] = el;
          }
          if (poiCategory(tags) != null) _pois['n$id'] = el;
        }
      } else if (type == 'way') {
        if (tags != null && tags['highway'] != null && el['nodes'] != null) {
          _ways[id] = el;
        } else if (tags != null && poiCategory(tags) != null) {
          _pois['w$id'] = el;
        }
      } else if (type == 'relation') {
        if (tags != null && poiCategory(tags) != null) _pois['r$id'] = el;
      }
    }
  }

  static PoiCategory? poiCategory(Map<String, dynamic> t) {
    if (t['name'] == null) return null;
    final tourism = t['tourism'];
    final amenity = t['amenity'];
    final social = t['social_facility'];
    if (amenity == 'hospital') return PoiCategory.hospital;
    if (amenity == 'nursing_home' ||
        social == 'nursing_home' ||
        social == 'assisted_living' ||
        t['healthcare'] == 'nursing_home') {
      return PoiCategory.nursingHome;
    }
    if (amenity == 'school') return PoiCategory.school;
    if (tourism == 'hotel' || tourism == 'motel') return PoiCategory.hotel;
    return null;
  }

  /// Ist der Weg für Kraftfahrzeuge befahrbar? (Ohne Sonderrechte.)
  static bool isDrivable(Map<String, dynamic> t) {
    final hw = t['highway'];
    if (!highwayToClass.containsKey(hw)) return false;
    if (t['area'] == 'yes') return false;
    if (hw == 'service') {
      const excluded = {'parking_aisle', 'driveway', 'drive-through', 'emergency_access'};
      if (excluded.contains(t['service'])) return false;
    }
    const okValues = {'yes', 'destination', 'designated', 'permissive'};
    const noValues = {'no', 'private', 'agricultural', 'forestry', 'delivery'};
    final emergency = t['emergency'];
    final emergencyOk = emergency == 'yes' || emergency == 'designated';
    for (final key in ['motorcar', 'motor_vehicle', 'vehicle', 'access']) {
      final v = t[key];
      if (v == null) continue;
      if (okValues.contains(v)) return true;
      if (noValues.contains(v)) return emergencyOk;
    }
    return true;
  }

  static double? _parseNumber(String? v) {
    if (v == null) return null;
    final m = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(v);
    if (m == null) return null;
    return double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }

  /// Darf ein Feuerwehr-LKW (ca. 16 t, 3,5 m hoch, 2,55 m breit) fahren?
  static bool lkwAllowed(Map<String, dynamic> t) {
    if (t['hgv'] == 'no') return false;
    final w = _parseNumber(t['maxweight'] as String?);
    if (w != null && w < 16) return false;
    final h = _parseNumber(t['maxheight'] as String?);
    if (h != null && h < 3.5 && t['maxheight'] != 'default') return false;
    final b = _parseNumber(t['maxwidth'] as String?);
    if (b != null && b < 2.55) return false;
    return true;
  }

  static int parseMaxspeed(String? v) {
    if (v == null) return 0;
    switch (v) {
      case 'DE:urban':
        return 50;
      case 'DE:rural':
        return 100;
      case 'DE:living_street':
      case 'walk':
        return 7;
      case 'DE:motorway':
      case 'none':
        return 130;
      case 'DE:bicycle_road':
        return 30;
    }
    if (v.contains('zone') && v.contains('30')) return 30;
    if (v.contains('zone') && v.contains('20')) return 20;
    final n = _parseNumber(v.split(';').first);
    if (n == null) return 0;
    if (v.contains('mph')) return (n * 1.609).round();
    return n.round();
  }

  static int onewayOf(Map<String, dynamic> t) {
    final o = t['oneway'];
    if (o == 'yes' || o == 'true' || o == '1') return 1;
    if (o == '-1' || o == 'reverse') return -1;
    if (o == 'no' || o == 'false' || o == '0') return 0;
    final j = t['junction'];
    if (j == 'roundabout' || j == 'circular') return 1;
    final hw = t['highway'];
    if (hw == 'motorway' || hw == 'motorway_link') return 1;
    return 0;
  }

  RoadGraph build({
    required List<List<double>> areaRings,
    required List<String> areaNames,
  }) {
    final area = AreaPolygon(areaRings);

    // 1) Befahrbare Wege filtern
    final ways = <Map<String, dynamic>>[];
    for (final w in _ways.values) {
      final tags = (w['tags'] as Map).cast<String, dynamic>();
      if (!isDrivable(tags)) continue;
      final nodes = (w['nodes'] as List).cast<int>();
      if (nodes.length < 2) continue;
      if (nodes.any((n) => !_nodeIndex.containsKey(n))) continue;
      ways.add(w);
    }

    // 2) Kreuzungen bestimmen
    final usage = <int, int>{};
    for (final w in ways) {
      final nodes = (w['nodes'] as List).cast<int>();
      for (var i = 0; i < nodes.length; i++) {
        final add = (i == 0 || i == nodes.length - 1) ? 2 : 1;
        usage[nodes[i]] = (usage[nodes[i]] ?? 0) + add;
      }
    }

    // 3) Kanten erzeugen
    final names = <String>[], refs = <String>[];
    final nameIds = <String, int>{}, refIds = <String, int>{};
    final graphNode = <int, int>{};
    final nLat = <double>[], nLon = <double>[];
    final eFrom = <int>[], eTo = <int>[], eName = <int>[], eRef = <int>[];
    final eCls = <int>[], eOneway = <int>[], eLkw = <int>[], eMax = <int>[];
    final geomStart = <int>[0];
    final gLat = <double>[], gLon = <double>[];

    int nodeId(int osm) => graphNode.putIfAbsent(osm, () {
          final i = _nodeIndex[osm]!;
          nLat.add(_nodeLat[i]);
          nLon.add(_nodeLon[i]);
          return nLat.length - 1;
        });

    for (final w in ways) {
      final tags = (w['tags'] as Map).cast<String, dynamic>();
      var nodes = (w['nodes'] as List).cast<int>();
      var oneway = onewayOf(tags);
      if (oneway == -1) {
        nodes = nodes.reversed.toList();
        oneway = 1;
      }
      final name = tags['name'] as String?;
      final ref = tags['ref'] as String?;
      final ni = name == null ? -1 : nameIds.putIfAbsent(name, () {
        names.add(name);
        return names.length - 1;
      });
      final ri = ref == null ? -1 : refIds.putIfAbsent(ref, () {
        refs.add(ref);
        return refs.length - 1;
      });
      final cls = highwayToClass[tags['highway']]!.index;
      final lkw = lkwAllowed(tags) ? 1 : 0;
      final maxspeed = parseMaxspeed(tags['maxspeed'] as String?);

      var segStart = 0;
      for (var i = 1; i < nodes.length; i++) {
        final isJunction = i == nodes.length - 1 || (usage[nodes[i]] ?? 0) >= 2;
        if (!isJunction) continue;
        final a = nodeId(nodes[segStart]);
        final b = nodeId(nodes[i]);
        for (var k = segStart; k <= i; k++) {
          final idx = _nodeIndex[nodes[k]]!;
          gLat.add(_nodeLat[idx]);
          gLon.add(_nodeLon[idx]);
        }
        geomStart.add(gLat.length);
        eFrom.add(a);
        eTo.add(b);
        eName.add(ni);
        eRef.add(ri);
        eCls.add(cls);
        eOneway.add(oneway);
        eLkw.add(lkw);
        eMax.add(maxspeed);
        segStart = i;
      }
    }

    // 4) Nur die größte zusammenhängende Komponente behalten (Inseln durch
    //    Kartenrand oder Datenfehler würden sonst unerreichbare Ziele liefern).
    final keep = _largestComponent(nLat.length, eFrom, eTo);

    // 5) Ortsteile
    final places = <(String, double, double, int)>[];
    const placeRank = {
      'city': 0, 'town': 0, 'village': 1, 'suburb': 1, 'borough': 1,
      'quarter': 2, 'hamlet': 2, 'neighbourhood': 3, 'isolated_dwelling': 4,
    };
    for (final p in _places.values) {
      final t = (p['tags'] as Map).cast<String, dynamic>();
      final rank = placeRank[t['place']];
      if (rank == null || rank > 2) continue;
      places.add((t['name'] as String, (p['lat'] as num).toDouble(),
          (p['lon'] as num).toDouble(), rank));
    }
    final localities = <String>[];
    final locIds = <String, int>{};
    final cosLat = areaRings.isEmpty || areaRings.first.isEmpty
        ? 0.65
        : math.cos(areaRings.first.first * math.pi / 180);
    int nearestPlace(double lat, double lon) {
      String? best;
      var bestD = double.infinity;
      for (final p in places) {
        // Dörfer/Stadtteile leicht bevorzugen vor Weilern
        final dy = lat - p.$2, dx = (lon - p.$3) * cosLat;
        final d = (dx * dx + dy * dy) * (1 + 0.5 * p.$4);
        if (d < bestD) {
          bestD = d;
          best = p.$1;
        }
      }
      if (best == null) return -1;
      return locIds.putIfAbsent(best, () {
        localities.add(best!);
        return localities.length - 1;
      });
    }

    // 6) Kompaktieren
    final newNode = List<int>.filled(nLat.length, -1);
    final fLat = <double>[], fLon = <double>[];
    final out = _EdgeLists();
    for (var e = 0; e < eFrom.length; e++) {
      if (!keep[eFrom[e]]) continue;
      for (final n in [eFrom[e], eTo[e]]) {
        if (newNode[n] < 0) {
          newNode[n] = fLat.length;
          fLat.add(nLat[n]);
          fLon.add(nLon[n]);
        }
      }
      final s = geomStart[e], t = geomStart[e + 1];
      final k = s + (t - s) ~/ 2;
      final midLat = gLat[k], midLon = gLon[k];
      out.from.add(newNode[eFrom[e]]);
      out.to.add(newNode[eTo[e]]);
      out.name.add(eName[e]);
      out.ref.add(eRef[e]);
      out.cls.add(eCls[e]);
      out.oneway.add(eOneway[e]);
      out.lkw.add(eLkw[e]);
      out.maxspeed.add(eMax[e]);
      out.inArea.add(area.contains(midLat, midLon) ? 1 : 0);
      out.loc.add(nearestPlace(midLat, midLon));
      for (var i = s; i < t; i++) {
        out.gLat.add(gLat[i]);
        out.gLon.add(gLon[i]);
      }
      out.geomStart.add(out.gLat.length);
    }

    // 7) Objekte
    final pois = <Poi>[];
    final seen = <String>{};
    for (final el in _pois.values) {
      final t = (el['tags'] as Map).cast<String, dynamic>();
      double? lat, lon;
      if (el['lat'] != null) {
        lat = (el['lat'] as num).toDouble();
        lon = (el['lon'] as num).toDouble();
      } else if (el['center'] != null) {
        lat = (el['center']['lat'] as num).toDouble();
        lon = (el['center']['lon'] as num).toDouble();
      }
      if (lat == null || lon == null) continue;
      final cat = poiCategory(t)!;
      final name = t['name'] as String;
      final key = '$name|${cat.index}|${lat.toStringAsFixed(3)}|${lon.toStringAsFixed(3)}';
      if (!seen.add(key)) continue;
      final street = t['addr:street'] as String?;
      final hn = t['addr:housenumber'] as String?;
      final city = (t['addr:city'] ?? t['addr:place'] ?? t['addr:suburb']) as String?;
      final parts = <String>[
        if (street != null) hn != null ? '$street $hn' : street,
        ?city,
      ];
      pois.add(Poi(name, cat, lat, lon, parts.join(', '), street,
          area.contains(lat, lon)));
    }

    return RoadGraph(
      names: names,
      refs: refs,
      localities: localities,
      nodeLat: Float64List.fromList(fLat),
      nodeLon: Float64List.fromList(fLon),
      eFrom: Int32List.fromList(out.from),
      eTo: Int32List.fromList(out.to),
      eName: Int32List.fromList(out.name),
      eRef: Int32List.fromList(out.ref),
      eLoc: Int32List.fromList(out.loc),
      eCls: Uint8List.fromList(out.cls),
      eOneway: Uint8List.fromList(out.oneway),
      eLkw: Uint8List.fromList(out.lkw),
      eInArea: Uint8List.fromList(out.inArea),
      eMaxspeed: Int16List.fromList(out.maxspeed),
      eGeomStart: Int32List.fromList(out.geomStart),
      gLat: Float64List.fromList(out.gLat),
      gLon: Float64List.fromList(out.gLon),
      pois: pois,
      areaNames: areaNames,
      areaRings: areaRings,
    );
  }

  static List<bool> _largestComponent(int n, List<int> from, List<int> to) {
    final parent = List<int>.generate(n, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    for (var e = 0; e < from.length; e++) {
      final a = find(from[e]), b = find(to[e]);
      if (a != b) parent[a] = b;
    }
    final size = <int, int>{};
    for (var i = 0; i < n; i++) {
      final r = find(i);
      size[r] = (size[r] ?? 0) + 1;
    }
    var bestRoot = -1, bestSize = -1;
    size.forEach((r, s) {
      if (s > bestSize) {
        bestSize = s;
        bestRoot = r;
      }
    });
    return [for (var i = 0; i < n; i++) find(i) == bestRoot];
  }
}

class _EdgeLists {
  final from = <int>[], to = <int>[], name = <int>[], ref = <int>[];
  final cls = <int>[], oneway = <int>[], lkw = <int>[], maxspeed = <int>[];
  final inArea = <int>[], loc = <int>[];
  final geomStart = <int>[0];
  final gLat = <double>[], gLon = <double>[];
}
