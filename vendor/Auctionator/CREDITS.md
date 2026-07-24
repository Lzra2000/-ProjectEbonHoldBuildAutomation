# Auctionator (vendored)

This folder contains **Auctionator 2.6.3** by **Zirco** ([auctionator-addon.com](http://auctionator-addon.com)),
packaged for Project Ebonhold / EbonBuilds players on **WoW 3.3.5a (Interface 30300)**.

EbonBuilds ships this as a **separate AddOn** (`vendor/Auctionator/`) that installs alongside EbonBuilds.
The EbonBuilds integration module (`modules/integration/AuctionatorBridge.lua`) uses Auctionator's public
price helpers (`Atr_GetAuctionBuyout`, `Atr_GetAuctionPrice`) and Buy-tab search UI when present; it soft-fails
when Auctionator is not installed.

Original Auctionator sources are unchanged except for companion notes in `Auctionator.toc`.
