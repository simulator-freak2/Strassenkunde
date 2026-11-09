# Straßenkunde

Ortskunde-Trainer für die Feuerwehr (Windows portabel/USB-Stick und Android).
Straßen und wichtige Objekte eines frei wählbaren Ausrückebereichs lernen und
den schnellsten Weg nach Fahrzeit nennen – mit Lernmodi, generierten
Straßensperrungen und Prüfungsmodus. Kartendaten aus OpenStreetMap, nach dem
Download vollständig offline.

- Bedienung & Installation: [docs/ANLEITUNG.md](docs/ANLEITUNG.md)
- Projektplan: [docs/PLAN.md](docs/PLAN.md)

## Fertige Programme herunterladen

GitHub baut bei jedem Push automatisch (Reiter **Actions → Build**, ganz unten
bei *Artifacts*):

- `Strassenkunde-Windows` – ZIP entpacken, `Strassenkunde.exe` starten
- `Strassenkunde-Android` – `Strassenkunde.apk` installieren

Wird ein Tag `v*` (z. B. `v1.0.0`) gepusht, landen beide Dateien zusätzlich
unter **Releases**.

### Android-Updates ohne Datenverlust (optional)

Ohne eigenen Signaturschlüssel signiert der Build jede APK mit einem neuen
Debug-Schlüssel. Android verlangt dann bei Updates eine Deinstallation, und
die Profile auf dem Handy gehen verloren. Abhilfe: einmalig einen Schlüssel
erzeugen …

```bash
keytool -genkey -v -keystore strassenkunde.jks -keyalg RSA -keysize 2048 -validity 10000 -alias strassenkunde
```

… und im Repository unter *Settings → Secrets and variables → Actions*
hinterlegen:

| Secret | Inhalt |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Ausgabe von `base64 -w0 strassenkunde.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore-Passwort |
| `ANDROID_KEY_ALIAS` | `strassenkunde` |
| `ANDROID_KEY_PASSWORD` | Schlüssel-Passwort |

## Entwicklung

Flutter 3.47 (Dart 3).

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run -d windows
```

Aufbau:

| Ordner | Inhalt |
|---|---|
| `lib/core/` | Straßengraph, OSM-Import, Routing (Fahrzeit, Abbiegen, Einbahnstraßen, LKW), Sperrungen, Aufgaben & Bewertung – reines Dart, getestet |
| `lib/data/` | Profile, Speicherung (portabel neben der `.exe`), Download über Nominatim/Overpass |
| `lib/ui/` | Oberfläche: Profile, Einrichtung, Lernmodi, Prüfung, Offline-Karte |
| `test/` | Unit- und Widget-Tests mit einer Test-Stadt |

Kartendaten © OpenStreetMap-Mitwirkende, ODbL.
