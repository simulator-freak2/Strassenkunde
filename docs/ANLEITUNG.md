# Straßenkunde – Anleitung

Ortskunde-Trainer für die Feuerwehr: Straßen und wichtige Objekte lernen und
den **schnellsten Weg (Fahrzeit)** zum Einsatzziel nennen.

## Installation

### Windows (auch vom USB-Stick)

1. `Strassenkunde-Windows.zip` herunterladen.
2. ZIP entpacken – z. B. direkt auf den USB-Stick.
3. Im Ordner `Strassenkunde` die Datei **`Strassenkunde.exe`** starten.

Es ist keine Installation nötig. Alle Daten (Profile, Karten, Lernstand)
liegen im Unterordner `Strassenkunde-Daten` direkt neben der `.exe` – sie
wandern also mit dem USB-Stick mit. Ist der Ordner schreibgeschützt, nutzt
die App automatisch den Benutzerordner.

> Beim ersten Start kann Windows SmartScreen warnen („Unbekannter
> Herausgeber“). Über **Weitere Informationen → Trotzdem ausführen** starten.

### Android

1. `Strassenkunde.apk` auf das Handy laden.
2. Datei antippen und Installation erlauben (einmalig „Apps aus dieser
   Quelle zulassen“ bestätigen).

## Einrichtung (pro Profil)

Bis zu **5 Profile** pro Gerät, jedes mit eigenem Gebiet, Gerätehaus,
Einstellungen und Lernstand.

1. **Profil anlegen.**
2. **Gebiet & Startpunkt → Jetzt einrichten**
   1. *Ausrückebereich*: Stadtteil, Stadt/Gemeinde, Verbandsgemeinde oder
      Landkreis suchen und hinzufügen. Mehrere Gebiete lassen sich
      kombinieren. Der *Randbereich* (0,5–5 km) bestimmt, wie weit Straßen
      außerhalb mitgeladen werden – Wege dürfen kurz durch Nachbarorte führen.
   2. *Kartendaten herunterladen* (Internet nur hierfür nötig, danach
      offline). Ein Landkreis kann einige Minuten dauern.
   3. *Gerätehaus*: per Adresssuche, Koordinaten (`50.1234, 8.5678`) oder
      durch Antippen auf der Karte festlegen.

## Üben

| Modus | Beschreibung |
|---|---|
| **Lernmodus leicht** | Karte mit Straßennamen und Ziel. Nach jeder eingegebenen Straße zeigt die App, in welche Straßen man abbiegen kann, und ob man noch auf der schnellsten Route ist. „Lösung zeigen“ ist möglich. |
| **Lernmodus schwer** | Komplette Straßenfolge eingeben, erst nach „Auswerten“ siehst du, ob sie richtig ist. Karte (ohne Namen) optional. |
| **Prüfung** | 5 Ziele (Objekte/Straßen) nacheinander – jedes startet am vorherigen Ziel. Keine Hilfen, Auswertung am Ende, Ergebnis wird gespeichert. |

**Route eingeben:** Straßen in Fahrreihenfolge eingeben (mit
Autovervollständigung, Enter übernimmt). Bundes-/Landesstraßen ohne Namen
können über ihre Nummer eingegeben werden (z. B. `B 9`). Kurze namenlose
Zufahrten müssen nicht eingegeben werden. Die Straße am Gerätehaus darf man
weglassen.

**Bewertung:** Richtig ist eine Route, die höchstens die eingestellte
Toleranz (Standard **2 Minuten**) länger dauert als die schnellste Route.

## Einstellungen

- **Fahrzeug PKW/LKW** – LKW fährt langsamer und meidet Straßen mit
  Gewichts-, Höhen- oder Breitenbeschränkung bzw. LKW-Verbot.
- **Sperrungen**
  - *Stufe 1*: nur relevante Sperrungen – sie liegen auf der schnellsten
    Route und erzwingen einen Umweg.
  - *Stufe 2*: zusätzlich Sperrungen in der Umgebung, die mit der Route
    nichts zu tun haben (Ablenkung).
- **Start jeder Lernaufgabe**: immer ab Gerätehaus oder vom letzten Ziel
  weiter.
- **Ziele**: Objekte (Hotels, Schulen, Alten-/Pflegeheime, Krankenhäuser)
  und/oder Straßen.
- **Toleranz**: 0–5 Minuten.

Falsch beantwortete Ziele werden häufiger abgefragt.

## Hinweise zu den Daten

- Kartendaten: © OpenStreetMap-Mitwirkende (ODbL). Fehlt ein Objekt oder ist
  eine Straße falsch erfasst, kann man das auf openstreetmap.org korrigieren
  und anschließend die Daten neu laden.
- Fahrzeiten sind Schätzwerte (Straßentyp, Tempolimit, Abbiegen). Sonderrechte
  werden nicht berücksichtigt (Einbahnstraßen gelten).
