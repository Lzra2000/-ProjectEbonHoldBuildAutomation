# Settings

<p class="ebb-lead">
Reference for every option in the Settings window (gear icon in the main window header).
</p>

The Settings window holds everything that used to be a slash command. Only `/ebb` itself remains, toggling the main window. Edits are held as a draft: nothing applies until **Save**, **Cancel** discards cleanly, and a category holding an invalid value shows an error marker in the navigation.

## General
Action delay and toast duration. Very low action delays can outrun the server's own screen updates.

## Automation
- **Auto-sell junk at vendors** -- sells 0-copper items while a vendor is open; items with an unlearned affix stay protected even if worthless.
- **Bag affix dots** -- colored dot on bag items missing an affix: red for a new line, purple for a missing rank.
- **Detailed automation logging** -- records every decision with its reasoning (view under Windows & Tools).
- **Log every button click** -- for "I clicked and nothing happened" troubleshooting.
- **Gear upgrade hints on tooltips** -- item tooltips judge the hovered item against the active build's spec.

## Interface
UI language: English, Deutsch, Español, Français, Polski, Português (Brasil), Русский. Picks up your client's language automatically; the override takes effect after `/reload`. Polish is override-only (no Polish 3.3.5a client exists).

## Windows & Tools
One-click access to the commands guide, Tome Atlas, Affixes reference, Tuning Advisor, and the Debug / Click Trace / Error logs.

## Build
Actions on the active build: EWL export and clearing Manual Training data (with confirmation). Greyed out when no build is active.

## Consent
DPS tracking and community sharing are opt-in per character. The login panel asks once; afterwards it's a checkbox here. With consent on, your per-Echo DPS aggregates are shared with other EbonBuilds players of your class -- raw combat data never leaves your client.
