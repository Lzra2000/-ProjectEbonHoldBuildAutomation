# Settings

<p class="ebb-lead">
Reference for every option in the Settings window (gear icon in the main window header).
</p>

The Settings window holds everything that used to be a slash command. Only `/ebb` itself remains, toggling the main window. Edits are held as a draft: nothing applies until **Save**, **Cancel** discards cleanly, and a category holding an invalid value shows an error marker in the navigation.

## General
Action delay and toast duration. Very low action delays can outrun the server's own screen updates.

## Automation

### Auto-sell at vendors
When enabled, EbonBuilds sells eligible zero-copper bag items while a merchant window is open. **Off by default** — opt in explicitly. The master toggle and category filters below apply only after you click **Save** in Settings.

- **Auto-sell junk at vendors** — master toggle. Without this on, nothing is sold regardless of the options below.
- **Only sell Poor (gray) quality** (`poorOnly`) — when off (default), any item quality with a zero vendor price can be sold; when on, only Poor (quality 0 / gray) items are eligible.
- **Never auto-sell Trade Goods** (`excludeTradeGoods`) — **on by default**. Materials sometimes show as zero-copper but are still worth keeping (e.g. for professions).
- **Never auto-sell Recipes** (`excludeRecipes`) — **on by default**. Patterns and recipes can be worthless at a vendor but still worth learning or trading.
- **Manage Auto-Sell Keep List...** — opens a per-character window. Items on this list are never auto-sold, matched by exact item name (case-insensitive). Add names manually; remove with the × on each row. The keep list saves immediately as you edit (no Settings **Save** needed).

**Always protected** (even when auto-sell is on): items with a non-zero vendor price; items carrying an affix you have not learned yet; gear that would upgrade your active build's spec; anything on the keep list. Trade Goods and Recipes are also skipped when their exclude toggles are on (the default).

Category filters use your client's localized item-type names (via `GetAuctionItemClasses`), so Trade Goods / Recipe detection works on non-English clients too. Items are sold one at a time with a short delay; WoW's vendor buyback tab gives you a same-session undo.

The old `/ebb autosell` slash command is gone — configure auto-sell here instead.

### Other automation options
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
