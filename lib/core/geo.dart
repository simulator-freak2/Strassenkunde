import 'dart:math' as math;

/// Einfache Geo-Hilfsfunktionen (WGS84, für kurze Distanzen ausreichend genau).

const double _earthRadius = 6371000.0;

double _rad(double deg) => deg * math.pi / 180.0;

/// Entfernung zweier Punkte in Metern (Haversine).
double distanceM(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * _earthRadius * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Kurswinkel von Punkt 1 nach Punkt 2 in Grad (0 = Nord, 90 = Ost).
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final y = math.sin(_rad(lon2 - lon1)) * math.cos(_rad(lat2));
  final x = math.cos(_rad(lat1)) * math.sin(_rad(lat2)) -
      math.sin(_rad(lat1)) * math.cos(_rad(lat2)) * math.cos(_rad(lon2 - lon1));
  final b = math.atan2(y, x) * 180.0 / math.pi;
  return (b + 360.0) % 360.0;
}

/// Winkeldifferenz in Grad im Bereich -180..180 (positiv = rechts).
double angleDiff(double fromBearing, double toBearing) {
  var d = (toBearing - fromBearing) % 360.0;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Abstand Punkt–Strecke in Metern (lokale Ebenen-Näherung).
double pointSegmentDistanceM(
    double lat, double lon, double lat1, double lon1, double lat2, double lon2) {
  final kx = math.cos(_rad(lat)) * 111320.0;
  const ky = 110540.0;
  final px = (lon - lon1) * kx, py = (lat - lat1) * ky;
  final sx = (lon2 - lon1) * kx, sy = (lat2 - lat1) * ky;
  final len2 = sx * sx + sy * sy;
  var t = len2 == 0 ? 0.0 : (px * sx + py * sy) / len2;
  t = t.clamp(0.0, 1.0);
  final dx = px - t * sx, dy = py - t * sy;
  return math.sqrt(dx * dx + dy * dy);
}

class BBox {
  double south, west, north, east;
  BBox(this.south, this.west, this.north, this.east);

  factory BBox.empty() => BBox(90, 180, -90, -180);

  bool get isEmpty => south > north;

  void extend(double lat, double lon) {
    if (lat < south) south = lat;
    if (lat > north) north = lat;
    if (lon < west) west = lon;
    if (lon > east) east = lon;
  }

  /// Vergrößert die Box um [meters] in alle Richtungen.
  BBox expanded(double meters) {
    final dLat = meters / 110540.0;
    final midLat = (south + north) / 2;
    final dLon = meters / (111320.0 * math.cos(_rad(midLat)));
    return BBox(south - dLat, west - dLon, north + dLat, east + dLon);
  }

  bool contains(double lat, double lon) =>
      lat >= south && lat <= north && lon >= west && lon <= east;

  /// Teilt die Box in Kacheln mit maximal [maxDeg] Grad Kantenlänge.
  List<BBox> tiles(double maxDeg) {
    final ny = math.max(1, ((north - south) / maxDeg).ceil());
    final nx = math.max(1, ((east - west) / maxDeg).ceil());
    final h = (north - south) / ny, w = (east - west) / nx;
    return [
      for (var y = 0; y < ny; y++)
        for (var x = 0; x < nx; x++)
          BBox(south + y * h, west + x * w, south + (y + 1) * h,
              west + (x + 1) * w)
    ];
  }

  List<double> toList() => [south, west, north, east];
  factory BBox.fromList(List l) => BBox((l[0] as num).toDouble(),
      (l[1] as num).toDouble(), (l[2] as num).toDouble(), (l[3] as num).toDouble());
}

/// Fläche aus mehreren Ringen (äußere und innere). Punkt-in-Polygon nach
/// der Even-Odd-Regel über alle Ringe – damit funktionieren Löcher und
/// Multipolygone ohne Unterscheidung von äußeren/inneren Ringen.
class AreaPolygon {
  /// Jeder Ring: [lat0, lon0, lat1, lon1, ...]
  final List<List<double>> rings;
  late final BBox bbox;

  AreaPolygon(this.rings) {
    bbox = BBox.empty();
    for (final r in rings) {
      for (var i = 0; i + 1 < r.length; i += 2) {
        bbox.extend(r[i], r[i + 1]);
      }
    }
  }

  bool contains(double lat, double lon) {
    if (rings.isEmpty || !bbox.contains(lat, lon)) return false;
    var inside = false;
    for (final r in rings) {
      final n = r.length ~/ 2;
      if (n < 3) continue;
      var j = n - 1;
      for (var i = 0; i < n; i++) {
        final yi = r[2 * i], xi = r[2 * i + 1];
        final yj = r[2 * j], xj = r[2 * j + 1];
        if (((yi > lat) != (yj > lat)) &&
            (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
          inside = !inside;
        }
        j = i;
      }
    }
    return inside;
  }

  /// Liest GeoJSON (Polygon oder MultiPolygon) ein.
  static List<List<double>> ringsFromGeoJson(Map<String, dynamic> geo) {
    final type = geo['type'];
    final coords = geo['coordinates'];
    final out = <List<double>>[];
    void addRing(List ring) {
      final r = <double>[];
      for (final p in ring) {
        r.add((p[1] as num).toDouble());
        r.add((p[0] as num).toDouble());
      }
      out.add(r);
    }

    if (type == 'Polygon') {
      for (final ring in coords as List) {
        addRing(ring as List);
      }
    } else if (type == 'MultiPolygon') {
      for (final poly in coords as List) {
        for (final ring in poly as List) {
          addRing(ring as List);
        }
      }
    }
    return out;
  }
}
