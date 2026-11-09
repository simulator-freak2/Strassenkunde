import '../core/road_graph.dart';
import '../core/router.dart';
import '../core/training.dart';

/// Ein gewähltes Gebiet (Stadtteil, Gemeinde, Landkreis …) mit Umriss.
class AreaItem {
  final String name;
  final String kind;
  final String osmType;
  final int osmId;
  final List<List<double>> rings;

  AreaItem(this.name, this.kind, this.osmType, this.osmId, this.rings);

  String get key => '$osmType$osmId';

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'osmType': osmType,
        'osmId': osmId,
        'rings': rings,
      };

  factory AreaItem.fromJson(Map<String, dynamic> j) => AreaItem(
        j['name'] as String,
        j['kind'] as String,
        j['osmType'] as String,
        j['osmId'] as int,
        [
          for (final r in j['rings'] as List)
            [for (final v in r as List) (v as num).toDouble()]
        ],
      );
}

/// Ausgangspunkt (Feuerwehrgerätehaus).
/// Ausfahrt des Gerätehauses.
class StationExit {
  String label;
  final double lat, lon;
  bool main;
  ExitTurn turn;
  StationExit(this.label, this.lat, this.lon,
      {this.main = false, this.turn = ExitTurn.both});

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': lat,
        'lon': lon,
        'main': main,
        'turn': turn.name,
      };

  factory StationExit.fromJson(Map<String, dynamic> j) => StationExit(
        j['label'] as String,
        (j['lat'] as num).toDouble(),
        (j['lon'] as num).toDouble(),
        main: j['main'] as bool? ?? false,
        turn: ExitTurn.values.byName(j['turn'] as String? ?? 'both'),
      );
}

/// Ausgangspunkt (Feuerwehrgerätehaus) mit optionalen Ausfahrten.
class StationPoint {
  final String label;
  final double lat, lon;
  List<StationExit> exits;

  /// Nebenausfahrten werden nur genutzt, wenn sie mindestens so viele
  /// Sekunden schneller sind als die Hauptausfahrt.
  int sideExitPenaltySec;

  StationPoint(this.label, this.lat, this.lon,
      {List<StationExit>? exits, this.sideExitPenaltySec = 60})
      : exits = exits ?? [];

  StationExit? get mainExit {
    for (final x in exits) {
      if (x.main) return x;
    }
    return exits.isEmpty ? null : exits.first;
  }

  /// Neuer Standort, Ausfahrten und Einstellungen bleiben erhalten.
  StationPoint copyWith({String? label, double? lat, double? lon}) =>
      StationPoint(label ?? this.label, lat ?? this.lat, lon ?? this.lon,
          exits: exits, sideExitPenaltySec: sideExitPenaltySec);

  /// Startpunkt für die Routenberechnung.
  StartPoint toStart(RoadGraph g) {
    if (exits.isEmpty) {
      return StartPoint(g.nearestEdge(lat, lon), lat, lon, label);
    }
    final main = mainExit!;
    final list = [
      for (final x in exits)
        StartExit.at(g,
            label: x.label,
            stationLat: lat,
            stationLon: lon,
            lat: x.lat,
            lon: x.lon,
            turn: x.turn,
            main: identical(x, main),
            penaltyS: identical(x, main) ? 0 : sideExitPenaltySec.toDouble())
    ];
    final mainEdge = list.firstWhere((x) => x.main).edge;
    return StartPoint(mainEdge, lat, lon, label, exits: list);
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': lat,
        'lon': lon,
        'exits': [for (final x in exits) x.toJson()],
        'sideExitPenaltySec': sideExitPenaltySec,
      };

  factory StationPoint.fromJson(Map<String, dynamic> j) => StationPoint(
        j['label'] as String,
        (j['lat'] as num).toDouble(),
        (j['lon'] as num).toDouble(),
        exits: [
          for (final x in j['exits'] as List? ?? const [])
            StationExit.fromJson(x as Map<String, dynamic>)
        ],
        sideExitPenaltySec: j['sideExitPenaltySec'] as int? ?? 60,
      );
}

class ProfileSettings {
  Vehicle vehicle = Vehicle.pkw;
  ClosureLevel closureLevel = ClosureLevel.none;
  bool startFromLast = false;
  bool objects = true;
  bool streets = true;
  Set<PoiCategory> categories = PoiCategory.values.toSet();
  int toleranceSec = 120;
  int examTargets = 5;

  TrainingOptions toOptions() => TrainingOptions(
        vehicle: vehicle,
        closureLevel: closureLevel,
        objects: objects,
        streets: streets,
        categories: categories,
        toleranceSec: toleranceSec,
      );

  Map<String, dynamic> toJson() => {
        'vehicle': vehicle.name,
        'closureLevel': closureLevel.name,
        'startFromLast': startFromLast,
        'objects': objects,
        'streets': streets,
        'categories': [for (final c in categories) c.name],
        'toleranceSec': toleranceSec,
        'examTargets': examTargets,
      };

