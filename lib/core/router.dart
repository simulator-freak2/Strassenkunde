import 'dart:typed_data';

import 'geo.dart';
import 'road_graph.dart';
import 'text_norm.dart';

/// Minimaler Binär-Heap für (Kosten, Wert).
class _Heap {
  final _cost = <double>[];
  final _val = <int>[];
  bool get isEmpty => _cost.isEmpty;

  void push(double c, int v) {
    _cost.add(c);
    _val.add(v);
    var i = _cost.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_cost[p] <= _cost[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  (double, int) pop() {
    final c = _cost[0], v = _val[0];
    final lc = _cost.removeLast(), lv = _val.removeLast();
    if (_cost.isNotEmpty) {
      _cost[0] = lc;
      _val[0] = lv;
      var i = 0;
      final n = _cost.length;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < n && _cost[l] < _cost[m]) m = l;
        if (r < n && _cost[r] < _cost[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return (c, v);
  }

  void _swap(int a, int b) {
    final c = _cost[a];
    _cost[a] = _cost[b];
    _cost[b] = c;
    final v = _val[a];
    _val[a] = _val[b];
    _val[b] = v;
  }
}

/// Startpunkt: eine Kante (man steht "auf" dieser Straße).
class StartPoint {
  final int edge;
  final double lat, lon;
  final String label;
  StartPoint(this.edge, this.lat, this.lon, this.label);
}

enum TargetType { object, street }

class Target {
  final TargetType type;
  final String title; // z. B. "Grundschule Am Park"
  final String detail; // z. B. "Schule" oder "Straße in Nordstadt"
  final String address; // Adresse bei Objekten (kann leer sein)
  final PoiCategory? category;
  final bool ambiguous; // Straßenname kommt in mehreren Orten vor
  final String key; // für die Lernstatistik
  final double lat, lon;
  final int targetEdge; // bei Objekten
  final Set<int> nodes; // Zielknoten
  final Set<int> edges; // Zielkanten (Straße bzw. Objekt-Kante)

  Target({
    required this.type,
    required this.title,
    required this.detail,
    this.address = '',
    this.category,
    this.ambiguous = false,
    required this.key,
    required this.lat,
    required this.lon,
    required this.targetEdge,
    required this.nodes,
    required this.edges,
  });
}

/// Abschnitt einer Route mit gleichem Straßennamen.
class RouteLeg {
  final String? label;
  final Set<String> keys; // normalisierte Namen/Nummern zum Vergleich
  double lengthM;
  double timeS;
  RouteLeg(this.label, this.keys, this.lengthM, this.timeS);
}

class RouteResult {
  final List<int> directedEdges;
  final double timeS;
  RouteResult(this.directedEdges, this.timeS);

  double lengthM(RoadGraph g) =>
      directedEdges.fold(0.0, (s, d) => s + g.eLength[d >> 1]);

  /// Zusammengefasste Straßenfolge (kurze namenlose Stücke ausgeblendet).
  List<RouteLeg> legs(RoadGraph g, Vehicle v) {
    final raw = <RouteLeg>[];
    for (final d in directedEdges) {
      final e = d >> 1;
      final lbl = g.label(e);
      final t = g.edgeTime(e, v);
      final keys = <String>{
        if (g.eName[e] >= 0) normalizeStreet(g.names[g.eName[e]]),
        if (g.eRef[e] >= 0)
          for (final r in splitOsmValues(g.refs[g.eRef[e]])) normalizeStreet(r),
      };
      if (raw.isNotEmpty && raw.last.label == lbl) {
        raw.last.lengthM += g.eLength[e];
        raw.last.timeS += t;
        raw.last.keys.addAll(keys);
      } else {
        raw.add(RouteLeg(lbl, keys, g.eLength[e], t));
      }
    }
    // kurze namenlose Stücke entfernen und Nachbarn verschmelzen
    final out = <RouteLeg>[];
    for (final l in raw) {
      if (l.label == null && l.lengthM < 150) {
        if (out.isNotEmpty) {
          out.last.lengthM += l.lengthM;
          out.last.timeS += l.timeS;
        }
        continue;
      }
      if (out.isNotEmpty && out.last.label == l.label) {
        out.last.lengthM += l.lengthM;
        out.last.timeS += l.timeS;
      } else {
        out.add(l);
      }
    }
    return out;
  }

  /// Nur die benannten Straßen in Reihenfolge.
  List<String> streetSequence(RoadGraph g, Vehicle v) => [
        for (final l in legs(g, v))
          if (l.label != null) l.label!
      ];
}

/// Ergebnis der Prüfung einer vom Nutzer eingegebenen Route.
class UserRouteCheck {
  final RouteResult? route; // beste Route entlang der Eingabe
  final String? error; // Erklärung, falls nicht befahrbar
  final List<String> unknownStreets;
  UserRouteCheck({this.route, this.error, this.unknownStreets = const []});
}

/// Routenberechnung nach Fahrzeit mit Abbiegezeiten, Einbahnstraßen,
/// Fahrzeugbeschränkungen und Sperrungen.
class Router {
  final RoadGraph g;
  final Vehicle vehicle;
  final Set<int> closed; // gesperrte (ungerichtete) Kanten

  Router(this.g, this.vehicle, [Set<int>? closed]) : closed = closed ?? {};

  Router withClosed(Set<int> extra) =>
      Router(g, vehicle, {...closed, ...extra});

  bool usable(int e) => !closed.contains(e) && g.allowed(e, vehicle);

  double edgeTime(int e) => g.edgeTime(e, vehicle);

  /// Zusatzzeit beim Übergang von [dIn] auf [dOut] in Sekunden, oder null
  /// wenn verboten (Wenden außer in Sackgassen).
  double? turnCost(int dIn, int dOut) {
    final node = g.endNode(dIn);
    if ((dIn >> 1) == (dOut >> 1) && dIn != dOut) {
      return g.degree(node) == 1 ? 25.0 : null;
    }
    if (g.degree(node) <= 2) return 0; // nur Fortsetzung
    final a = angleDiff(g.endBearing(dIn), g.startBearing(dOut));
    final abs = a.abs();
    if (abs < 35) return 0;
    if (a > 0) return abs <= 135 ? 6 : 12; // rechts
    return abs <= 135 ? 10 : 15; // links
  }

  Iterable<int> _startStates(StartPoint s) sync* {
    final e = s.edge;
    if (!g.allowed(e, vehicle)) return;
    yield e * 2;
    if (g.eOneway[e] == 0) yield e * 2 + 1;
  }

  /// Ziel erreicht, sobald man in die Zielstraße bzw. das Straßenstück
  /// des Objekts eingefahren ist.
  bool _isGoal(int d, Target t) => t.edges.contains(d >> 1);

  /// Schnellste Route vom Start zum Ziel.
  RouteResult? fastest(StartPoint start, Target target) {
    final n = g.edgeCount * 2;
    final dist = Float64List(n)..fillRange(0, n, double.infinity);
    final prev = Int32List(n)..fillRange(0, n, -1);
    final heap = _Heap();
    for (final d in _startStates(start)) {
      final c = edgeTime(d >> 1) * 0.5;
      dist[d] = c;
      heap.push(c, d);
    }
    while (!heap.isEmpty) {
      final (c, d) = heap.pop();
      if (c > dist[d]) continue;
      if (_isGoal(d, target)) return _build(prev, d, c);
      for (final d2 in g.outgoing(g.endNode(d))) {
        final e2 = d2 >> 1;
        if (!usable(e2)) continue;
        final tc = turnCost(d, d2);
        if (tc == null) continue;
        final nc = c + tc + edgeTime(e2);
        if (nc < dist[d2]) {
          dist[d2] = nc;
          prev[d2] = d;
          heap.push(nc, d2);
        }
      }
    }
    return null;
  }

  RouteResult _build(Int32List prev, int last, double cost) {
    final list = <int>[];
    var d = last;
    while (d >= 0) {
      list.add(d);
      d = prev[d];
    }
    return RouteResult(list.reversed.toList(), cost);
  }

  /// Ordnet eingegebene Straßennamen Namens-/Nummern-IDs zu.
  (List<Set<int>>, List<Set<int>>, List<String>) _resolve(List<String> streets) {
    final nameSets = <Set<int>>[], refSets = <Set<int>>[];
    final unknown = <String>[];
    for (final s in streets) {
      final k = normalizeStreet(s);
      final ns = g.nameIndex[k] ?? <int>{};
      final rs = g.refIndex[k] ?? <int>{};
      if (ns.isEmpty && rs.isEmpty) unknown.add(s);
      nameSets.add(ns);
      refSets.add(rs);
    }
    return (nameSets, refSets, unknown);
  }

  /// Sucht die schnellste Route, die genau der eingegebenen Straßenfolge
  /// folgt. Namenlose Stücke (Zufahrten, Auffahrten) dürfen dazwischen
  /// beliebig benutzt werden.
  UserRouteCheck checkUserRoute(
      StartPoint start, Target target, List<String> streets) {
    if (streets.isEmpty) {
      return UserRouteCheck(error: 'Es wurde keine Straße eingegeben.');
    }
    final (nameSets, refSets, unknown) = _resolve(streets);
    if (unknown.isNotEmpty) {
      return UserRouteCheck(
          error: 'Unbekannte Straße(n): ${unknown.join(', ')}',
          unknownStreets: unknown);
    }
    final res = _constrainedSearch(start, nameSets, refSets, target);
    if (res.goal != null) {
      return UserRouteCheck(route: res.goal);
    }
    // Fehlerdiagnose
    final m = res.maxIndex;
    String msg;
    if (m < 0) {
      msg = 'Vom Startpunkt aus kommst du nicht auf „${streets[0]}“.';
    } else if (m < streets.length - 1) {
      msg = 'Von „${streets[m]}“ gibt es keine befahrbare Verbindung '
          'auf „${streets[m + 1]}“.';
    } else {
      msg = 'Über „${streets.last}“ erreichst du das Ziel nicht.';
    }
    if (closed.isNotEmpty) {
      final free = Router(g, vehicle)
          ._constrainedSearch(start, nameSets, refSets, target);
      if (free.goal != null) msg += ' (Grund: Sperrung auf dem Weg)';
    }
    return UserRouteCheck(error: msg);
  }

  /// Straßen, auf die man nach der bisherigen Eingabe als Nächstes
  /// abbiegen kann (für den leichten Lernmodus).
  List<String> nextStreetOptions(StartPoint start, List<String> streets) {
    final (nameSets, refSets, unknown) = _resolve(streets);
    if (unknown.isNotEmpty) return const [];
    final res = _constrainedSearch(start, nameSets, refSets, null);
    final states = res.lastIndexStates;
    final opts = <String>{};
    final currentKeys = streets.isEmpty ? <String>{} : {normalizeStreet(streets.last)};
    if (streets.isEmpty) {
      final l = g.label(start.edge);
      if (l != null) opts.add(l);
    }
    final visitedNodes = <int>{};
    void collect(int node, int depth) {
      if (!visitedNodes.add(node * 4 + depth)) return;
      for (final d2 in g.outgoing(node)) {
        final e2 = d2 >> 1;
        if (!usable(e2)) continue;
        final l = g.label(e2);
        if (l == null) {
          if (depth < 2) collect(g.endNode(d2), depth + 1);
          continue;
        }
        if (currentKeys.contains(normalizeStreet(l))) continue;
        opts.add(l);
      }
    }

    for (final d in states) {
      collect(g.endNode(d), 0);
    }
    final list = opts.toList()..sort();
    return list;
  }

  _ConstrainedResult _constrainedSearch(StartPoint start,
      List<Set<int>> nameSets, List<Set<int>> refSets, Target? target) {
    final n = nameSets.length;
    bool matches(int e, int i) =>
        nameSets[i].contains(g.eName[e]) || refSets[i].contains(g.eRef[e]);

    final se = start.edge;
    // Auf der Straße des Startpunkts darf man ohne Eingabe weiterfahren.
    bool sameAsStart(int e) =>
        (g.eName[se] >= 0 && g.eName[e] == g.eName[se]) ||
        (g.eName[se] < 0 && g.eRef[se] >= 0 && g.eRef[e] == g.eRef[se]);
    final dist = <int, double>{};
    final prev = <int, int>{};
    final heap = _Heap();
    var maxIndex = -1;
    void push(int key, double c, int from) {
      final old = dist[key];
      if (old == null || c < old) {
        dist[key] = c;
        prev[key] = from;
        heap.push(c, key);
      }
    }

    for (final d in _startStates(start)) {
      final c = edgeTime(d >> 1) * 0.5;
      // Die Startstraße gilt als befahren, wenn sie der ersten Eingabe
      // entspricht; andernfalls darf man von ihr auf die erste Straße abbiegen.
      push(d * (n + 1) + 0, c, -1);
      if (n > 0 && matches(d >> 1, 0)) push(d * (n + 1) + 1, c, -1);
    }
    // Zustand i: Anzahl bereits "erreichter" Eingabestraßen (0..n).
    final lastStates = <int>[];
    while (!heap.isEmpty) {
      final (c, key) = heap.pop();
      if (c > (dist[key] ?? double.infinity)) continue;
      final d = key ~/ (n + 1), i = key % (n + 1);
      if (i - 1 > maxIndex) maxIndex = i - 1;
      if (i == n) {
        if (target != null && _isGoal(d, target)) {
          // Route rekonstruieren
          final list = <int>[];
          int? k = key;
          while (k != null && k >= 0) {
            list.add(k ~/ (n + 1));
            k = prev[k];
          }
          return _ConstrainedResult(
              RouteResult(list.reversed.toList(), c), maxIndex, lastStates);
        }
        lastStates.add(d);
      }
      for (final d2 in g.outgoing(g.endNode(d))) {
        final e2 = d2 >> 1;
        if (!usable(e2)) continue;
        final tc = turnCost(d, d2);
        if (tc == null) continue;
        final nc = c + tc + edgeTime(e2);
        // auf der aktuellen Straße bleiben (oder namenloses Stück)
        if (g.isUnnamed(e2) ||
            (i >= 1 && matches(e2, i - 1)) ||
            (i == 0 && sameAsStart(e2))) {
          push(d2 * (n + 1) + i, nc, key);
        }
        // auf die nächste eingegebene Straße abbiegen
        if (i < n && matches(e2, i)) {
          push(d2 * (n + 1) + i + 1, nc, key);
        }
      }
    }
    return _ConstrainedResult(null, maxIndex, lastStates);
  }

  /// Dijkstra ohne Ziel: Fahrzeit vom Start zu allen Kanten (für die
  /// Zielauswahl).
  Float64List reachTimes(StartPoint start) {
    final n = g.edgeCount * 2;
    final dist = Float64List(n)..fillRange(0, n, double.infinity);
    final heap = _Heap();
    for (final d in _startStates(start)) {
      final c = edgeTime(d >> 1) * 0.5;
      dist[d] = c;
      heap.push(c, d);
    }
    while (!heap.isEmpty) {
      final (c, d) = heap.pop();
      if (c > dist[d]) continue;
      for (final d2 in g.outgoing(g.endNode(d))) {
        final e2 = d2 >> 1;
        if (!usable(e2)) continue;
        final tc = turnCost(d, d2);
        if (tc == null) continue;
        final nc = c + tc + edgeTime(e2);
        if (nc < dist[d2]) {
          dist[d2] = nc;
          heap.push(nc, d2);
        }
      }
    }
    return dist;
  }
}

class _ConstrainedResult {
  final RouteResult? goal;
  final int maxIndex;
  final List<int> lastIndexStates;
  _ConstrainedResult(this.goal, this.maxIndex, this.lastIndexStates);
}
