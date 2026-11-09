import 'package:strassenkunde/core/osm_builder.dart';
import 'package:strassenkunde/core/road_graph.dart';

/// Kleine Test-Stadt: 6x6 Straßenraster (~110 m Abstand).
/// Zeilen (West-Ost) und Spalten (Süd-Nord) sind eigene Straßen.
/// Zeile 2 ist die schnelle "Hauptstraße", Spalte 3 eine Einbahnstraße
/// Richtung Norden.
const rowNames = [
  'Ahornweg', 'Birkenweg', 'Hauptstraße', 'Dorfstraße', 'Eichenweg', 'Fichtenweg'
];
const colNames = [
  'Amselstraße', 'Bachstraße', 'Gartenstraße', 'Einbahnweg', 'Lindenstraße', 'Mühlenweg'
];
const lat0 = 50.0, lon0 = 8.0, dLat = 0.001, dLon = 0.0015;

int nodeId(int r, int c) => r * 10 + c + 1;

List<Map<String, dynamic>> fixtureElements() {
  final els = <Map<String, dynamic>>[];
  for (var r = 0; r < 6; r++) {
    for (var c = 0; c < 6; c++) {
      els.add({
        'type': 'node',
        'id': nodeId(r, c),
        'lat': lat0 + r * dLat,
        'lon': lon0 + c * dLon,
      });
    }
  }
  for (var r = 0; r < 6; r++) {
    els.add({
      'type': 'way',
      'id': 1000 + r,
      'nodes': [for (var c = 0; c < 6; c++) nodeId(r, c)],
      'tags': {
        'highway': r == 2 ? 'primary' : 'residential',
        'name': rowNames[r],
        'maxspeed': r == 2 ? '50' : '30',
      },
    });
  }
  for (var c = 0; c < 6; c++) {
    els.add({
      'type': 'way',
      'id': 2000 + c,
      'nodes': [for (var r = 0; r < 6; r++) nodeId(r, c)],
      'tags': {
        'highway': 'residential',
        'name': colNames[c],
        'maxspeed': '30',
        if (c == 3) 'oneway': 'yes',
      },
    });
  }
  // Schule an der Eichenstraße (Zeile 4) zwischen Spalte 4 und 5
  els.add({
    'type': 'node',
    'id': 9001,
    'lat': lat0 + 4 * dLat + 0.0001,
    'lon': lon0 + 4.5 * dLon,
    'tags': {
      'amenity': 'school',
      'name': 'Grundschule Am Park',
      'addr:street': 'Eichenweg',
      'addr:housenumber': '5',
    },
  });
  els.add({
    'type': 'node',
    'id': 9002,
    'lat': lat0 + 2.5 * dLat,
    'lon': lon0 + 2.5 * dLon,
    'tags': {'place': 'village', 'name': 'Testdorf'},
  });
  return els;
}

List<List<double>> fixtureArea() => [
      [
        lat0 - 0.0005, lon0 - 0.0005,
        lat0 - 0.0005, lon0 + 5 * dLon + 0.0005,
        lat0 + 5 * dLat + 0.0005, lon0 + 5 * dLon + 0.0005,
        lat0 + 5 * dLat + 0.0005, lon0 - 0.0005,
      ]
    ];

RoadGraph buildFixture() {
  final b = OsmGraphBuilder()..addOverpassElements(fixtureElements());
  return b.build(areaRings: fixtureArea(), areaNames: ['Testdorf']);
}
