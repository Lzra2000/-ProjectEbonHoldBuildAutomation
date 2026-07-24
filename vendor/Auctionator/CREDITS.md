# Auctionator (vendored, Project Ebonhold fork)

This folder contains **Auctionator 2.6.3** by **Zirco** ([auctionator-addon.com](http://auctionator-addon.com)),
packaged for Project Ebonhold / EbonBuilds players on **WoW 3.3.5a (Interface 30300)**.

EbonBuilds ships this as a **separate AddOn** (`vendor/Auctionator/`) that installs alongside EbonBuilds.
The EbonBuilds integration module (`modules/integration/AuctionatorBridge.lua`) uses Auctionator's public
price helpers (`Atr_GetAuctionBuyout`, `Atr_GetAuctionPrice`) and Buy-tab search UI when present; it soft-fails
when Auctionator is not installed.

## Base vs upstream zip (Auctionator_v0263.zip)

Compared to upstream **2.6.3**, the vendored tree matches all Lua/XML/media files except:

| File | Change |
|------|--------|
| `Auctionator.toc` | PE title, version `2.6.3-pe1`, fork notes |
| `AuctionatorProjectEbonhold.lua` | **New** — PE helpers (`AtrPE_*`) loaded before scan/query |
| `AuctionatorProjectEbonholdHooks.lua` | **New** — shopping list preset, affix search hooks |
| `Locales/deDE.lua`, `Locales/esES.lua` | UTF-8 BOM removed (luac5.1 / syntax-check clean) |
| `AuctionatorQuery.lua`, `AuctionatorScan.lua`, `AuctionatorBuy.lua` | Defensive `pcall` wrappers for flaky AH APIs |
| `CREDITS.md` | This document |

## Project Ebonhold fork delta (`2.6.3-pe1`)

**`AuctionatorProjectEbonhold.lua`**

- **`AtrPE_BuildAffixSearchQuery` / `AtrPE_NormalizeAffixSearch`** — affix-friendly Buy-tab search (`Keen Strikes III` → `of Keen Strikes III`; full item names unchanged).
- **`AtrPE_SafeGetAuctionItemInfo` / `AtrPE_SafeQueryAuctionItems`** — guards `GetAuctionItemInfo` / `QueryAuctionItems` failures on custom cores.

**`AuctionatorProjectEbonholdHooks.lua`**

- **Default shopping list `EbonBuilds Affixes`** — seeded with sample affix-line searches; EbonBuilds Bridge can replace entries at runtime.
- **Affix search normalization hook** on `AtrSearch:Init`.
- **Soft EbonBuilds coexistence** — Auctionator keeps addon-message prefix `ATR`; EbonBuilds uses `AAM0x9` (no prefix conflict).

**Left unchanged from upstream**

- Core scan/sell/buy logic, UI layout, saved variables, and `ATR` addon-message versioning.
- No Retail / `C_AuctionHouse` APIs.

## Install

Extract `dist/Auctionator.zip` to `Interface/AddOns/Auctionator` (alongside `EbonBuilds`). Optional but recommended for affix shopping integration.
