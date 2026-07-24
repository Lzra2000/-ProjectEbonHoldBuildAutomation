<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds — Echo-Automation für ProjectEbonhold" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="CI-Checks"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Neuestes Release"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-EbonBuilds%20License-4a5568" alt="Lizenz"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <b>Deutsch</b> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

**EbonBuilds** ist ein World-of-Warcraft-**3.3.5a**-Client-Addon für Spieler auf **[ProjectEbonhold](https://github.com/Lzra2000/ProjectEbonhold)**-Privatservern. Du definierst einen Build — Echo-Gewichte, Policies und Autopilot-Intent — und EbonBuilds bewertet jeden Echo-Auswahlbildschirm (Banish / Reroll / Freeze / Select) für dich, protokolliert, was passiert ist, und verwandelt echte Run-Daten in überprüfbare Tuning-Vorschläge.

Entwickelt für ProjectEbonhold-Raider und Echo-Grinder, die konsistente Automation wollen, ohne die Kontrolle abzugeben: jede Aktion wird geloggt, Empfehlungen brauchen deine Freigabe, und der Manual Training Mode lässt das Addon aus bewussten Picks lernen.

## Schnellinstallation

1. Lade **`EbonBuilds.zip`** aus dem [neuesten Release](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest) herunter.
2. Entpacke das Archiv. Der Ordner muss **`EbonBuilds`** heißen (passend zu `EbonBuilds.toc`).
3. Kopiere ihn nach `World of Warcraft/Interface/AddOns/`.
4. Starte das Spiel neu oder führe `/reload` aus.

**Alternativ per Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git EbonBuilds
```

**Server-Anforderung:** ProjectEbonhold bringt ein eigenes Server-Addon mit. Installiere **ProjectEbonhold** oder **ProjectEbonhold Enhanced** auf dem Client, wie dein Server es vorsieht — EbonBuilds hängt davon ab für Echo-Boards, Affix-Daten und mehrere Integrationsfunktionen. Ohne dieses Addon funktioniert EbonBuilds nicht.

**Optional:** **[Details!](https://www.curseforge.com/wow/addons/details)** ermöglicht DPS-basierte Gewichts-Vorschläge und reichere Statistiken. Combat-DPS-Logging im Logbook (v3.84+) funktioniert ohne Details!, wenn es unter Einstellungen aktiviert ist.

Öffne das Addon mit **`/ebb`** oder **`/ebonbuilds`**.

## Funktionen

| Bereich | Was du bekommst |
| --- | --- |
| **Autopilot** | Intent-Presets (Save charges / Balanced / Chase upgrades), Echo-Scoring, run-persistentes Freeze-Tracking und ein entscheidungsorientiertes **Logbook** mit Begründung und Charge-Nutzung. |
| **Builds** | Echo-Gewichte (inkl. per-Quality-Ranks), gesperrte/gebannte Slots, Charakter-Snapshots (Talente, Glyphen, Ausrüstung), Tuning Advisor, Manual Training Mode, EchoWishlist-Export (`EWL1`) und Klartext-**Export (AI)**-Dumps. |
| **Public Builds** | Community-Builds durchsuchen, Prioritäten und Snapshots ansehen, voten, importieren und (wenn der Server es unterstützt) **Server Loadouts** speichern oder anwenden. |
| **Affixes** | Affix-Referenzpanel, Taschen-Affix-Punkte (Standard-Taschen, Bagnon, Combuctor) und Ausrüstungsmodellierung im Charakter-Tab. |
| **DPS & Statistiken** | Optionale Combat-DPS-Samples an Runs, sichtbar im Logbook; Details!-basiertes DPS-Tracking und Erscheinungsraten-Sync bei Installation und Einwilligung. Stats-Workspace mit Summary, Actions, Echoes und belegbasierten Recommendations. |
| **Locales** | Build-Editor-UI auf Deutsch, Spanisch, Französisch, Polnisch, brasilianisches Portugiesisch und Russisch — automatisch vom Client erkannt oder über Einstellungen überschrieben. |

Weitere nennenswerte Tools: **Tome Atlas** (Community-Drop-Locations), **Missing Echoes** (gewichtete Echoes, die du noch nicht gelernt hast), **Budget-Pacing** über den ganzen Run und optionaler Auto-Verkauf beim Händler.

<p align="center">
  <img src="../../assets/how-it-works.svg" alt="Build definieren, Autopilot handelt auf Auswahlbildschirmen, Daten werden getrackt, der Tuning Advisor schlägt Anpassungen vor, und die Schleife wiederholt sich" width="100%">
</p>

## Screenshots

| Build-Editor — Prioritäten | Build-Übersicht & Autopilot |
| --- | --- |
| <img src="../../assets/screenshots/editor-priorities.png" alt="Echo-Prioritäten-Editor" width="100%"> | <img src="../../assets/screenshots/build-overview.png" alt="Build-Übersicht" width="100%"> |

| Logbook | Statistiken — Empfehlungen |
| --- | --- |
| <img src="../../assets/screenshots/logbook.png" alt="Entscheidungs-Logbook" width="100%"> | <img src="../../assets/screenshots/stats-recommendations.png" alt="Belegbasierte Empfehlungen" width="100%"> |

Weitere Screenshots und eine vollständige UI-Tour findest du in [`assets/screenshots/`](../../assets/screenshots/) und auf der [Dokumentations-Seite](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/getting-started/).

## Dokumentation & Support

| Ressource | Link |
| --- | --- |
| Dokumentation (Einstieg, Einstellungen, FAQ) | [lzra2000.github.io/ProjectEbonHoldBuildAutomation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) |
| FAQ | [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) |
| Releases & Changelog | [Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases) · [`CHANGELOG.md`](../../CHANGELOG.md) |
| Bug-Reports & Feature-Requests | [Issues](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues) |
| Sicherheit | [`SECURITY.md`](../../SECURITY.md) |

Beim Melden von Bugs hänge die Ausgabe aus **Einstellungen → Windows & Tools → Error log** oder **Debug log** an — das ist der schnellste Weg zu einem Fix.

## Entwicklung

Beiträge sind willkommen. Siehe [`CONTRIBUTING.md`](../../CONTRIBUTING.md) für Setup, Konventionen und die Pre-PR-Checkliste.

Für lokale Checks, CI-Parität und das Debuggen fehlgeschlagener Actions-Runs siehe **[`docs/dev-testing.md`](../../docs/dev-testing.md)**. Schnelleinstieg:

```sh
sh scripts/dev-setup.sh    # einmalige Toolchain (Debian/Ubuntu; unter Windows WSL)
sh scripts/check.sh        # schneller lokaler Loop (Syntax, Tests, .toc, 3.3.5a-API-Lint)
sh scripts/check.sh --full # vollständige CI-Suite vor dem Merge
sh scripts/build-dist.sh   # erzeugt dist/EbonBuilds.zip
```

Das Repo-Wurzelverzeichnis ist der Addon-Ordner (`EbonBuilds.toc`, `core/`, `modules/` auf oberster Ebene). Release-Tags lösen [`.github/workflows/release.yml`](../../.github/workflows/release.yml) aus, das `EbonBuilds.zip` auf GitHub Releases veröffentlicht.

## Lizenz

Siehe [`LICENSE`](../../LICENSE). Persönliche Nutzung und Nutzung in Privatserver-Communities sind für unveränderte offizielle Releases erlaubt. Das Weiterverbreiten veränderter Versionen unter dem Namen EbonBuilds sowie kommerzielle Nutzung erfordern vorherige Erlaubnis des Rechteinhabers.
