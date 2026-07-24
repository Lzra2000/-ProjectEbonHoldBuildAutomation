<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds — Automatyzacja ech dla ProjectEbonhold" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Sprawdzenia CI"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Najnowsze wydanie"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-EbonBuilds%20License-4a5568" alt="Licencja"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <b>Polski</b>
</p>

**EbonBuilds** to addon kliencki World of Warcraft **3.3.5a** dla graczy na prywatnych serwerach **[ProjectEbonhold](https://github.com/Lzra2000/ProjectEbonhold)**. Definiujesz build — wagi ech, polityki i intencję autopilota — a EbonBuilds ocenia każdy ekran wyboru echa (Banish / Reroll / Freeze / Select) w twoim imieniu, rejestruje, co się wydarzyło, i zamienia prawdziwe dane z runów w weryfikowalne sugestie dostrajania.

Stworzony dla raiderów i grinderów ech ProjectEbonhold, którzy chcą spójnej automatyzacji bez rezygnacji z kontroli: każda akcja jest logowana, rekomendacje wymagają twojej akceptacji, a Manual Training Mode pozwala addonowi uczyć się z przemyślanych wyborów.

## Szybka instalacja

1. Pobierz **`EbonBuilds.zip`** z [najnowszego wydania](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
2. Rozpakuj archiwum. Folder musi nazywać się **`EbonBuilds`** (zgodnie z `EbonBuilds.toc`).
3. Skopiuj go do `World of Warcraft/Interface/AddOns/`.
4. Uruchom grę ponownie lub wpisz `/reload`.

**Alternatywnie przez Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git EbonBuilds
```

**Wymaganie serwera:** ProjectEbonhold dostarcza własny addon serwerowy. Zainstaluj **ProjectEbonhold** lub **ProjectEbonhold Enhanced** po stronie klienta zgodnie z instrukcjami serwera — EbonBuilds zależy od niego w kwestii tablic ech, danych affixów i kilku funkcji integracyjnych. Bez niego EbonBuilds nie będzie działać.

**Opcjonalnie:** **[Details!](https://www.curseforge.com/wow/addons/details)** włącza sugestie wag oparte na DPS i bogatsze statystyki. Logowanie DPS w walce w Logbooku (v3.84+) działa bez Details!, gdy jest włączone w Ustawieniach.

Otwórz addon poleceniem **`/ebb`** lub **`/ebonbuilds`**.

## Funkcje

| Obszar | Co otrzymujesz |
| --- | --- |
| **Autopilot** | Presety intencji (Save charges / Balanced / Chase upgrades), scoring per echo, śledzenie freeze trwałe w runie oraz **Logbook** skoncentrowany na decyzjach z uzasadnieniem i zużyciem ładunków. |
| **Builds** | Wagi per echo (w tym per rangi jakości), zablokowane/zbanowane sloty, snapshoty postaci (talenty, glify, ekwipunek), Tuning Advisor, Manual Training Mode, eksport EchoWishlist (`EWL1`) oraz zrzuty **Export (AI)** w postaci zwykłego tekstu. |
| **Public Builds** | Przeglądaj buildy społeczności, inspekcja priorytetów i snapshotów, głosowanie, import oraz (gdy serwer to obsługuje) zapisywanie lub stosowanie **server loadouts**. |
| **Affixes** | Panel referencyjny affixów, kropki affixów na torbach (domyślne torby, Bagnon, Combuctor) oraz modelowanie ekwipunku w zakładce Postać. |
| **DPS i statystyki** | Opcjonalne próbki DPS w walce dołączone do runów i widoczne w Logbooku; śledzenie DPS przez Details! i synchronizacja częstotliwości pojawiania się po instalacji i zgodzie. Przestrzeń statystyk z Summary, Actions, Echoes i Recommendations popartymi dowodami. |
| **Locales** | UI edytora buildów po niemiecku, hiszpańsku, francusku, polsku, brazylijskim portugalsku i rosyjsku — wykrywane automatycznie z klienta lub nadpisywane w Ustawieniach. |

Inne narzędzia: **Tome Atlas** (lokalizacje dropów od społeczności), **Missing Echoes** (ważone echa, których jeszcze nie nauczyłeś), **budget pacing** na cały run oraz opcjonalna auto-sprzedaż u vendora.

<p align="center">
  <img src="../../assets/how-it-works.svg" alt="Zdefiniuj build, Autopilot działa na ekranach wyboru, dane są śledzone, Tuning Advisor sugeruje korekty, i pętla się powtarza" width="100%">
</p>

## Zrzuty ekranu

| Edytor builda — priorytety | Przegląd builda i Autopilot |
| --- | --- |
| <img src="../../assets/screenshots/editor-priorities.png" alt="Edytor priorytetów ech" width="100%"> | <img src="../../assets/screenshots/build-overview.png" alt="Przegląd builda" width="100%"> |

| Logbook | Statystyki — rekomendacje |
| --- | --- |
| <img src="../../assets/screenshots/logbook.png" alt="Logbook decyzji" width="100%"> | <img src="../../assets/screenshots/stats-recommendations.png" alt="Rekomendacje poparte dowodami" width="100%"> |

Więcej zrzutów i pełna trasa UI znajdują się w [`assets/screenshots/`](../../assets/screenshots/) oraz na [stronie dokumentacji](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/getting-started/).

## Dokumentacja i wsparcie

| Zasób | Link |
| --- | --- |
| Dokumentacja (Pierwsze kroki, Ustawienia, FAQ) | [lzra2000.github.io/ProjectEbonHoldBuildAutomation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) |
| FAQ | [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) |
| Wydania i changelog | [Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases) · [`CHANGELOG.md`](../../CHANGELOG.md) |
| Zgłoszenia błędów i propozycje funkcji | [Issues](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues) |
| Bezpieczeństwo | [`SECURITY.md`](../../SECURITY.md) |

Przy zgłaszaniu błędów dołącz wynik z **Ustawienia → Windows & tools → Error log** lub **Debug log** — to najszybsza droga do naprawy.

## Rozwój

Wkład jest mile widziany. Zobacz [`CONTRIBUTING.md`](../../CONTRIBUTING.md) w sprawie konfiguracji, konwencji i checklisty przed PR.

Lokalne testy, zgodność z CI i debugowanie nieudanych uruchomień Actions — w **[`docs/dev-testing.md`](../../docs/dev-testing.md)**. Szybki start:

```sh
sh scripts/dev-setup.sh    # jednorazowa toolchain (Debian/Ubuntu; na Windows użyj WSL)
sh scripts/check.sh        # szybka pętla lokalna (składnia, testy, .toc, lint API 3.3.5a)
sh scripts/check.sh --full # pełna suite uruchamiana przez CI przed merge
sh scripts/build-dist.sh   # tworzy dist/EbonBuilds.zip
```

Korzeń repozytorium to folder addonu (`EbonBuilds.toc`, `core/`, `modules/` na najwyższym poziomie). Tagi release uruchamiają [`.github/workflows/release.yml`](../../.github/workflows/release.yml), który publikuje `EbonBuilds.zip` na GitHub Releases.

## Licencja

Zobacz [`LICENSE`](../../LICENSE). Użytek osobisty i w społecznościach prywatnych serwerów jest dozwolony dla niezmienionych oficjalnych wydań. Redystrybucja zmodyfikowanych wersji pod nazwą EbonBuilds lub użytek komercyjny wymaga wcześniejszej zgody właściciela praw autorskich.
