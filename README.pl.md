<p align="center">
  <img src="assets/banner.svg" alt="EbonBuilds" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Checks"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
  <img src="https://img.shields.io/badge/Lua-5.1-8a5fc9" alt="Lua 5.1">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <b>Polski</b>
</p>

Addon do World of Warcraft (3.3.5a) dla **ProjectEbonhold**, który automatyzuje wybory echa (Banish / Reroll / Freeze / Select) na podstawie zdefiniowanego przez ciebie builda i z czasem sam się dostraja na podstawie prawdziwych danych z gry.

Wymaga **ProjectEbonhold** lub **ProjectEbonhold Enhanced**. Niektóre funkcje dodatkowo korzystają z **[Details!](https://www.curseforge.com/wow/addons/details)**, jeśli jest zainstalowany.


<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works" width="100%">
</p>

## Co robi

- **Definiowanie builda**: wagi dla każdego echa, bonusy jakości/rodziny/nowości, zablokowane sloty, zbanowane echa.
- **Automatyzacja**: ocenia każdy ekran wyboru echa względem twojego builda i działa (banish/reroll/freeze/select) za ciebie.
- **Tuning Advisor**: porównuje twoje progi Banish/Reroll/Freeze z tym, co twój build faktycznie dostaje w ofercie (nie z modelem teoretycznym), sugeruje lepsze wartości i może je stopniowo dostrajać automatycznie z czasem.
- **Rozkładanie budżetu na cały run**: progi automatycznie stają się bardziej rygorystyczne, gdy ładunki Banish/Reroll/Freeze się kończą, żebyś nie wydał ostatnich ładunków na wątpliwe oferty.
- **Śledzenie DPS i częstotliwości pojawiania się**: przy zainstalowanym Details! śledzi prawdziwy DPS dla każdego aktywnego echa; zawsze śledzi, jak często dane echo faktycznie pojawia się na ekranie wyboru. Oba te dane można opcjonalnie synchronizować z innymi graczami tej samej klasy.
- **Manual Training Mode**: zawieś automatyzację dla builda, wybieraj ręcznie, a EbonBuilds uczy się na podstawie twoich wyborów, generując sugestie wag na podstawie tego, co faktycznie preferowałeś.
- **Sugestie wag i bonusów**: dane DPS i ręczne wybory razem zasilają sugestie wag dla poszczególnych ech, a także (eksperymentalnie) sugestie bonusów jakości/rodziny.
- **Export (AI)**: pełny zrzut tekstowy ustawień builda, wszystkich ech dostępnych dla twojej klasy z prawdziwymi opisami efektów oraz wszystkich danych dostrajania — pomyślany do wklejenia w czacie z AI do analizy.
- **Tome Atlas**: lokalizacje dropów tomów echa, zebrane przez społeczność.
- **Public Builds**: przeglądaj i importuj buildy udostępnione przez innych graczy.

Szczegółowe wyjaśnienia każdej funkcji i pełną historię wersji znajdziesz w [`FAQ.md`](FAQ.md).

## Zrzuty ekranu

Przegląd podąża za rzeczywistym przepływem: skonfiguruj build, pozwól grać Autopilotowi, ucz się z danych.

### 1 · Konfiguracja builda

<img src="assets/screenshots/editor-priorities.png" alt="editor-priorities" width="100%">

*Priorytety ech: wartości rang, zasady i finalne wyniki automatyzacji.*

<img src="assets/screenshots/editor-modifiers.png" alt="editor-modifiers" width="100%">

*Modyfikatory: strategia rang, nacisk na role, bonus unikalnego echa.*

<img src="assets/screenshots/editor-autopilot.png" alt="editor-autopilot" width="100%">

*Autopilot: wybierz cel i dostrój progi.*

### 2 · Zakładka Postać

<img src="assets/screenshots/character-overview.png" alt="character-overview" width="100%">

*Migawka postaci: talenty, glify i ekwipunek.*

<img src="assets/screenshots/character-talents.png" alt="character-talents" width="100%">

*Pełne drzewka talentów z rozkładem migawki.*

<img src="assets/screenshots/character-gear.png" alt="character-gear" width="100%">

*Ekwipunek z afiksami i modelowanymi wynikami.*

### 3 · Uruchomienie

<img src="assets/screenshots/build-overview.png" alt="build-overview" width="100%">

*Przegląd builda: zablokowane echa, udostępnianie, eksporty.*

<img src="assets/screenshots/logbook.png" alt="logbook" width="100%">

*Dziennik: każda decyzja z uzasadnieniem i alternatywą.*

### 4 · Nauka z danych

<img src="assets/screenshots/stats-summary.png" alt="stats-summary" width="100%">

*Podsumowanie statystyk zarejestrowanych przebiegów.*

<img src="assets/screenshots/stats-actions.png" alt="stats-actions" width="100%">

*Jak faktycznie użyto czterech akcji.*

<img src="assets/screenshots/stats-recommendations.png" alt="stats-recommendations" width="100%">

*Rekomendacje oparte na danych, z pewnością i odnośnikami.*

<img src="assets/screenshots/missing-echoes.png" alt="missing-echoes" width="100%">

*Brakujące ważone echa i ich źródła.*

## Instalacja

Katalog główny tego repozytorium *jest* folderem addonu (`EbonBuilds.toc`, `core/`, `modules/` znajdują się na najwyższym poziomie, nie w podfolderze).

**Przez Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Przez pobranie ZIP:** przycisk „Download ZIP” na GitHubie nazywa wypakowany folder zgodnie z nazwą gałęzi (np. `EbonBuilds-main`) — przed umieszczeniem go w `Interface/AddOns/` zmień nazwę dokładnie na `EbonBuilds`, żeby nazwa folderu pasowała do `EbonBuilds.toc`.

Następnie zrestartuj grę lub wykonaj `/reload`.

## Komendy

Tylko `/ebb` (lub `/ebonbuilds`) — otwiera lub zamyka główne okno. Wszystko, co wcześniej było osobną komendą, znajduje się teraz pod ikoną zębatki (Ustawienia) w nagłówku okna, wszystko w jednym miejscu zamiast podkomend do zapamiętania: język, automatyczna sprzedaż, kropki afiksów w torbach, logowanie debugowania, Click Trace, logi debugowania/błędów/Click Trace, Tuning Advisor, Tome Atlas, spis afiksów, przewodnik po komendach oraz eksport EWL i reset Manual Training aktywnego builda.

## Zgłaszanie błędów

Dołącz do zgłoszenia zawartość logu błędów lub logu debugowania (Ustawienia — ikona zębatki — Windows & Tools) — to zdecydowanie najszybszy sposób, by coś zostało naprawione, a nie zgadywane.

## Rozwój

- Czysty Lua, API WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` sprawdza składnię każdego pliku przed każdym wydaniem; zobacz `.github/workflows/lua-syntax.yml` dla tej samej kontroli działającej w CI.
- Brak etapu budowania — katalog główny repozytorium *jest* strukturą folderu addonu oczekiwaną przez `Interface/AddOns/`.
