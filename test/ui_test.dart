import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strassenkunde/core/road_graph.dart';
import 'package:strassenkunde/core/training.dart';
import 'package:strassenkunde/data/profile.dart';
import 'package:strassenkunde/data/storage.dart';
import 'package:strassenkunde/ui/exam_page.dart';
import 'package:strassenkunde/ui/profile_home_page.dart';
import 'package:strassenkunde/ui/session.dart';
import 'package:strassenkunde/ui/setup_page.dart';
import 'package:strassenkunde/ui/training_page.dart';

import 'fixture.dart';

Session makeSession(ClosureLevel level) {
  final dir = Directory.systemTemp.createTempSync('sk_test');
  final p = Profile('p', 'Test')
    ..station = StationPoint('Gerätehaus', lat0 + 0.0001, lon0 + 0.5 * dLon)
    ..settings.closureLevel = level;
  final s = Session(Storage.at(dir), p);
  s.graph = buildFixture();
  s.generator = TaskGenerator(s.graph!);
  return s;
}

/// Löst einen Button über seinen Text aus (unabhängig von der Scrollposition).
Future<void> press(WidgetTester tester, String text) async {
  final btn = find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
  (btn.evaluate().first.widget as ButtonStyleButton).onPressed!();
  await tester.pump();
}

Finder panelScrollable() => find
    .descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable))
    .first;

Future<void> pumpPage(WidgetTester tester, Widget page, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    final tag = '${size.width.toInt()}px';

    testWidgets('Startseite Profil $tag', (tester) async {
      final s = makeSession(ClosureLevel.none);
      await pumpPage(tester, ProfileHomePage(storage: s.storage, profile: s.profile), size);
      expect(find.text('Lernmodus leicht'), findsOneWidget);
    });

    testWidgets('Einrichtung $tag', (tester) async {
      final s = makeSession(ClosureLevel.none);
      await pumpPage(tester, SetupPage(session: s), size);
      expect(find.text('1. Ausrückebereich'), findsOneWidget);
    });

    testWidgets('Lernmodus leicht $tag', (tester) async {
      final s = makeSession(ClosureLevel.relevant);
      await pumpPage(tester, TrainingPage(session: s, easy: true), size);
      expect(find.text('Aktuelle Sperrungen'), findsOneWidget);
      expect(find.text('Vom Start aus erreichbar:'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ahornweg');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.textContaining('kannst du abbiegen'), findsOneWidget);
      await press(tester, 'Lösung zeigen');
      await tester.scrollUntilVisible(find.textContaining('Schnellste Route:'), 200,
          scrollable: panelScrollable());
      expect(find.textContaining('Schnellste Route:'), findsOneWidget);
      await press(tester, 'Nächste Aufgabe');
      expect(find.text('Lösung zeigen'), findsOneWidget);
    });

    testWidgets('Lernmodus schwer $tag', (tester) async {
      final s = makeSession(ClosureLevel.all);
      await pumpPage(tester, TrainingPage(session: s, easy: false), size);
      expect(find.text('Vom Start aus erreichbar:'), findsNothing);
      final task = s.generator!;
      expect(task, isNotNull);
      await tester.enterText(find.byType(TextField), 'Ahornweg');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await press(tester, 'Auswerten');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.scrollUntilVisible(find.textContaining('Schnellste Route:'), 200,
          scrollable: panelScrollable());
      expect(find.textContaining('Schnellste Route:'), findsOneWidget);
    });

    testWidgets('Prüfung mit 5 Zielen $tag', (tester) async {
      final s = makeSession(ClosureLevel.relevant);
      await pumpPage(tester, ExamPage(session: s), size);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('Prüfung – Ziel $i von 5'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Hauptstraße');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        for (var k = 0; k < 5; k++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
      }
      expect(find.text('Prüfung – Ergebnis'), findsOneWidget);
      expect(s.profile.exams, hasLength(1));
      expect(s.profile.exams.first.items, hasLength(5));
      expect(s.profile.trainedTasks, 5);
    });
  }

  test('Fahrzeug-Label', () => expect(Vehicle.lkw.label, 'LKW'));
}
