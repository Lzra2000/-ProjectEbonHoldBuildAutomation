# Localization

<p class="ebb-lead">
How translations work in EbonBuilds and how to add a new language.
</p>

UI strings go through `EbonBuilds.L["English string"]` -- a lookup table that returns the active language's translation, or the English key itself when none exists. A partial translation never breaks anything; untranslated strings simply show English.

Seven languages ship today: English, German, Spanish, French, Polish, Brazilian Portuguese, Russian. The addon follows the client's own language, overridable in Settings -> Interface (takes effect after `/reload`).

## Adding a language

```
sh scripts/new-locale.sh itIT
```

That scans every translation call site in the addon -- including alias lookups like `local L = EbonBuilds.L` -- and generates `modules/i18n/locales/itIT.lua` with every key pre-filled (English placeholder as the value), grouped by the source file that uses it. Then:

1. Translate the values.
2. Add the file to `EbonBuilds.toc`, right after the other locale files.
3. Add the code to `SUPPORTED_LOCALES` in `modules/i18n/Locale.lua` (and `ALIASES` for short forms).

**Terminology convention:** game-specific terms -- Echo, Build, Banish/Reroll/Freeze/Select, Autopilot -- stay in English across every language, matching the translated READMEs. Check the existing locale files for how your language already handles them in context.

**Characters beyond Latin-1 (Polish):** stock 3.3.5a client fonts cover Latin-1 (é, ü, ñ, ó, ...) but not Latin Extended-A, so Polish ą ć ę ł ń ś ź ż would render as "?". Locale files still use the proper spelling -- `Locale.lua` probes the client font once per session and transparently folds those letters to ASCII (Postać -> Postac) only when the font can't draw them. Players with a Latin-Extended font pack installed see real diacritics.

## Checking coverage

`sh scripts/i18n-report.sh` prints per-language coverage: missing keys and orphaned entries (registered but no longer looked up anywhere). The test suite additionally FAILS when a locale file misses a key the build editor actually uses, so a forgotten translation can't slip through a release.
