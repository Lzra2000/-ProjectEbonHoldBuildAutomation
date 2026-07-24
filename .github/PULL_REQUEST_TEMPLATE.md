**What this changes and why**

<!-- Short description. Link an issue if there is one (`Fixes #123`). -->

**Checklist**

- [ ] `sh scripts/check.sh --full` passes locally (or `check.sh` for a docs-only change)
- [ ] Added or updated a test where one made sense
- [ ] User-facing change: `### <version>` entry in `CHANGELOG.md` (plain, specific — see recent entries), and `docs/faq.md` if players need an explanation
- [ ] New UI string in `BuildTabs.lua` / `MainWindow.lua`: key added to all six `modules/i18n/locales/*.lua` (or left untranslated on purpose)
- [ ] Not a release-only change — version bumps and tags go through `scripts/release.sh` after merge

**Anything reviewers should look at closely**

<!-- Optional: tricky bits, tradeoffs, things you're unsure about. -->
