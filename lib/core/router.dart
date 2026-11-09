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

/// Erlaubte Abbiegerichtung beim Verlassen einer Ausfahrt.
enum ExitTurn { both, right, left }

extension ExitTurnLabel on ExitTurn {
  String get label => switch (this) {
        ExitTurn.both => 'links und rechts',
        ExitTurn.right => 'nur rechts',
        ExitTurn.left => 'nur links',
      };
}

/// Eine Ausfahrt des Startpunkts (z. B. Haupt- oder Nebenausfahrt des
/// Gerätehauses).
class StartExit {
  final String label;
  final int edge;
  final bool forward; // darf in Digitalisierungsrichtung fahren
  final bool backward; // darf entgegen fahren
  final double penaltyS; // Zuschlag (Nebenausfahrten)
  final double forwardTurnS, backwardTurnS; // Abbiegezeit beim Ausfahren
  final double lat, lon;
  final bool main;

  StartExit({
    required this.label,
    required this.edge,
    this.forward = true,
    this.backward = true,
    this.penaltyS = 0,
    this.forwardTurnS = 0,
    this.backwardTurnS = 0,
    required this.lat,
    required this.lon,
    this.main = false,
  });

  /// Erzeugt eine Ausfahrt aus Koordinaten. Die Abbiegerichtung wird aus der
  /// Lage der Ausfahrt relativ zum Gebäude bestimmt.
  factory StartExit.at(RoadGraph g,
      {required String label,
      required double stationLat,
      required double stationLon,
      required double lat,
      required double lon,
      ExitTurn turn = ExitTurn.both,
      double penaltyS = 0,
      bool main = false}) {
    final e = g.nearestEdge(lat, lon);
    var fwd = true, back = true;
    double fwdTurn = 0, backTurn = 0;
    final outDist = distanceM(stationLat, stationLon, lat, lon);
    if (e >= 0 && outDist > 3) {
      final out = bearingDeg(stationLat, stationLon, lat, lon);
      final road = g.bearingNear(e, lat, lon);
      final a = angleDiff(out, road); // > 0: vorwärts = rechts abbiegen
      final fwdIsRight = a > 0;
      fwdTurn = fwdIsRight ? 6 : 10;
      backTurn = fwdIsRight ? 10 : 6;
      if (turn == ExitTurn.right) {
        fwd = fwdIsRight;
        back = !fwdIsRight;
      } else if (turn == ExitTurn.left) {
        fwd = !fwdIsRight;
        back = fwdIsRight;
      }
    }
    return StartExit(
      label: label,
      edge: e,
      forward: fwd,
      backward: back,
      penaltyS: penaltyS,
      forwardTurnS: fwdTurn,
      backwardTurnS: backTurn,
      lat: lat,
      lon: lon,
      main: main,
    );
  }
}

/// Startpunkt: eine Kante (man steht "auf" dieser Straße) oder mehrere
/// Ausfahrten.
class StartPoint {
  final int edge; // Hauptkante (bei Ausfahrten: die der Hauptausfahrt)
  final double lat, lon;
  final String label;
  final List<StartExit> exits;
  StartPoint(this.edge, this.lat, this.lon, this.label,
      {this.exits = const []});

  /// Alle Kanten, auf denen man startet.
  Set<int> get edges => exits.isEmpty ? {edge} : {for (final x in exits) x.edge};

  /// Name der Ausfahrt, über die eine Route beginnt (oder null).
  String? exitLabelFor(RouteResult r) {
    if (exits.length < 2 || r.directedEdges.isEmpty) return null;
    final d = r.directedEdges.first;
    StartExit? best;
    for (final x in exits) {
      if (x.edge != d >> 1) continue;
      if (best == null || x.penaltyS < best.penaltyS) best = x;
    }
    return best?.label;
  }
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

  /// Start-Zustände (gerichtete Kante, Anfangskosten).
  Iterable<(int, double)> _startStates(StartPoint s) sync* {
    if (s.exits.isEmpty) {
      final e = s.edge;
      if (!g.allowed(e, vehicle)) return;
      final c = edgeTime(e) * 0.5;
      yield (e * 2, c);
      if (g.eOneway[e] == 0) yield (e * 2 + 1, c);
      return;
    }
    for (final x in s.exits) {
      final e = x.edge;
      if (e < 0 || !usable(e)) continue;
      final c = edgeTime(e) * 0.5 + x.penaltyS;
      if (x.forward) yield (e * 2, c + x.forwardTurnS);
      if (x.backward && g.eOneway[e] == 0) yield (e * 2 + 1, c + x.backwardTurnS);
    }
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
    for (final (d, c) in _startStates(start)) {
      if (c < dist[d]) {
        dist[d] = c;
        heap.push(c, d);
      }
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
      for (final se in start.edges) {
        final l = se < 0 ? null : g.label(se);
        if (l != null) opts.add(l);
      }
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

    // Auf der Straße des Startpunkts (bzw. der Ausfahrten) darf man ohne
    // Eingabe weiterfahren.
    final startNames = <int>{}, startRefs = <int>{};
    for (final se in start.edges) {
      if (se < 0) continue;
      if (g.eName[se] >= 0) {
        startNames.add(g.eName[se]);
      } else if (g.eRef[se] >= 0) {
        startRefs.add(g.eRef[se]);
      }
    }
    bool sameAsStart(int e) =>
        (g.eName[e] >= 0 && startNames.contains(g.eName[e])) ||
        (g.eName[e] < 0 && g.eRef[e] >= 0 && startRefs.contains(g.eRef[e]));
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

    for (final (d, c) in _startStates(start)) {
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
    for (final (d, c) in _startStates(start)) {
      if (c < dist[d]) {
        dist[d] = c;
        heap.push(c, d);
      }
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
