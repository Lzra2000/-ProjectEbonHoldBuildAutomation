<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds — автоматизация эхо для ProjectEbonhold" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="CI-проверки"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Последний релиз"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-EbonBuilds%20License-4a5568" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <a href="README.de.md">Deutsch</a> | <b>Русский</b> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

**EbonBuilds** — клиентский аддон World of Warcraft **3.3.5a** для игроков на приватных серверах **[ProjectEbonhold](https://github.com/Lzra2000/ProjectEbonhold)**. Вы задаёте билд — веса эхо, политики и намерение автопилота — а EbonBuilds оценивает каждый экран выбора эхо (Banish / Reroll / Freeze / Select) за вас, записывает, что произошло, и превращает реальные данные ранов в проверяемые рекомендации по настройке.

Создан для рейдеров и фармеров эхо ProjectEbonhold, которым нужна стабильная автоматизация без потери контроля: каждое действие логируется, рекомендации требуют вашего одобрения, а Manual Training Mode позволяет аддону учиться на осознанных выборах.

## Быстрая установка

1. Скачайте **`EbonBuilds.zip`** из [последнего релиза](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
2. Распакуйте архив. Папка должна называться **`EbonBuilds`** (как в `EbonBuilds.toc`).
3. Скопируйте её в `World of Warcraft/Interface/AddOns/`.
4. Перезапустите игру или выполните `/reload`.

**Альтернатива через Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git EbonBuilds
```

**Требование сервера:** ProjectEbonhold поставляет свой серверный аддон. Установите **ProjectEbonhold** или **ProjectEbonhold Enhanced** на клиенте, как указано вашим сервером — EbonBuilds зависит от него для досок эхо, данных аффиксов и ряда интеграционных функций. Без него EbonBuilds работать не будет.

**Опционально:** **[Details!](https://www.curseforge.com/wow/addons/details)** включает рекомендации весов на основе DPS и более подробную статистику. Логирование боевого DPS в Logbook (v3.84+) работает без Details!, если включено в Настройках.

Откройте аддон командой **`/ebb`** или **`/ebonbuilds`**.

## Возможности

| Область | Что вы получаете |
| --- | --- |
| **Autopilot** | Пресеты намерений (Save charges / Balanced / Chase upgrades), оценка по каждому эхо, отслеживание freeze на протяжении рана и **Logbook**, ориентированный на решения, с обоснованием и расходом зарядов. |
| **Builds** | Веса по эхо (включая ранги качества), заблокированные/запрещённые слоты, снимки персонажа (таланты, символы, экипировка), Tuning Advisor, Manual Training Mode, экспорт EchoWishlist (`EWL1`) и текстовые дампы **Export (AI)**. |
| **Public Builds** | Просматривайте билды сообщества, изучайте приоритеты и снимки, голосуйте, импортируйте и (если сервер поддерживает) сохраняйте или применяйте **server loadouts**. |
| **Affixes** | Справочная панель аффиксов, точки аффиксов на сумках (стандартные сумки, Bagnon, Combuctor) и моделирование экипировки на вкладке Персонаж. |
| **DPS и статистика** | Опциональные образцы боевого DPS, прикреплённые к ранам и отображаемые в Logbook; отслеживание DPS через Details! и синхронизация частоты появления при установке и согласии. Рабочая область статистики: Summary, Actions, Echoes и Recommendations с доказательной базой. |
| **Locales** | UI редактора билдов на немецком, испанском, французском, польском, бразильском португальском и русском — определяется клиентом автоматически или переопределяется в Настройках. |

Другие инструменты: **Tome Atlas** (места дропа от сообщества), **Missing Echoes** (взвешенные эхо, которых вы ещё не изучили), **budget pacing** на весь ран и опциональная авто-продажа у торговца.

<p align="center">
  <img src="../../assets/how-it-works.svg" alt="Задайте билд, Autopilot действует на экранах выбора, данные отслеживаются, Tuning Advisor предлагает корректировки, и цикл повторяется" width="100%">
</p>

## Скриншоты

| Редактор билда — приоритеты | Обзор билда и Autopilot |
| --- | --- |
| <img src="../../assets/screenshots/editor-priorities.png" alt="Редактор приоритетов эхо" width="100%"> | <img src="../../assets/screenshots/build-overview.png" alt="Обзор билда" width="100%"> |

| Logbook | Статистика — рекомендации |
| --- | --- |
| <img src="../../assets/screenshots/logbook.png" alt="Logbook решений" width="100%"> | <img src="../../assets/screenshots/stats-recommendations.png" alt="Рекомендации с доказательной базой" width="100%"> |

Больше скриншотов и полный тур по UI — в [`assets/screenshots/`](../../assets/screenshots/) и на [сайте документации](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/getting-started/).

## Документация и поддержка

| Ресурс | Ссылка |
| --- | --- |
| Документация (Начало работы, Настройки, FAQ) | [lzra2000.github.io/ProjectEbonHoldBuildAutomation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) |
| FAQ | [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) |
| Релизы и changelog | [Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases) · [`CHANGELOG.md`](../../CHANGELOG.md) |
| Сообщения об ошибках и запросы функций | [Issues](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues) |
| Безопасность | [`SECURITY.md`](../../SECURITY.md) |

При сообщении об ошибках приложите вывод **Настройки → Windows & tools → Error log** или **Debug log** — это самый быстрый путь к исправлению.

## Разработка

Вклад приветствуется. См. [`CONTRIBUTING.md`](../../CONTRIBUTING.md) — настройка, соглашения и чеклист перед PR.

Локальные проверки, соответствие CI и отладка неудачных запусков Actions — в **[`docs/dev-testing.md`](../../docs/dev-testing.md)**. Быстрый старт:

```sh
sh scripts/dev-setup.sh    # одноразовая toolchain (Debian/Ubuntu; на Windows — WSL)
sh scripts/check.sh        # быстрый локальный цикл (синтаксис, тесты, .toc, lint API 3.3.5a)
sh scripts/check.sh --full # полный набор, как в CI перед merge
sh scripts/build-dist.sh   # создаёт dist/EbonBuilds.zip
```

Корень репозитория — папка аддона (`EbonBuilds.toc`, `core/`, `modules/` на верхнем уровне). Теги релиза запускают [`.github/workflows/release.yml`](../../.github/workflows/release.yml), который публикует `EbonBuilds.zip` на GitHub Releases.

## Лицензия

См. [`LICENSE`](../../LICENSE). Личное использование и использование в сообществах приватных серверов разрешено для неизменённых официальных релизов. Распространение изменённых версий под именем EbonBuilds или коммерческое использование требует предварительного разрешения правообладателя.
