<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Checks"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
  <img src="https://img.shields.io/badge/Lua-5.1-8a5fc9" alt="Lua 5.1">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <b>Deutsch</b> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

Ein World-of-Warcraft-Addon (3.3.5a) für **ProjectEbonhold**, das Echo-Auswahlen (Banish / Reroll / Freeze / Select) anhand eines von dir definierten Builds automatisiert und sich über die Zeit anhand echter Spieldaten selbst nachjustiert.

Benötigt **ProjectEbonhold** oder **ProjectEbonhold Enhanced**. Manche Funktionen nutzen zusätzlich **[Details!](https://www.curseforge.com/wow/addons/details)**, falls installiert.


<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works" width="100%">
</p>

## Was es macht

- **Build definieren**: Gewichte pro Echo, Quality-/Family-/Novelty-Boni, gesperrte Slots, gebannte Echoes.
- **Automation**: bewertet jeden Echo-Auswahlbildschirm gegen deinen Build und handelt (banish/reroll/freeze/select), damit du es nicht musst.
- **Tuning Advisor**: vergleicht deine Banish/Reroll/Freeze-Schwellenwerte mit dem, was dein Build tatsächlich angeboten bekommt (kein theoretisches Modell), schlägt bessere Werte vor und kann sie über Zeit schrittweise automatisch anpassen.
- **Budget-Pacing über den ganzen Run**: Schwellenwerte werden automatisch strenger, je weniger Banish-/Reroll-/Freeze-Charges übrig sind, damit du die letzten Charges nicht auf Grenzfälle verschwendest.
- **DPS- und Erscheinungswahrscheinlichkeits-Tracking**: mit installiertem Details! wird echter DPS pro aktivem Echo getrackt; wie oft ein Echo überhaupt angeboten wird, wird immer getrackt. Beides kann optional mit anderen Spielern derselben Klasse synchronisiert werden.
- **Manual Training Mode**: Automation für einen Build pausieren, manuell wählen — EbonBuilds lernt aus deinen Entscheidungen und leitet Gewichts-Vorschläge daraus ab, was du tatsächlich bevorzugt hast.
- **Gewichts- und Bonus-Vorschläge**: DPS-Daten und manuelle Picks fließen beide in Gewichts-Vorschläge pro Echo ein, sowie (experimentell) in Quality-/Family-Bonus-Vorschläge.
- **Export (AI)**: ein vollständiger Klartext-Dump der Build-Einstellungen, aller für deine Klasse verfügbaren Echoes mit echten Effektbeschreibungen, plus aller Tuning-Daten — gedacht zum Einfügen in einen KI-Chat zur Analyse.
- **Tome Atlas**: community-basierte Drop-Locations für Echo-Tomes.
- **Public Builds**: Builds anderer Spieler durchsuchen und importieren.

Ausführliche Erklärungen zu jedem Feature stehen in der [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/), die vollständige Versionshistorie in [CHANGELOG.md](../../CHANGELOG.md).

## Screenshots

Die Tour folgt dem tatsächlichen Ablauf: Build konfigurieren, vom Autopilot spielen lassen, dann aus den Daten lernen.

### 1 · Build konfigurieren

<img src="assets/screenshots/editor-priorities.png" alt="editor-priorities" width="100%">

*Echo-Prioritäten: Rang-Werte, Policies und die finalen Scores der Automation.*

<img src="assets/screenshots/editor-modifiers.png" alt="editor-modifiers" width="100%">

*Modifikatoren: Rang-Strategie, Rollen-Gewichtung, Unique-Echo-Bonus.*

<img src="assets/screenshots/editor-autopilot.png" alt="editor-autopilot" width="100%">

*Autopilot: Ausrichtung wählen, Banish/Reroll/Freeze-Schwellen justieren.*

### 2 · Der Charakter-Tab

<img src="assets/screenshots/character-overview.png" alt="character-overview" width="100%">

*Gespeicherter Charakter-Snapshot: Talente, Glyphen, Ausrüstung.*

<img src="assets/screenshots/character-talents.png" alt="character-talents" width="100%">

*Vollständige Talentbäume mit der Verteilung des Snapshots.*

<img src="assets/screenshots/character-gear.png" alt="character-gear" width="100%">

*Ausrüstung mit Affixen pro Slot und modellierten Scores.*

### 3 · Laufen lassen

<img src="assets/screenshots/build-overview.png" alt="build-overview" width="100%">

*Die Build-Übersicht: gesperrte Echoes, Teilen, Schalter, Exporte.*

<img src="assets/screenshots/logbook.png" alt="logbook" width="100%">

*Das Logbuch: jede Entscheidung mit Begründung und Alternative.*

### 4 · Aus den Daten lernen

<img src="assets/screenshots/stats-summary.png" alt="stats-summary" width="100%">

*Statistik-Zusammenfassung über aufgezeichnete Runs.*

<img src="assets/screenshots/stats-actions.png" alt="stats-actions" width="100%">

*Wie die vier Aktionen tatsächlich genutzt wurden.*

<img src="assets/screenshots/stats-recommendations.png" alt="stats-recommendations" width="100%">

*Belegbasierte Empfehlungen mit Konfidenz und Entscheidungs-Links.*

<img src="assets/screenshots/missing-echoes.png" alt="missing-echoes" width="100%">

*Fehlende gewichtete Echoes und ihre Quellen.*

## Installation

Das Wurzelverzeichnis dieses Repos *ist* der Addon-Ordner (`EbonBuilds.toc`, `core/`, `modules/` liegen direkt oben, nicht in einem Unterordner).

**Über Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Über ZIP-Download:** GitHubs "Download ZIP" benennt den entpackten Ordner nach dem Branch (z.B. `EbonBuilds-main`) — vor dem Verschieben nach `Interface/AddOns/` exakt in `EbonBuilds` umbenennen, damit der Ordnername zur `EbonBuilds.toc` passt.

Danach Spiel neu starten oder `/reload`.

## Befehle

Nur `/ebb` (oder `/ebonbuilds`) — öffnet oder schließt das Hauptfenster. Alles, was früher ein eigener Slash-Befehl war, findet sich jetzt hinter dem Zahnrad-Symbol (Einstellungen) in der Kopfzeile des Fensters, alles an einem Ort statt auswendig zu lernender Unterbefehle: Sprache, Auto-Verkauf, Taschen-Affix-Punkte, Debug-Logging, Click Trace, die Debug-/Fehler-/Click-Trace-Logs, Tuning Advisor, Tome Atlas, Affix-Referenz, die Befehlsübersicht sowie EWL-Export und Manual-Training-Reset des aktiven Builds.

## Lokalisierung

Tabs, Buttons und Tooltips des Build-Editors sind auf Deutsch, Spanisch, Französisch, Polnisch, brasilianisches Portugiesisch und Russisch übersetzt. EbonBuilds wählt die Sprache automatisch anhand deines Clients; mit `/ebb locale <code>` lässt sie sich überschreiben. Eine neue Sprache hinzufügen: `sh scripts/new-locale.sh <code>` erzeugt eine vorbefüllte Startdatei — die restlichen Schritte stehen in `CONTRIBUTING.md`. Spielbegriffe (Echo, Build, Banish/Reroll/Freeze/Select, Autopilot) bleiben in allen Sprachen englisch.

## Dokumentation

Die [Dokumentations-Seite](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) deckt Einstieg, alle Einstellungen, die vollständig durchsuchbare FAQ, Lokalisierung, Entwicklung und Fehlerbehebung ab. Ihre Quellen liegen in [`docs/`](../../docs/), sind mit dem Code versioniert und werden bei jedem Merge auf `main` auf GitHub Pages veröffentlicht. Sicherheitsthemen — feindliche Sync-Payloads, bösartige Import-Strings, Einwilligung zum Datenteilen — haben ihren eigenen Meldeweg: siehe [SECURITY.md](../../SECURITY.md).

## Bugs melden

Häng die Ausgabe des Fehler-Logs oder Debug-Logs (Einstellungen — Zahnrad-Symbol im Hauptfenster — Windows & Tools) an deinen Report an — das ist der mit Abstand schnellste Weg, dass etwas gefixt statt geraten wird.

## Entwicklung

- Reines Lua, WotLK-3.3.5a-API (Interface 30300). Kein Build-Schritt — das Repo-Wurzelverzeichnis *ist* die Addon-Ordnerstruktur, die `Interface/AddOns/` erwartet.
- Einmalig: `sh scripts/dev-setup.sh` installiert die Toolchain (`lua5.1`, `zip`; Debian/Ubuntu — unter Windows via WSL).
- `sh scripts/check.sh` fährt dieselben Prüfungen wie CI in einem Befehl: Syntax, Testsuite, `.toc`-Verifikation, 3.3.5a-API-Check, Datei-Header.
- Releases laufen über `sh scripts/release.sh <version>`; der gepushte Tag veröffentlicht das GitHub-Release automatisch per Workflow.
- Vollständiger Leitfaden (englisch): [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

## Lizenz

Siehe [`LICENSE`](../../LICENSE). Persönliche Nutzung und Nutzung in Privatserver-Communities sind frei; das Weiterverbreiten veränderter Versionen unter dem Namen EbonBuilds sowie kommerzielle Nutzung erfordern vorherige Erlaubnis des Rechteinhabers.
