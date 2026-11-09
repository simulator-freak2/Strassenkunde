import 'dart:math' as math;

import 'geo.dart';
import 'road_graph.dart';
import 'router.dart';
import 'text_norm.dart';

enum ClosureLevel { none, relevant, all }

extension ClosureLevelLabel on ClosureLevel {
  String get label => switch (this) {
        ClosureLevel.none => 'Keine Sperrungen',
        ClosureLevel.relevant => 'Stufe 1: nur relevante Sperrungen',
        ClosureLevel.all => 'Stufe 2: relevante + zusätzliche Sperrungen',
      };
}

/// Eine Straßensperrung (ein oder mehrere zusammenhängende Kanten).
class Closure {
  final List<int> edges;
  final String street;
  final String description;
  final bool relevant;
  Closure(this.edges, this.street, this.description, this.relevant);
}

class TrainingOptions {
  final Vehicle vehicle;
  final ClosureLevel closureLevel;
  final bool objects;
  final bool streets;
  final Set<PoiCategory> categories;
  final int toleranceSec;

  const TrainingOptions({
    this.vehicle = Vehicle.pkw,
    this.closureLevel = ClosureLevel.none,
    this.objects = true,
    this.streets = true,
    this.categories = const {
      PoiCategory.hotel,
      PoiCategory.school,
      PoiCategory.nursingHome,
      PoiCategory.hospital
    },
    this.toleranceSec = 120,
  });
}

class Task {
  final StartPoint start;
  final Target target;
  final List<Closure> closures;
  final RouteResult optimal;
  final double timeWithoutClosures;
  final Router router; // inkl. Sperrungen
  Task(this.start, this.target, this.closures, this.optimal,
      this.timeWithoutClosures, this.router);

  /// Startpunkt für die nächste Aufgabe, wenn vom letzten Ziel aus weiter
  /// gefahren wird.
  StartPoint get endPoint {
    final e = target.type == TargetType.object
        ? target.targetEdge
        : optimal.directedEdges.last >> 1;
    return StartPoint(e, target.lat, target.lon, target.title);
  }
}

class Evaluation {
  final UserRouteCheck check;
  final bool correct;
  final double diffS; // Mehrzeit gegenüber der schnellsten Route
  final List<String> input;
  Evaluation(this.check, this.correct, this.diffS, this.input);
}

/// Erzeugt Aufgaben (Ziel + Sperrungen) und bewertet Eingaben.
class TaskGenerator {
  final RoadGraph g;
  final math.Random rng;
  late final List<Target> _objectTargets;
  late final List<Target> _streetTargets;

  TaskGenerator(this.g, [math.Random? rng]) : rng = rng ?? math.Random() {
    _objectTargets = [];
    for (final p in g.pois) {
      if (!p.inArea || p.edge < 0) continue;
      _objectTargets.add(Target(
        type: TargetType.object,
        title: p.name,
        detail: p.category.label,
        address: p.address,
        key: 'o:${p.category.index}:${p.name}',
        lat: p.lat,
        lon: p.lon,
        targetEdge: p.edge,
        nodes: {g.eFrom[p.edge], g.eTo[p.edge]},
        edges: {p.edge},
        category: p.category,
      ));
    }
    final groups = <int, List<int>>{};
    for (var e = 0; e < g.edgeCount; e++) {
      if (g.eInArea[e] == 0 || g.eName[e] < 0) continue;
      final key = g.eName[e] * 100000 + (g.eLoc[e] + 1);
      groups.putIfAbsent(key, () => []).add(e);
    }
    final locCount = <int, Set<int>>{};
    for (final k in groups.keys) {
      locCount.putIfAbsent(k ~/ 100000, () => {}).add(k % 100000);
    }
    _streetTargets = [];
    groups.forEach((key, edges) {
      final nameIdx = key ~/ 100000;
      final locIdx = key % 100000 - 1;
      final name = g.names[nameIdx];
      final loc = locIdx >= 0 ? g.localities[locIdx] : null;
      final total = edges.fold(0.0, (s, e) => s + g.eLength[e]);
      if (total < 40) return; // winzige Stücke ignorieren
      final mid = edges[edges.length ~/ 2];
      final (lat, lon) = g.edgeMid(mid);
      _streetTargets.add(Target(
        type: TargetType.street,
        title: name,
        detail: loc != null ? 'Straße in $loc' : 'Straße',
        address: '',
        key: 's:$name:${loc ?? ''}',
        lat: lat,
        lon: lon,
        targetEdge: -1,
        nodes: {for (final e in edges) ...[g.eFrom[e], g.eTo[e]]},
        edges: edges.toSet(),
        ambiguous: (locCount[nameIdx]?.length ?? 1) > 1,
      ));
    });
  }

