# Security Policy

## Reporting a vulnerability

**Preferred:** [GitHub private vulnerability reporting](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/security/advisories/new) (repository **Security** tab → **Report a vulnerability**), when that option is available.

**Otherwise:** open a [GitHub issue](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/new/choose) and mark it clearly as a security report. Do not post exploit details, payloads, or step-by-step attack instructions in public — describe impact and offer to follow up privately. The maintainer may convert the issue to a private advisory or ask you to redact details.

Include how to reproduce, what an attacker gains, and the addon version.

## What counts as a security issue here

EbonBuilds is a World of Warcraft 3.3.5a client addon. It cannot make network requests, execute programs, or read anything outside WoW's sandbox, which rules out most conventional vulnerability classes. The attack surface that DOES exist:

- **Inbound sync payloads.** Other players can send this addon arbitrary data via addon messages and the sync channel. Anything a hostile payload can do beyond being ignored -- crashing the receiver, corrupting their SavedVariables, spoofing another player's contribution -- is a security issue. This surface is fuzzed in CI (`tests/test_sync_fuzz.lua`, thousands of hostile payloads per run), but the fuzzer only proves crash-resistance, not semantic safety.
- **Imported build strings.** Import strings come from strangers by design (Public Builds, pasted exports). Same standard: parsing must never do more than accept or cleanly reject.
- **SavedVariables integrity.** A malicious build string or sync payload that persists something which later breaks or alters other characters' data crosses the line from bug to vulnerability.
- **Privacy of shared data.** DPS tracking and community sharing are opt-in by explicit consent (since 3.23). Anything that transmits a player's data without that consent, or transmits more than the documented aggregates, is a security issue even if unintentional.

## What is not a security issue

Automation making a bad Banish/Reroll decision, scoring disagreements, UI glitches, or crashes you can only trigger on your own client with your own input -- those are ordinary bugs; please use the normal bug report template for them.

## Supported versions

Only the latest release is supported. Fixes ship as a new version rather than backports -- update to the current release before reporting.
