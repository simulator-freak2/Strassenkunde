# Strassenkunde – Projektplan (Entwurf)

Lern-App für Feuerwehr-Ortskunde: Straßen und wichtige Objekte lernen, schnellsten Weg (Fahrzeit) zum Ziel nennen.
Läuft offline auf **Windows (portabel, auch vom USB-Stick)** und **Android**.

## Technik

| Bereich | Wahl | Begründung |
|---|---|---|
| App-Framework | **Flutter (Dart)** | Ein Code für Windows + Android; Windows-Build ist ein Ordner mit `.exe` → läuft ohne Installation vom USB-Stick |
| Kartendaten | **OpenStreetMap** (Overpass-API, einmaliger Download pro Ort) | Kostenlos, vollständig, enthält Straßen, Einbahnstraßen, Tempo, viele Objekte |
| Kartenanzeige | Eigene Darstellung der Straßen aus den Daten (flutter_map ohne Online-Kacheln) | Voll offline, keine Kachel-Lizenzprobleme; Straßennamen können für Prüfungen ausgeblendet werden |
| Routing | Eigener Dijkstra/A* über Straßengraph, Gewicht = **Fahrzeit** (Länge ÷ Geschwindigkeit je Straßentyp, Abbiegezuschläge) | Sperrungen = Kanten entfernen, sofort neu berechnen |
| Speicher | SQLite (Ortsdaten, Objekte, Lernfortschritt, Prüfungsprotokolle) | Portabel: im USB-Modus liegt die Datenbank neben der `.exe` |
| Builds | **GitHub Actions** baut automatisch Windows-ZIP + Android-APK | Du brauchst keine Entwicklungsumgebung |

## Funktionen

1. **Ort einrichten**: Ortsname / Gebiet wählen, Startpunkt per Adresse (Suche) oder Koordinaten (Feuerwehrgerätehaus). Daten herunterladen → danach offline.
2. **Objekte**: wichtige Gebäude aus OSM (Schulen, Kitas, Krankenhäuser, Pflegeheime, Industrie, …) + eigene Objekte per Import (CSV/Excel) oder in der App anlegen.
3. **Startmodus pro Aufgabe**: „vom letzten Ziel weiter“ oder „neu ab Gerätehaus“.
4. **Lernmodus leicht**: Nach jedem Schritt werden die möglichen nächsten Straßen angezeigt; sofortiges Feedback.
5. **Lernmodus schwer**: Komplette Straßenfolge eingeben, erst danach Auswertung mit Vergleich zur schnellsten Route.
6. **Sperrungen** (zuschaltbar):
   - Stufe 1: nur relevante Sperrungen (liegen auf der schnellsten Route, Umweg nötig).
   - Stufe 2: zusätzlich irrelevante Sperrungen als Ablenkung.
7. **Prüfungsmodus**: mehrere Ziele (Objekte + Straßen) nacheinander, keine Hilfen, Auswertung am Ende, Protokoll speichern.
8. **Auswertung**: eigene Route vs. schnellste Route, Zeitdifferenz, Kartenvergleich.
9. **Statistik/Lernfortschritt**: welche Straßen/Objekte sicher sitzen, schwache Ziele öfter abfragen.

## Phasen

1. **Grundgerüst**: Flutter-Projekt, CI-Builds (Windows-ZIP, APK), portabler Modus.
2. **Daten**: OSM-Import für einen Ort, Straßengraph, Geocoding Startadresse, Objektimport.
3. **Routing**: Fahrzeitmodell, schnellste Route, Sperrungen-Generator (relevant/irrelevant).
4. **Lernmodi**: leicht + schwer, Eingabe mit Autovervollständigung, Auswertung.
5. **Prüfungsmodus** + Protokolle.
6. **Feinschliff**: Statistik, Einstellungen, Test mit echtem Ort, Anleitung (USB-Stick, APK-Installation).
