import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/road_graph.dart';
import 'profile.dart';

const int maxProfiles = 5;

/// Dateiablage. Unter Windows liegen alle Daten im Ordner
/// "Strassenkunde-Daten" neben der .exe – so funktioniert die App portabel
/// vom USB-Stick. Unter Android im privaten App-Speicher.
class Storage {
  final Directory root;
  Storage._(this.root);

  /// Für Tests: fester Ordner.
  Storage.at(this.root);

  static Future<Storage> open() async {
    Directory? dir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final d = Directory(p.join(exeDir.path, 'Strassenkunde-Daten'));
      try {
        await d.create(recursive: true);
        final probe = File(p.join(d.path, '.schreibtest'));
        await probe.writeAsString('ok');
        await probe.delete();
        dir = d;
      } catch (_) {
        dir = null; // z. B. schreibgeschützt -> Benutzerordner
      }
    }
    if (dir == null) {
      final base = await getApplicationSupportDirectory();
      dir = Directory(p.join(base.path, 'daten'));
      await dir.create(recursive: true);
    }
    return Storage._(dir);
  }

  Directory get _profilesDir => Directory(p.join(root.path, 'profile'));

  Directory profileDir(Profile pr) => Directory(p.join(_profilesDir.path, pr.id));

  File _profileFile(String id) =>
      File(p.join(_profilesDir.path, id, 'profil.json'));

  File graphFile(Profile pr) =>
      File(p.join(profileDir(pr).path, 'karte.json.gz'));

  Directory downloadDir(Profile pr) =>
      Directory(p.join(profileDir(pr).path, 'download'));

  Future<List<Profile>> loadProfiles() async {
    final out = <Profile>[];
    if (!await _profilesDir.exists()) return out;
    await for (final e in _profilesDir.list()) {
      if (e is! Directory) continue;
      final f = File(p.join(e.path, 'profil.json'));
      if (!await f.exists()) continue;
      try {
        out.add(Profile.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // beschädigtes Profil überspringen
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<Profile> createProfile(String name) async {
    final id = 'p${DateTime.now().millisecondsSinceEpoch}';
    final pr = Profile(id, name);
    await saveProfile(pr);
    return pr;
  }

  Future<void> saveProfile(Profile pr) async {
    final f = _profileFile(pr.id);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(pr.toJson()));
    await tmp.rename(f.path);
  }

  Future<void> deleteProfile(Profile pr) async {
    final d = profileDir(pr);
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<RoadGraph?> loadGraph(Profile pr) async {
    final f = graphFile(pr);
    if (!await f.exists()) return null;
    final path = f.path;
    return Isolate.run(() => decodeGraphFile(path));
  }
}

/// Liest eine gespeicherte Karte (läuft in einem Hintergrund-Isolate).
RoadGraph decodeGraphFile(String path) {
  final bytes = File(path).readAsBytesSync();
  final json = utf8.decode(gzip.decode(bytes));
  return RoadGraph.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

/// Schreibt eine Karte komprimiert.
void encodeGraphFile(RoadGraph g, String path) {
  final data = gzip.encode(utf8.encode(jsonEncode(g.toJson())));
  final tmp = File('$path.tmp');
  tmp.writeAsBytesSync(data);
  tmp.renameSync(path);
}
