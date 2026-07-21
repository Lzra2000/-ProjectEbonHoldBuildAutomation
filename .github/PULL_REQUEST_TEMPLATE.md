**What this changes and why**

<!-- Short description. Link an issue if there is one. -->

**Checklist**

- [ ] `sh scripts/check.sh` passes locally (syntax check, test suite, `.toc` verification)
- [ ] Added or updated a test for the change, where one made sense
- [ ] If this changes user-facing behavior: added a `### <version>` entry to `CHANGELOG.md` (see existing entries for the format/tone -- plain, specific, no marketing language), and updated `docs/faq.md` if an explanation belongs there
- [ ] If this adds a new UI string in `modules/ui/BuildTabs.lua` or `modules/ui/MainWindow.lua`: added the English key to all six files under `modules/i18n/locales/` (or left it untranslated on purpose -- it'll fall back to English, but `scripts/check.sh` will flag it as a gap either way)
- [ ] Not something that should instead go through `scripts/release.sh` (version bump + tag) after merge

**Anything reviewers should look at closely**

<!-- Optional: tricky bits, things you're unsure about, deliberate tradeoffs. -->