  int get objectCount => _objectTargets.length;
  int get streetCount => _streetTargets.length;

  int objectCountFor(Set<PoiCategory> cats) =>
      _objectTargets.where((t) => cats.contains(t.category)).length;

  /// Erzeugt eine neue Aufgabe. [stats] enthält je Ziel-Schlüssel die Anzahl
  /// falscher (negativ: richtiger) Antworten, um schwache Ziele öfter zu
  /// wählen.
  Task? next(StartPoint start, TrainingOptions o,
      {Map<String, int> stats = const {}, Set<String> avoid = const {}}) {
    final pool = <Target>[
      if (o.objects)
        ..._objectTargets.where((t) => o.categories.contains(t.category)),
      if (o.streets) ..._streetTargets,
    ];
    if (pool.isEmpty) return null;
    final base = Router(g, o.vehicle);
    for (var attempt = 0; attempt < 40; attempt++) {
      final t = _weightedPick(pool, stats, avoid);
      if (start.edges.any(t.edges.contains)) continue;
      if (distanceM(start.lat, start.lon, t.lat, t.lon) < 250) continue;
      final opt = base.fastest(start, t);
      if (opt == null || opt.timeS < 45) continue;
      final closures = <Closure>[];
      var router = base;
      var route = opt;
      if (o.closureLevel != ClosureLevel.none) {
        final want = 1 + (rng.nextDouble() < 0.35 ? 1 : 0);
        for (var k = 0; k < want; k++) {
          final c = _relevantClosure(router, route, start, t);
          if (c == null) break;
          closures.add(c.$1);
          router = c.$2;
          route = c.$3;
        }
        // Ohne wirksame Sperrung lieber ein anderes Ziel wählen.
        if (closures.isEmpty && attempt < 30) continue;
        if (o.closureLevel == ClosureLevel.all) {
          final count = 2 + rng.nextInt(3);
          closures.addAll(_irrelevantClosures(route, start, t, closures, count));
          router = router.withClosed({for (final c in closures) ...c.edges});
        }
        closures.shuffle(rng);
      }
      return Task(start, t, closures, route, opt.timeS, router);
    }
    return null;
  }

  Target _weightedPick(
      List<Target> pool, Map<String, int> stats, Set<String> avoid) {
    double w(Target t) {
      if (avoid.contains(t.key)) return 0.05;
      final s = stats[t.key] ?? 0;
      return (1.0 + s * 1.5).clamp(0.3, 6.0);
    }

    final total = pool.fold(0.0, (s, t) => s + w(t));
    var r = rng.nextDouble() * total;
    for (final t in pool) {
      r -= w(t);
      if (r <= 0) return t;
    }
    return pool.last;
  }

  bool _sameStreet(int a, int b) {
    if (g.eName[a] >= 0) return g.eName[a] == g.eName[b];
    return g.eRef[a] >= 0 && g.eRef[a] == g.eRef[b];
  }

