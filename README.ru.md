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
  <a href="README.md">English</a> | <a href="README.de.md">Deutsch</a> | <b>Русский</b> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

Аддон для World of Warcraft (3.3.5a), созданный для **ProjectEbonhold**, автоматизирующий выбор эхо (Banish / Reroll / Freeze / Select) на основе билда, который вы задаёте, и со временем самонастраивающийся на реальных игровых данных.

Требует **ProjectEbonhold** или **ProjectEbonhold Enhanced**. Некоторые функции дополнительно используют **[Details!](https://www.curseforge.com/wow/addons/details)**, если он установлен.


<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works" width="100%">
</p>

## Что он делает

- **Настройка билда**: веса для каждого эхо, бонусы качества/семейства/новизны, заблокированные слоты, запрещённые эхо.
- **Автоматизация**: оценивает каждый экран выбора эхо относительно вашего билда и действует (banish/reroll/freeze/select) вместо вас.
- **Tuning Advisor**: сравнивает ваши пороги Banish/Reroll/Freeze с тем, что реально предлагается вашему билду (а не с теоретической моделью), предлагает лучшие значения и может постепенно подстраивать их автоматически со временем.
- **Распределение бюджета на весь ран**: пороги автоматически становятся строже по мере уменьшения зарядов Banish/Reroll/Freeze, чтобы вы не тратили последние заряды на пограничные варианты.
- **Отслеживание DPS и частоты появления**: при установленном Details! отслеживается реальный DPS для каждого активного эхо; частота появления каждого эхо на экране выбора отслеживается всегда. Оба показателя можно опционально синхронизировать с другими игроками того же класса.
- **Ручной режим тренировки (Manual Training Mode)**: приостановите автоматизацию для билда, выбирайте вручную — EbonBuilds учится на ваших решениях и формирует рекомендации по весам на основе того, что вы реально предпочли.
- **Рекомендации по весам и бонусам**: данные DPS и ручной выбор вместе формируют рекомендации по весам для каждого эхо, а также (экспериментально) рекомендации по бонусам качества/семейства.
- **Export (AI)**: полный текстовый дамп настроек билда, всех доступных вашему классу эхо с реальными описаниями эффектов и всех данных настройки — предназначен для вставки в чат с ИИ для анализа.
- **Tome Atlas**: места дропа эхо-томов, собранные сообществом.
- **Public Builds**: просмотр и импорт билдов, которыми поделились другие игроки.

Подробные объяснения каждой функции и полная история версий — в [`FAQ.md`](FAQ.md).

## Скриншоты

Обзор повторяет реальный процесс: настройте билд, дайте Autopilot играть, учитесь на данных.

### 1 · Настройка билда

<img src="assets/screenshots/editor-priorities.png" alt="editor-priorities" width="100%">

*Приоритеты эхо: значения рангов, политики и итоговые оценки.*

<img src="assets/screenshots/editor-modifiers.png" alt="editor-modifiers" width="100%">

*Модификаторы: стратегия рангов, акцент ролей, бонус уникального эхо.*

<img src="assets/screenshots/editor-autopilot.png" alt="editor-autopilot" width="100%">

*Autopilot: выберите направление и настройте пороги.*

### 2 · Вкладка Персонаж

<img src="assets/screenshots/character-overview.png" alt="character-overview" width="100%">

*Снимок персонажа: таланты, символы и экипировка.*

<img src="assets/screenshots/character-talents.png" alt="character-talents" width="100%">

*Полные деревья талантов с распределением из снимка.*

<img src="assets/screenshots/character-gear.png" alt="character-gear" width="100%">

*Экипировка с аффиксами по слотам и смоделированными оценками.*

### 3 · Запуск

<img src="assets/screenshots/build-overview.png" alt="build-overview" width="100%">

*Обзор билда: заблокированные эхо, общий доступ, экспорт.*

<img src="assets/screenshots/logbook.png" alt="logbook" width="100%">

*Журнал: каждое решение с обоснованием и альтернативой.*

### 4 · Учимся на данных

<img src="assets/screenshots/stats-summary.png" alt="stats-summary" width="100%">

*Сводка статистики по записанным забегам.*

<img src="assets/screenshots/stats-actions.png" alt="stats-actions" width="100%">

*Как на самом деле использовались четыре действия.*

<img src="assets/screenshots/stats-recommendations.png" alt="stats-recommendations" width="100%">

*Рекомендации на основе данных, с уверенностью и ссылками.*

<img src="assets/screenshots/missing-echoes.png" alt="missing-echoes" width="100%">

*Недостающие взвешенные эхо и их источники.*

## Установка

Корень этого репозитория *является* папкой аддона (`EbonBuilds.toc`, `core/`, `modules/` находятся на верхнем уровне, а не во вложенной папке).

**Через Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Через скачивание ZIP:** кнопка GitHub "Download ZIP" называет извлечённую папку по имени ветки (например, `EbonBuilds-main`) — переименуйте её точно в `EbonBuilds`, прежде чем помещать в `Interface/AddOns/`, чтобы имя папки совпадало с `EbonBuilds.toc`.

Затем перезапустите игру или выполните `/reload`.

## Команды

Только `/ebb` (или `/ebonbuilds`) — открывает или закрывает главное окно. Всё, что раньше было отдельными командами, теперь находится за значком шестерёнки (Настройки) в заголовке окна — всё в одном месте вместо подкоманд, которые нужно помнить: язык, автопродажа, точки аффиксов в сумках, журналирование отладки, Click Trace, журналы отладки/ошибок/Click Trace, Tuning Advisor, Tome Atlas, справочник аффиксов, справка по командам, а также экспорт EWL и сброс Manual Training активного билда.

## Сообщить об ошибке

Приложите к отчёту вывод журнала ошибок или журнала отладки (Настройки — значок шестерёнки — Windows & Tools) — это самый быстрый способ добиться исправления вместо догадок.

## Разработка

- Чистый Lua, API WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` используется для проверки синтаксиса каждого файла перед каждым релизом; см. `.github/workflows/lua-syntax.yml` для той же проверки в CI.
- Без этапа сборки — корень репозитория *и есть* структура папки аддона, ожидаемая в `Interface/AddOns/`.
