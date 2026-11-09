import '../core/road_graph.dart';
import '../core/router.dart';
import '../core/training.dart';
import '../data/profile.dart';
import '../data/storage.dart';

/// Geöffnetes Profil mit geladener Karte.
class Session {
  final Storage storage;
  final Profile profile;
  RoadGraph? graph;
  TaskGenerator? generator;
  List<String>? _labels;

  Session(this.storage, this.profile);

  bool get ready => graph != null && profile.station != null;

  Future<void> loadGraph() async {
    graph = await storage.loadGraph(profile);
    generator = graph == null ? null : TaskGenerator(graph!);
    _labels = null;
  }

  Future<void> save() => storage.saveProfile(profile);

  List<String> get streetLabels => _labels ??= generator!.allStreetLabels();

  StartPoint stationStart() {
    final st = profile.station!;
    final e = graph!.nearestEdge(st.lat, st.lon);
    return StartPoint(e, st.lat, st.lon, st.label);
  }
}