  /// Erweitert eine Kante zu einem Abschnitt zwischen zwei Querstraßen.
  List<int> _segment(int e) {
    final seg = <int>[e];
    for (final startNode in [g.eFrom[e], g.eTo[e]]) {
      var cur = e;
      var node = startNode;
      for (var step = 0; step < 6; step++) {
        if (g.crossStreetAt(node, cur) != null) break;
        final next = g
            .edgesAtNode(node)
            .where((x) => x != cur && _sameStreet(x, e) && !seg.contains(x))
            .toList();
        if (next.length != 1) break;
        cur = next.first;
        seg.add(cur);
        node = g.eFrom[cur] == node ? g.eTo[cur] : g.eFrom[cur];
      }
    }
    return seg;
  }

  String _describe(List<int> seg) {
    final e = seg.first;
    final street = g.label(e)!;
    // Endknoten des Abschnitts bestimmen (Knoten, die nur einmal vorkommen)
    final count = <int, int>{};
    for (final x in seg) {
      count[g.eFrom[x]] = (count[g.eFrom[x]] ?? 0) + 1;
      count[g.eTo[x]] = (count[g.eTo[x]] ?? 0) + 1;
    }
    final ends = count.entries.where((m) => m.value == 1).map((m) => m.key).toList();
    final crosses = <String>[];
    final segSet = seg.toSet();
    for (final n in ends) {
      final edgeAt = seg.firstWhere((x) => g.eFrom[x] == n || g.eTo[x] == n);
      final c = g.crossStreetAt(n, edgeAt) ?? _nearestCross(n, e, segSet);
      if (c != null && !crosses.contains(c)) crosses.add(c);
    }
    final loc = g.eLoc[e] >= 0 ? ' (${g.localities[g.eLoc[e]]})' : '';
    if (crosses.length >= 2) {
      return '$street$loc zwischen ${crosses[0]} und ${crosses[1]}';
    }
    if (crosses.length == 1) return '$street$loc, Höhe ${crosses[0]}';
    // Notfalls nächstgelegene andere Straße als Orientierung nennen
    final (mla, mlo) = g.edgeMid(seg[seg.length ~/ 2]);
    String? near;
    var nearD = 500.0;
    for (var x = 0; x < g.edgeCount; x++) {
      final l = g.label(x);
      if (l == null || l == street) continue;
      final (la, lo) = g.edgeMid(x);
      if ((la - mla).abs() > 0.005 || (lo - mlo).abs() > 0.008) continue;
      final d = distanceM(mla, mlo, la, lo);
      if (d < nearD) {
        nearD = d;
        near = l;
      }
    }
    if (near != null) return '$street$loc, Abschnitt nahe $near';
    return '$street$loc, Teilabschnitt';
  }

  /// Sucht entlang derselben Straße (weg vom gesperrten Abschnitt) die
  /// nächste benannte Querstraße – für verständliche Beschreibungen, wenn
  /// direkt am Abschnittsende nur Zufahrten oder Fahrbahnteilungen liegen.
  String? _nearestCross(int startNode, int streetEdge, Set<int> exclude) {
    final dist = <int, double>{startNode: 0};
    final queue = <int>[startNode];
    String? best;
    var bestD = double.infinity;
    while (queue.isNotEmpty) {
      queue.sort((a, b) => dist[b]!.compareTo(dist[a]!));
      final n = queue.removeLast();
      final d = dist[n]!;
      if (d > 800 || d >= bestD) break;
      for (final x in g.edgesAtNode(n)) {
        if (exclude.contains(x)) continue;
        final other = g.eFrom[x] == n ? g.eTo[x] : g.eFrom[x];
        if (_sameStreet(x, streetEdge)) {
          final nd = d + g.eLength[x];
          if (nd < (dist[other] ?? double.infinity)) {
            dist[other] = nd;
            queue.add(other);
          }
        } else if (n != startNode) {
          final c = g.crossStreetAt(n, streetEdge);
          if (c != null && d < bestD) {
            best = c;
            bestD = d;
          }
        }
      }
    }
    return best;
  }

