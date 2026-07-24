-- AuctionatorProjectEbonholdHooks.lua
-- Project Ebonhold hooks (shopping list preset, affix search, EbonBuilds coexistence).

local ATR_PE_SHOPPING_LIST = "EbonBuilds Affixes";

local function FindShoppingList(name)
	if type(AUCTIONATOR_SHOPPING_LISTS) ~= "table" then return nil end;
	for _, slist in ipairs(AUCTIONATOR_SHOPPING_LISTS) do
		if slist and slist.name == name then
			return slist;
		end
	end
	return nil;
end

local function EnsureEbonBuildsShoppingList()
	if type(Atr_SList) ~= "table" or type(Atr_SList.create) ~= "function" then
		return;
	end

	if FindShoppingList(ATR_PE_SHOPPING_LIST) then
		return;
	end

	local slist = Atr_SList.create(ATR_PE_SHOPPING_LIST);
	if not slist or type(slist.AddItem) ~= "function" then
		return;
	end

	slist:AddItem(AtrPE_BuildAffixSearchQuery("Keen Strikes III"));
	slist:AddItem(AtrPE_BuildAffixSearchQuery("Overwhelming Force II"));
	slist.isSorted = false;
end

local function HookSearchInit()
	if type(AtrSearch) ~= "table" or type(AtrSearch.Init) ~= "function" then
		return;
	end
	if AtrSearch._peInitHooked then
		return;
	end
	AtrSearch._peInitHooked = true;

	local origInit = AtrSearch.Init;
	function AtrSearch:Init(searchText, exact, rescanThreshold, callback)
		if type(searchText) == "string" and searchText ~= "" and not exact then
			searchText = AtrPE_NormalizeAffixSearch(searchText);
		end
		return origInit(self, searchText, exact, rescanThreshold, callback);
	end
end

local function HookShoppingInit()
	if type(Atr_Init) ~= "function" or Atr_Init._peHooked then
		return;
	end
	Atr_Init._peHooked = true;

	local origInit = Atr_Init;
	function Atr_Init()
		origInit();
		EnsureEbonBuildsShoppingList();
	end
end

local function HookConflictCheck()
	if type(Atr_Check_For_Conflicts) ~= "function" or Atr_Check_For_Conflicts._peHooked then
		return;
	end
	Atr_Check_For_Conflicts._peHooked = true;

	local origCheck = Atr_Check_For_Conflicts;
	function Atr_Check_For_Conflicts(addonName)
		origCheck(addonName);
		if addonName == "EbonBuilds" and DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cff00ff00Auctionator|r: EbonBuilds detected — affix shopping list and Bridge features are available.",
				0.7, 0.9, 0.7
			);
		end
	end
end

HookSearchInit();
HookShoppingInit();
HookConflictCheck();
