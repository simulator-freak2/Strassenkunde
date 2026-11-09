import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strassenkunde/core/road_graph.dart';
import 'package:strassenkunde/core/router.dart';
import 'package:strassenkunde/core/osm_builder.dart';
import 'package:strassenkunde/core/text_norm.dart';
import 'package:strassenkunde/core/training.dart';
import 'package:strassenkunde/data/profile.dart';

import 'fixture.dart';

void main() {
  late RoadGraph g;
  late TaskGenerator gen;
  late StartPoint start;

  setUp(() {
    g = buildFixture();
    gen = TaskGenerator(g, math.Random(1));
    // Start: Ahornweg (Zeile 0) zwischen Spalte 0 und 1
    final e = g.nearestEdge(lat0, lon0 + 0.5 * dLon);
    start = StartPoint(e, lat0, lon0 + 0.5 * dLon, 'Gerätehaus');
  });

  Target school() {
    final p = g.pois.single;
    return Target(
      type: TargetType.object,
      title: p.name,
      detail: p.category.label,
      key: 'school',
      lat: p.lat,
      lon: p.lon,
      targetEdge: p.edge,
      nodes: {g.eFrom[p.edge], g.eTo[p.edge]},
      edges: {p.edge},
    );
  }

  test('Normalisierung von Straßennamen', () {
    expect(normalizeStreet('Hauptstr.'), normalizeStreet('Hauptstraße'));
    expect(normalizeStreet('hauptstrasse'), normalizeStreet('Hauptstraße'));
    expect(normalizeStreet('Karl-Marx-Str.'), normalizeStreet('Karl Marx Straße'));
    expect(normalizeStreet('B9'), normalizeStreet('B 9'));
    expect(normalizeStreet('Ostring'), isNot(normalizeStreet('Ostrasseing')));
  });

  test('Graph wird korrekt aufgebaut', () {
    expect(g.nodeCount, 36);
    expect(g.edgeCount, 60);
    expect(g.pois, hasLength(1));
    expect(g.label(g.pois.single.edge), 'Eichenweg');
    expect(g.localities, ['Testdorf']);
    expect(g.eInArea.every((v) => v == 1), isTrue);
  });

  test('Speichern und Laden ergibt denselben Graphen', () {
    final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    final g2 = RoadGraph.fromJson(json);
    expect(g2.edgeCount, g.edgeCount);
    expect(g2.names, g.names);
    final r1 = Router(g, Vehicle.pkw).fastest(start, school())!;
    final r2 = Router(g2, Vehicle.pkw).fastest(start, school())!;
    expect(r2.timeS, closeTo(r1.timeS, 0.01));
  });

  test('Schnellste Route und Eingabe der optimalen Straßenfolge', () {
    final router = Router(g, Vehicle.pkw);
    final opt = router.fastest(start, school())!;
    expect(opt.timeS, greaterThan(30));
    final seq = opt.streetSequence(g, Vehicle.pkw);
    expect(seq.last, 'Eichenweg');
    final check = router.checkUserRoute(start, school(), seq);
    expect(check.error, isNull);
    expect(check.route!.timeS, closeTo(opt.timeS, 0.5));
  });

  test('Einbahnstraße darf nicht entgegen der Richtung befahren werden', () {
    final router = Router(g, Vehicle.pkw);
    // Start oben am Fichtenweg (Zeile 5) nahe Spalte 3
    final e = g.nearestEdge(lat0 + 5 * dLat, lon0 + 2.5 * dLon);
    final s = StartPoint(e, lat0 + 5 * dLat, lon0 + 2.5 * dLon, 'Start');
    final target = Target(
      type: TargetType.street,
      title: 'Ahornweg',
      detail: '',
      key: 'x',
      lat: lat0,
      lon: lon0,
      targetEdge: -1,
      nodes: {},
      edges: {for (var c = 0; c < 5; c++) g.nearestEdge(lat0, lon0 + (c + 0.5) * dLon)},
    );
    final wrong = router.checkUserRoute(s, target, ['Fichtenweg', 'Einbahnweg', 'Ahornweg']);
    expect(wrong.route, isNull);
    expect(wrong.error, contains('Einbahnweg'));
    final ok = router.checkUserRoute(s, target, ['Fichtenweg', 'Gartenstraße', 'Ahornweg']);
    expect(ok.route, isNotNull);
  });

  test('Unbekannte Straße wird gemeldet', () {
    final c = Router(g, Vehicle.pkw).checkUserRoute(start, school(), ['Mondweg']);
    expect(c.unknownStreets, ['Mondweg']);
  });

  test('Nächste Straßen im leichten Modus', () {
    final r = Router(g, Vehicle.pkw);
    final first = r.nextStreetOptions(start, []);
    expect(first, containsAll(['Ahornweg', 'Amselstraße', 'Bachstraße']));
    final after = r.nextStreetOptions(start, ['Ahornweg']);
    expect(after, contains('Lindenstraße'));
    // Einbahnweg führt vom Ahornweg nach Norden -> erlaubt
    expect(after, contains('Einbahnweg'));
    expect(after, isNot(contains('Ahornweg')));
  });

  test('Relevante Sperrungen liegen auf der Route und verlängern sie', () {
    for (var seed = 0; seed < 10; seed++) {
      final gen = TaskGenerator(g, math.Random(seed));
      final t = gen.next(start,
          const TrainingOptions(closureLevel: ClosureLevel.relevant, streets: false));
      expect(t, isNotNull);
      expect(t!.closures, isNotEmpty);
      expect(t.closures.every((c) => c.relevant), isTrue);
      expect(t.optimal.timeS, greaterThan(t.timeWithoutClosures));
      // Route führt nicht über gesperrte Kanten
      final closed = {for (final c in t.closures) ...c.edges};
      expect(t.optimal.directedEdges.any((d) => closed.contains(d >> 1)), isFalse);
      expect(t.closures.first.description, contains('zwischen'));
    }
  });

  test('Stufe 2 fügt irrelevante Sperrungen hinzu, die die Route nicht ändern', () {
    final gen = TaskGenerator(g, math.Random(3));
    final t = gen.next(start,
        const TrainingOptions(closureLevel: ClosureLevel.all, streets: false))!;
    final irrelevant = t.closures.where((c) => !c.relevant).toList();
    expect(irrelevant, isNotEmpty);
    final onlyRelevant = Router(g, Vehicle.pkw,
        {for (final c in t.closures.where((c) => c.relevant)) ...c.edges});
    final r = onlyRelevant.fastest(t.start, t.target)!;
    expect(t.optimal.timeS, closeTo(r.timeS, 0.01));
  });

  test('Bewertung mit Toleranz', () {
    final t = gen.next(start, const TrainingOptions(streets: false))!;
    final seq = t.optimal.streetSequence(g, Vehicle.pkw);
    final ev = gen.evaluate(t, seq, 120);
    expect(ev.correct, isTrue);
    expect(gen.isOnOptimalPath(t, seq.take(1).toList()), isTrue);
    // Umweg über den Fichtenweg ganz im Norden
    final detour = gen.evaluate(
        t, ['Ahornweg', 'Amselstraße', 'Fichtenweg', 'Mühlenweg', 'Eichenweg'], 0);
    expect(detour.check.route, isNotNull);
    expect(detour.diffS, greaterThan(0));
    expect(detour.correct, isFalse);
  });

  test('LKW-Beschränkung', () {
    final b = fixtureElements();
    // Gartenstraße: max. 7,5 t
    final w = b.firstWhere((e) => e['id'] == 2002);
    (w['tags'] as Map)['maxweight'] = '7.5';
    expect(lkwAllowedFor(w['tags'] as Map<String, dynamic>), isFalse);
  });

  test('Profil: Speichern/Laden und Lernstand', () {
    final p = Profile('p1', 'Test');
    p.settings.closureLevel = ClosureLevel.all;
    p.settings.vehicle = Vehicle.lkw;
    final p2 = Profile.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    p2.recordResult('x', false);
    p2.recordResult('x', false);
    p2.recordResult('y', true);
    expect(p2.stats['x'], 4);
    expect(p2.stats['y'], -1);
    expect(p2.settings.closureLevel, ClosureLevel.all);
    expect(p2.settings.vehicle, Vehicle.lkw);
    final p3 = Profile.fromJson(jsonDecode(jsonEncode(p2.toJson())) as Map<String, dynamic>);
    p3.recordResult('x', true);
    expect(p3.stats['x'], 3);
    expect(p3.trainedTasks, 4);
  });

  group('Ausfahrten des Gerätehauses', () {
    // Gerätehaus mitten im Block zwischen Birkenweg (Zeile 1) und
    // Hauptstraße (Zeile 2), Spalte 2..3
    const sLat = lat0 + 1.5 * dLat, sLon = lon0 + 2.5 * dLon;
    StationPoint station({int penalty = 60, ExitTurn turn = ExitTurn.both}) =>
        StationPoint('FGH', sLat, sLon, sideExitPenaltySec: penalty, exits: [
          StationExit('Haupt Birkenweg', lat0 + dLat, sLon, main: true, turn: turn),
          StationExit('Neben Hauptstraße', lat0 + 2 * dLat, sLon),
        ]);
    Target fichtenweg() {
      final edges = {
        for (var c = 0; c < 5; c++) g.nearestEdge(lat0 + 5 * dLat, lon0 + (c + 0.5) * dLon)
      };
      return Target(
          type: TargetType.street,
          title: 'Fichtenweg',
          detail: '',
          key: 'f',
          lat: lat0 + 5 * dLat,
          lon: sLon,
          targetEdge: -1,
          nodes: {},
          edges: edges);
    }

    test('Hauptausfahrt wird bevorzugt, Nebenausfahrt nur wenn deutlich schneller', () {
      final r = Router(g, Vehicle.pkw);
      final viaMain = r.fastest(station(penalty: 600).toStart(g), fichtenweg())!;
      expect(g.label(viaMain.directedEdges.first >> 1), 'Birkenweg');
      final st = station(penalty: 0).toStart(g);
      final viaSide = r.fastest(st, fichtenweg())!;
      expect(g.label(viaSide.directedEdges.first >> 1), 'Hauptstraße');
      expect(st.exitLabelFor(viaSide), 'Neben Hauptstraße');
      expect(viaSide.timeS, lessThan(viaMain.timeS));
    });

    test('Abbiegeregel „nur rechts“ an der Ausfahrt', () {
      // Ausfahrt nach Süden auf den Birkenweg: rechts = Richtung Westen
      final st = StationPoint('FGH', sLat, sLon, exits: [
        StationExit('Haupt', lat0 + dLat, sLon, main: true, turn: ExitTurn.right),
      ]).toStart(g);
      final x = st.exits.single;
      final east = Router(g, Vehicle.pkw);
      final r = east.fastest(st, fichtenweg())!;
      final first = r.directedEdges.first;
      final fwdBearing = g.startBearing(first);
      expect(fwdBearing, closeTo(270, 20)); // nach Westen
      expect(x.forward != x.backward, isTrue);
    });

    test('Eingabe ab Nebenausfahrt wird erkannt', () {
      final st = station(penalty: 0).toStart(g);
      final c = Router(g, Vehicle.pkw)
          .checkUserRoute(st, fichtenweg(), ['Hauptstraße', 'Gartenstraße', 'Fichtenweg']);
      expect(c.route, isNotNull);
      expect(st.exitLabelFor(c.route!), 'Neben Hauptstraße');
    });

    test('Ausfahrten werden gespeichert', () {
      final p = Profile('p', 'x')..station = station(penalty: 90, turn: ExitTurn.left);
      final p2 = Profile.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(p2.station!.exits, hasLength(2));
      expect(p2.station!.mainExit!.label, 'Haupt Birkenweg');
      expect(p2.station!.mainExit!.turn, ExitTurn.left);
      expect(p2.station!.sideExitPenaltySec, 90);
    });
  });

  test('Straßenziele mit Ortsteil', () {
    final t = gen.next(start, const TrainingOptions(objects: false))!;
    expect(t.target.type, TargetType.street);
    expect(t.target.detail, 'Straße in Testdorf');
  });
}
bool lkwAllowedFor(Map<String, dynamic> t) => OsmGraphBuilder.lkwAllowed(t);