  static ProfileSettings fromJson(Map<String, dynamic>? j) {
    final s = ProfileSettings();
    if (j == null) return s;
    s.vehicle = Vehicle.values.byName(j['vehicle'] as String? ?? 'pkw');
    s.closureLevel =
        ClosureLevel.values.byName(j['closureLevel'] as String? ?? 'none');
    s.startFromLast = j['startFromLast'] as bool? ?? false;
    s.objects = j['objects'] as bool? ?? true;
    s.streets = j['streets'] as bool? ?? true;
    final cats = j['categories'] as List?;
    if (cats != null) {
      s.categories = {
        for (final c in cats)
          if (PoiCategory.values.any((v) => v.name == c))
            PoiCategory.values.byName(c as String)
      };
    }
    s.toleranceSec = j['toleranceSec'] as int? ?? 120;
    s.examTargets = j['examTargets'] as int? ?? 5;
    return s;
  }
}

/// Ergebnis eines einzelnen Ziels in einer Prüfung.
class ExamItem {
  final String title;
  final String detail;
  final bool correct;
  final double? diffS; // null = Route nicht befahrbar
  final List<String> input;
  final List<String> optimal;
  final List<String> closures;

  ExamItem(this.title, this.detail, this.correct, this.diffS, this.input,
      this.optimal, this.closures);

  Map<String, dynamic> toJson() => {
        'title': title,
        'detail': detail,
        'correct': correct,
        'diffS': diffS,
        'input': input,
        'optimal': optimal,
        'closures': closures,
      };

  factory ExamItem.fromJson(Map<String, dynamic> j) => ExamItem(
        j['title'] as String,
        j['detail'] as String,
        j['correct'] as bool,
        (j['diffS'] as num?)?.toDouble(),
        (j['input'] as List).cast<String>(),
        (j['optimal'] as List).cast<String>(),
        (j['closures'] as List? ?? const []).cast<String>(),
      );
}

class ExamRecord {
  final DateTime date;
  final String settingsLabel;
  final List<ExamItem> items;
  ExamRecord(this.date, this.settingsLabel, this.items);

  int get correctCount => items.where((i) => i.correct).length;
  bool get passed => correctCount == items.length;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'settings': settingsLabel,
        'items': [for (final i in items) i.toJson()],
      };

  factory ExamRecord.fromJson(Map<String, dynamic> j) => ExamRecord(
        DateTime.parse(j['date'] as String),
        j['settings'] as String? ?? '',
        [
          for (final i in j['items'] as List)
            ExamItem.fromJson(i as Map<String, dynamic>)
        ],
      );
}

class Profile {
  final String id;
  String name;
  List<AreaItem> areas = [];
  double bufferM = 2000;
  StationPoint? station;
  DateTime? dataDate;
  int dataStreets = 0;
  int dataObjects = 0;
  ProfileSettings settings = ProfileSettings();

  /// Lernstatistik: Ziel-Schlüssel -> (Fehler - Treffer), begrenzt.
  Map<String, int> stats = {};
  int trainedTasks = 0;
  int trainedCorrect = 0;
  List<ExamRecord> exams = [];

  Profile(this.id, this.name);

  bool get hasData => dataDate != null;

  /// Bei Änderung des Gebiets müssen die Daten neu geladen werden.
  String areaSignature() =>
      '${(areas.map((a) => a.key).toList()..sort()).join(',')}|${bufferM.round()}';
  String? dataSignature;

  void recordResult(String key, bool correct) {
    final v = (stats[key] ?? 0) + (correct ? -1 : 2);
    stats[key] = v.clamp(-3, 6);
    trainedTasks++;
    if (correct) trainedCorrect++;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'areas': [for (final a in areas) a.toJson()],
        'bufferM': bufferM,
        'station': station?.toJson(),
        'dataDate': dataDate?.toIso8601String(),
        'dataStreets': dataStreets,
        'dataObjects': dataObjects,
        'dataSignature': dataSignature,
        'settings': settings.toJson(),
        'stats': stats,
        'trainedTasks': trainedTasks,
        'trainedCorrect': trainedCorrect,
        'exams': [for (final e in exams) e.toJson()],
      };

  factory Profile.fromJson(Map<String, dynamic> j) {
    final p = Profile(j['id'] as String, j['name'] as String);
    p.areas = [
      for (final a in j['areas'] as List? ?? const [])
        AreaItem.fromJson(a as Map<String, dynamic>)
    ];
    p.bufferM = (j['bufferM'] as num?)?.toDouble() ?? 2000;
    if (j['station'] != null) {
      p.station = StationPoint.fromJson(j['station'] as Map<String, dynamic>);
    }
    if (j['dataDate'] != null) p.dataDate = DateTime.parse(j['dataDate'] as String);
    p.dataStreets = j['dataStreets'] as int? ?? 0;
    p.dataObjects = j['dataObjects'] as int? ?? 0;
    p.dataSignature = j['dataSignature'] as String?;
    p.settings = ProfileSettings.fromJson(j['settings'] as Map<String, dynamic>?);
    p.stats = Map<String, int>.from(j['stats'] as Map? ?? const {});
    p.trainedTasks = j['trainedTasks'] as int? ?? 0;
    p.trainedCorrect = j['trainedCorrect'] as int? ?? 0;
    p.exams = [
      for (final e in j['exams'] as List? ?? const [])
        ExamRecord.fromJson(e as Map<String, dynamic>)
    ];
    return p;
  }
}