  (Closure, Router, RouteResult)? _relevantClosure(
      Router router, RouteResult route, StartPoint start, Target t) {
    final dirs = route.directedEdges;
    if (dirs.length < 4) return null;
    final cand = <int>[];
    for (var i = 1; i < dirs.length - 1; i++) {
      final e = dirs[i] >> 1;
      if (g.label(e) == null || g.eInArea[e] == 0) continue;
      if (start.edges.contains(e) || t.edges.contains(e)) continue;
      cand.add(e);
    }
    cand.shuffle(rng);
    for (final e in cand.take(10)) {
      final seg = _segment(e);
      if (seg.any(start.edges.contains) || seg.any(t.edges.contains)) continue;
      final r2 = router.withClosed(seg.toSet());
      final alt = r2.fastest(start, t);
      if (alt == null || alt.timeS < route.timeS + 0.5) continue;
      return (
        Closure(seg, g.label(e)!, _describe(seg), true),
        r2,
        alt,
      );
    }
    return null;
  }

  List<Closure> _irrelevantClosures(RouteResult route, StartPoint start,
      Target t, List<Closure> existing, int count) {
    final onRoute = {for (final d in route.directedEdges) d >> 1};
    final used = {for (final c in existing) ...c.edges};
    final box = BBox.empty();
    box.extend(start.lat, start.lon);
    box.extend(t.lat, t.lon);
    for (final d in route.directedEdges) {
      final (la, lo) = g.edgeMid(d >> 1);
      box.extend(la, lo);
    }
    final area = box.expanded(700);
    final cand = <int>[];
    for (var e = 0; e < g.edgeCount; e++) {
      if (g.label(e) == null || g.eInArea[e] == 0) continue;
      if (onRoute.contains(e) || used.contains(e)) continue;
      final (la, lo) = g.edgeMid(e);
      if (area.contains(la, lo)) cand.add(e);
    }
    cand.shuffle(rng);
    final out = <Closure>[];
    final routeStreets = {for (final c in existing) c.street};
    for (final e in cand) {
      if (out.length >= count) break;
      final seg = _segment(e);
      if (seg.any((x) => onRoute.contains(x) || used.contains(x))) continue;
      if (seg.any(start.edges.contains) || seg.any(t.edges.contains)) continue;
      final street = g.label(e)!;
      if (routeStreets.contains(street)) continue;
      routeStreets.add(street);
      used.addAll(seg);
      out.add(Closure(seg, street, _describe(seg), false));
    }
    return out;
  }

  /// Bewertet die eingegebene Straßenfolge.
  Evaluation evaluate(Task task, List<String> input, int toleranceSec) {
    final check = task.router.checkUserRoute(task.start, task.target, input);
    if (check.route == null) {
      return Evaluation(check, false, double.infinity, input);
    }
    final diff = check.route!.timeS - task.optimal.timeS;
    return Evaluation(check, diff <= toleranceSec, diff, input);
  }

  /// Hinweis für den leichten Modus: Ist die bisherige Eingabe der Anfang
  /// der schnellsten Route?
  bool isOnOptimalPath(Task task, List<String> input) {
    final legs = task.optimal
        .legs(g, task.router.vehicle)
        .where((l) => l.label != null)
        .toList();
    bool alignFrom(int off) {
      for (var i = 0; i < input.length; i++) {
        if (off + i >= legs.length) return false;
        if (!legs[off + i].keys.contains(normalizeStreet(input[i]))) {
          return false;
        }
      }
      return true;
    }

    if (alignFrom(0)) return true;
    // Startstraße muss nicht eingegeben werden
    final startLabels = {
      for (final e in task.start.edges)
        if (e >= 0 && g.label(e) != null) g.label(e)!
    };
    return legs.isNotEmpty &&
        startLabels.contains(legs.first.label) &&
        alignFrom(1);
  }

  /// Alle Straßennamen und -nummern für die Autovervollständigung.
  List<String> allStreetLabels() {
    final s = <String>{...g.names};
    for (final r in g.refs) {
      s.addAll(splitOsmValues(r));
    }
    return s.toList()..sort();
  }
}
