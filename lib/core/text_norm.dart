/// Normalisiert Straßennamen, damit Schreibvarianten wie
/// "Hauptstr.", "Hauptstrasse" und "Hauptstraße" gleich behandelt werden.
String normalizeStreet(String input) {
  var s = input.toLowerCase().trim();
  s = s
      .replaceAll('ß', 'ss')
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue');
  // "str." / "str" am Wortende -> "strasse"
  s = s.replaceAllMapped(
      RegExp(r'str(\.|\b)'), (m) => 'strasse');
  // Leerzeichen, Bindestriche, Punkte, Schrägstriche entfernen
  s = s.replaceAll(RegExp(r'[\s\-\./_,;]+'), '');
  return s;
}

/// Aufteilen mehrerer Werte in einem OSM-Tag (z. B. ref="B 9;B 27").
List<String> splitOsmValues(String v) =>
    v.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
