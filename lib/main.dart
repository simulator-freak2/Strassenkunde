import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/storage.dart';
import 'ui/profiles_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StrassenkundeApp());
}

class StrassenkundeApp extends StatelessWidget {
  const StrassenkundeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFC62828); // Feuerwehrrot
    return MaterialApp(
      title: 'Straßenkunde',
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const _StartUp(),
    );
  }
}

class _StartUp extends StatelessWidget {
  const _StartUp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Storage>(
      future: Storage.open(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Speicherort konnte nicht geöffnet werden:\n'
                    '${snap.error}'),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return ProfilesPage(storage: snap.data!);
      },
    );
  }
}
