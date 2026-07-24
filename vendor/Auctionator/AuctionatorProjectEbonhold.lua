-- AuctionatorProjectEbonhold.lua
-- Project Ebonhold / EbonBuilds helpers for Auctionator 2.6.3 (WotLK 3.3.5a).
-- Loaded early (after zcUtils) so scan/query/buy modules can call safe wrappers.

local ROMAN_RANK = "[IVXLCDM]+";

local function Trim(text)
	text = tostring(text or ""):match("^%s*(.-)%s*$") or "";
	return text;
end

-- Shared affix AH search term ("Keen Strikes III" -> "of Keen Strikes III").
function AtrPE_BuildAffixSearchQuery(affixName)
	affixName = Trim(affixName);
	if affixName == "" then return "" end;
	if affixName:lower():find("^of%s+", 1) then return affixName end;
	return "of " .. affixName;
end

-- Normalizes free-text Buy-tab searches without breaking full item names.
function AtrPE_NormalizeAffixSearch(searchText)
	searchText = Trim(searchText);
	if searchText == "" then return searchText end;

	if searchText:match('^".*"$') then
		return searchText;
	end

	if searchText:lower():match("^of%s+") then
		return searchText;
	end

	if searchText:match(" of .+" .. ROMAN_RANK .. "$") then
		return searchText;
	end

	if searchText:match("^[%w%s'%-]+%s+" .. ROMAN_RANK .. "$") and not searchText:match(" of ") then
		return AtrPE_BuildAffixSearchQuery(searchText);
	end

	return searchText;
end

function AtrPE_SafeGetAuctionItemInfo(listType, index)
	local ok, name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner =
		pcall(GetAuctionItemInfo, listType, index);
	if not ok then
		return nil;
	end
	return name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner;
end

function AtrPE_SafeQueryAuctionItems(...)
	local ok, err = pcall(QueryAuctionItems, ...);
	if not ok and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cff00ff00Auctionator|r: auction query failed on this realm (" .. tostring(err) .. ").",
			1, 0.5, 0.5
		);
	end
	return ok;
end
