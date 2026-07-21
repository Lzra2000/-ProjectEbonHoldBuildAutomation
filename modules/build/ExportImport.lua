local addonName, EbonBuilds = ...

-- EbonBuilds: modules/build/ExportImport.lua
-- Responsibility: serialise a build to base64-encoded JSON for sharing,
-- and deserialise an imported string back into a new build.

EbonBuilds.ExportImport = {}

------------------------------------------------------------------------
-- Base64
------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local MAX_ENCODED_BYTES = 98304
local MAX_DECODED_BYTES = 65536
local MAX_TREE_DEPTH = 8
local MAX_TREE_NODES = 10000
local MAX_WEIGHT_ENTRIES = 1000
local MAX_POLICY_ENTRIES = 1000

local BASE64_CHUNK = 2000
local function Base64Encode(data)
	local out = {}
	local len = #data
	for i = 1, len, 3 do
		local a, b, c = data:byte(i, i + 2)
		a, b, c = a or 0, b or 0, c or 0
		local n = a * 65536 + b * 256 + c
		out[#out + 1] = B64:byte(math.floor(n / 262144) + 1)
		out[#out + 1] = B64:byte(math.floor((n % 262144) / 4096) + 1)
		out[#out + 1] = i + 1 <= len and B64:byte(math.floor((n % 4096) / 64) + 1) or 61
		out[#out + 1] = i + 2 <= len and B64:byte(math.floor(n % 64) + 1) or 61
	end
	local chunks = {}
	for i = 1, #out, BASE64_CHUNK do
		chunks[#chunks + 1] = string.char(unpack(out, i, math.min(i + BASE64_CHUNK - 1, #out)))
	end
	return table.concat(chunks)
end

local function Base64Decode(s)
	if type(s) ~= "string" or #s > MAX_ENCODED_BYTES or #s % 4 ~= 0 then return nil end
	if s:find("[^A-Za-z0-9+/=]") or s:find("=", 1, true) and not s:match("^[A-Za-z0-9+/]*=?=?$") then return nil end
	local rev = {}
	for i = 1, #B64 do rev[B64:byte(i)] = i - 1 end
	rev[61] = 0
	local out = {}
	local len = #s
	for i = 1, len, 4 do
		local a = rev[s:byte(i)] or 0
		local b = rev[s:byte(i + 1)] or 0
		local c = rev[s:byte(i + 2)] or 0
		local d = rev[s:byte(i + 3)] or 0
		local n = a * 262144 + b * 4096 + c * 64 + d
		out[#out + 1] = string.char(math.floor(n / 65536))
		if s:byte(i + 2) ~= 61 then
			out[#out + 1] = string.char(math.floor((n % 65536) / 256))
		end
		if s:byte(i + 3) ~= 61 then
			out[#out + 1] = string.char(math.floor(n % 256))
		end
	end
	local decoded = table.concat(out)
	if #decoded > MAX_DECODED_BYTES then return nil end
	return decoded
end

------------------------------------------------------------------------
-- Minimal JSON encoder (handles the build data structure)
------------------------------------------------------------------------

local function IsArray(tbl)
	if type(tbl) ~= "table" then return false end
	local count, maxIdx = 0, 0
	for k in pairs(tbl) do
		if type(k) ~= "number" or k < 1 then return false end
		count = count + 1
		if k > maxIdx then maxIdx = k end
	end
	return count == maxIdx
end

local function JSONEncode(value)
	local t = type(value)
	if t == "nil" then return "null"
	elseif t == "boolean" then return value and "true" or "false"
	elseif t == "number" then
		if value ~= value then return "null" end -- NaN
		if value == math.huge or value == -math.huge then return "null" end
		return tostring(value)
	elseif t == "string" then
		-- JSON requires every U+0000..U+001F control byte to be escaped.
		-- Preserve hidden Echo-variant suffixes using valid \u00XX escapes.
		local parts = {}
		for index = 1, #value do
			local byte = value:byte(index)
			if byte == 34 then parts[#parts + 1] = '\\"'
			elseif byte == 92 then parts[#parts + 1] = "\\\\"
			elseif byte == 8 then parts[#parts + 1] = "\\b"
			elseif byte == 9 then parts[#parts + 1] = "\\t"
			elseif byte == 10 then parts[#parts + 1] = "\\n"
			elseif byte == 12 then parts[#parts + 1] = "\\f"
			elseif byte == 13 then parts[#parts + 1] = "\\r"
			elseif byte < 32 then parts[#parts + 1] = string.format("\\u%04X", byte)
			else parts[#parts + 1] = string.char(byte) end
		end
		return '"' .. table.concat(parts) .. '"'
	elseif t == "table" then
		local parts = {}
		if IsArray(value) then
			for i = 1, #value do parts[#parts + 1] = JSONEncode(value[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			for k, v in pairs(value) do
				if v ~= nil then
					parts[#parts + 1] = JSONEncode(tostring(k)) .. ":" .. JSONEncode(v)
				end
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

EbonBuilds.ExportImport.JSONEncode = JSONEncode

------------------------------------------------------------------------
-- Minimal JSON decoder
------------------------------------------------------------------------

local function SkipWhitespace(s, pos)
	while pos <= #s do
		local c = s:byte(pos)
		if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end
		pos = pos + 1
	end
	return pos
end

local function CodepointToUTF8(code)
	if not code then return "" end
	if code <= 0x7F then
		return string.char(code)
	elseif code <= 0x7FF then
		return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
	elseif code <= 0xFFFF then
		return string.char(
			0xE0 + math.floor(code / 0x1000),
			0x80 + (math.floor(code / 0x40) % 0x40),
			0x80 + (code % 0x40)
		)
	end
	return ""
end

local function ParseValue(s, pos)
	pos = SkipWhitespace(s, pos)
	if pos > #s then return nil, pos end
	local c = s:byte(pos)
	if c == 110 then -- null
		return nil, pos + 4
	elseif c == 116 then -- true
		return true, pos + 4
	elseif c == 102 then -- false
		return false, pos + 5
	elseif c == 34 then -- string
		local out = {}
		pos = pos + 1
		while pos <= #s do
			local cc = s:byte(pos)
			if cc == 34 then
				return table.concat(out), pos + 1
			elseif cc == 92 then -- backslash
				pos = pos + 1
				local ec = s:byte(pos)
				if ec == 98 then out[#out + 1] = string.char(8)
				elseif ec == 102 then out[#out + 1] = string.char(12)
				elseif ec == 110 then out[#out + 1] = "\n"
				elseif ec == 114 then out[#out + 1] = "\r"
				elseif ec == 116 then out[#out + 1] = "\t"
				elseif ec == 92 then out[#out + 1] = "\\"
				elseif ec == 34 then out[#out + 1] = '"'
				elseif ec == 117 then
					local hex = s:sub(pos + 1, pos + 4)
					local code = hex:match("^%x%x%x%x$") and tonumber(hex, 16) or nil
					if code then
						out[#out + 1] = CodepointToUTF8(code)
						pos = pos + 4
					else
						out[#out + 1] = "u"
					end
				else out[#out + 1] = s:sub(pos, pos) end
			else
				out[#out + 1] = s:sub(pos, pos)
			end
			pos = pos + 1
		end
		return table.concat(out), pos
	elseif c == 91 then -- array
		local arr = {}
		pos = pos + 1
		pos = SkipWhitespace(s, pos)
		if s:byte(pos) == 93 then return arr, pos + 1 end
		while true do
			if pos > #s then return arr, pos end
			local val
			val, pos = ParseValue(s, pos)
			arr[#arr + 1] = val
			pos = SkipWhitespace(s, pos)
			if s:byte(pos) == 93 then return arr, pos + 1 end
			pos = pos + 1 -- skip comma
		end
	elseif c == 123 then -- object
		local obj = {}
		pos = pos + 1
		pos = SkipWhitespace(s, pos)
		if s:byte(pos) == 125 then return obj, pos + 1 end
		while true do
			if pos > #s then return obj, pos end
			local key
			key, pos = ParseValue(s, pos)
			pos = SkipWhitespace(s, pos)
			pos = pos + 1 -- skip colon
			local val
			val, pos = ParseValue(s, pos)
			if key ~= nil then
				-- Our own encoder always stringifies table keys (JSON object
				-- keys are strings by spec), including originally-numeric
				-- Lua keys like qualityBonus[0..4], lockedEchoes[1..5], or
				-- echoBanList[spellId]. Coerce integer-looking keys back to
				-- numbers so numeric lookups (e.g. qb[quality]) still work
				-- after a round-trip through export/import or sync.
				if type(key) == "string" and key:match("^%-?%d+$") then
					obj[tonumber(key)] = val
				else
					obj[key] = val
				end
			end
			pos = SkipWhitespace(s, pos)
			if s:byte(pos) == 125 then return obj, pos + 1 end
			pos = pos + 1 -- skip comma
		end
	else -- number
		local startPos = pos
		if c == 45 then pos = pos + 1 end -- negative sign
		while pos <= #s do
			local nc = s:byte(pos)
			if nc >= 48 and nc <= 57 or nc == 46 or nc == 101 or nc == 69 or nc == 43 then
				pos = pos + 1
			else
				break
			end
		end
		return tonumber(s:sub(startPos, pos - 1)), pos
	end
end

EbonBuilds.ExportImport.JSONDecode = function(s)
	if not s or s == "" then return nil end
	local val = ParseValue(s, 1)
	return val
end

------------------------------------------------------------------------
-- Export / Import logic
------------------------------------------------------------------------

local EXPORT_VERSION = 4

local function ClampText(value, limit, fallback)
	value = type(value) == "string" and value or fallback or ""
	return value:sub(1, limit)
end

local function IsSafeTree(root, maxDepth, maxNodes)
	local nodes = 0
	local function Visit(value, depth)
		nodes = nodes + 1
		if nodes > maxNodes or depth > maxDepth then return false end
		local kind = type(value)
		if kind ~= "table" then return kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" end
		for key, child in pairs(value) do
			if type(key) ~= "number" and type(key) ~= "string" then return false end
			if not Visit(child, depth + 1) then return false end
		end
		return true
	end
	return Visit(root, 0)
end

local function BuildExportData(build)
	if EbonBuilds.EchoReferenceMigration then EbonBuilds.EchoReferenceMigration.Ensure(build) end
	local filteredWeights, filteredRefWeights = {}, {}
	if build.echoWeights then
		for name, weight in pairs(build.echoWeights) do
			if EbonBuilds.Weights.HasNonZero(weight) then
				filteredWeights[name] = EbonBuilds.Weights.NormalizeEntry(weight)
			end
		end
	end
	if build.echoWeightsByRef then
		for refKey, weight in pairs(build.echoWeightsByRef) do
			if type(refKey) == "string" and refKey:match("^[gs]:%d+$") and EbonBuilds.Weights.HasNonZero(weight) then
				filteredRefWeights[refKey] = EbonBuilds.Weights.NormalizeEntry(weight)
			end
		end
	end

	return {
		v = EXPORT_VERSION,
		title = build.title,
		class = build.class,
		spec = build.spec,
		comments = build.comments,
		lockedEchoes = build.lockedEchoes or { nil, nil, nil, nil, nil, nil },
		echoWeights = filteredWeights,
		echoWeightsByRef = filteredRefWeights,
		echoRefs = build.echoRefs,
		echoSchema = build.echoSchema,
		echoCatalogFingerprint = build.echoCatalogFingerprint,
		unresolvedEchoWeights = build.unresolvedEchoWeights,
		wizardMeta = build.wizardMeta,
		settings = build.settings,
		isPublic = build.isPublic or false,
		validated = build.validated or false,
		author = build.author,
		lastModified = build.lastModified,
		copiedFrom = build.copiedFrom or nil,
		revision = tonumber(build.revision) or tonumber(build.version) or 1,
		strategyRevision = tonumber(build.strategyRevision) or 1,
		strategyHash = build.strategyHash or EbonBuilds.Build.StrategyChecksum(build),
		-- Optional: the gear/talents/glyphs snapshot adopted on the
		-- Character tab travels with the build, so a shared Public Build
		-- can carry its author's full setup, not just weights.
		characterSnapshot = build.characterSnapshot or nil,
	}
end

function EbonBuilds.ExportImport.ExportBuild(build)
	if not build then return nil end
	local data = BuildExportData(build)
	local json = EbonBuilds.ExportImport.JSONEncode(data)
	local encoded = Base64Encode(json)
	return encoded and #encoded <= MAX_ENCODED_BYTES and encoded or nil
end

function EbonBuilds.ExportImport.DecodeBuild(b64String)
	if type(b64String) ~= "string" or b64String == "" or #b64String > MAX_ENCODED_BYTES then return nil end
	local json = Base64Decode(b64String)
	if not json or json == "" then return nil end
	local ok, data = pcall(EbonBuilds.ExportImport.JSONDecode, json)
	if not ok or type(data) ~= "table" or not IsSafeTree(data, MAX_TREE_DEPTH, MAX_TREE_NODES) then return nil end
	if data.v and (tonumber(data.v) or 0) > EXPORT_VERSION then return nil end

	local locked = {}
	if type(data.lockedEchoes) == "table" then
		for key, value in pairs(data.lockedEchoes) do
			local index = tonumber(key)
			local spellId = tonumber(value)
			if not index or index ~= math.floor(index) or index < 1 or index > EbonBuilds.Build.LOCKED_SLOTS
				or not spellId or spellId ~= math.floor(spellId) or spellId < 1 or spellId > 2147483647 then
				return nil
			end
			locked[index] = spellId
		end
	end

	local echoWeights = nil
	if type(data.echoWeights) == "table" and next(data.echoWeights) then
		local clean, count = {}, 0
		for name, entry in pairs(data.echoWeights) do
			if type(name) ~= "string" or name == "" or #name > 160 then return nil end
			count = count + 1
			if count > MAX_WEIGHT_ENTRIES then return nil end
			if type(entry) == "number" or type(entry) == "string" then
				if EbonBuilds.Weights.Validate(entry) == nil then return nil end
				clean[name] = entry -- legacy single-weight import
			elseif type(entry) == "table" then
				local ranks = {}
				for rawRank, rawValue in pairs(entry) do
					if rawRank == "default" then
						if EbonBuilds.Weights.Validate(rawValue) == nil then return nil end
						ranks.default = rawValue
					else
						local rank = tonumber(rawRank)
						if not rank or not EbonBuilds.Quality.IsValid(rank)
							or EbonBuilds.Weights.Validate(rawValue) == nil then return nil end
						ranks[rank] = rawValue
					end
				end
				clean[name] = ranks
			else
				return nil
			end
		end
		echoWeights = EbonBuilds.Weights.NormalizeWeights(clean)
	end
	local echoWeightsByRef = nil
	if type(data.echoWeightsByRef) == "table" and next(data.echoWeightsByRef) then
		local clean, count = {}, 0
		for refKey, entry in pairs(data.echoWeightsByRef) do
			if type(refKey) ~= "string" or not refKey:match("^[gs]:%d+$") or #refKey > 40 then return nil end
			count = count + 1
			if count > MAX_WEIGHT_ENTRIES then return nil end
			if type(entry) ~= "table" and type(entry) ~= "number" and type(entry) ~= "string" then return nil end
			local normalized = EbonBuilds.Weights.NormalizeEntry(entry)
			for _, rank in ipairs(EbonBuilds.Quality.ORDER or {}) do
				if EbonBuilds.Weights.Validate(normalized[rank]) == nil then return nil end
			end
			clean[refKey] = normalized
		end
		echoWeightsByRef = EbonBuilds.Weights.NormalizeRefWeights(clean)
	end

	local settings = type(data.settings) == "table" and data.settings or EbonBuilds.Build.DefaultSettings()
	if type(settings.echoPolicies) == "table" then
		local policyCount = 0
		for name, policy in pairs(settings.echoPolicies) do
			policyCount = policyCount + 1
			if policyCount > MAX_POLICY_ENTRIES or type(name) ~= "string" or #name > 160
				or not (EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.IsValid(policy)) then return nil end
		end
	end
	local snapshot = type(data.characterSnapshot) == "table" and data.characterSnapshot or nil
	local validClasses = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
		DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
	local class = type(data.class) == "string" and data.class:upper() or EbonBuilds.Build.PlayerClassToken()
	if not validClasses[class] then return nil end
	-- Reject known cross-class exact locks. Unknown legacy spell IDs remain
	-- importable for diagnostics, but a spell the active catalog can prove is
	-- unavailable to the build class must never become an active lock.
	for slot = 1, EbonBuilds.Build.LOCKED_SLOTS do
		local spellId = locked[slot]
		if spellId and EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.GetBySpellId(spellId)
			and EbonBuilds.EchoProjection and not EbonBuilds.EchoProjection.ResolveSpell(class, spellId) then
			return nil
		end
	end

	local build = EbonBuilds.Build.NewObject({
		title       = ClampText(data.title, 80, "Imported Build"),
		class       = class,
		spec        = math.max(1, math.min(3, tonumber(data.spec) or 1)),
		comments    = ClampText(data.comments, 4000, ""),
		lockedEchoes = locked,
		echoWeights = echoWeights,
		echoWeightsByRef = echoWeightsByRef,
		echoRefs = type(data.echoRefs) == "table" and data.echoRefs or nil,
		echoSchema = tonumber(data.echoSchema) or (echoWeightsByRef and 2 or nil),
		echoCatalogFingerprint = type(data.echoCatalogFingerprint) == "string" and data.echoCatalogFingerprint:sub(1, 120) or nil,
		unresolvedEchoWeights = type(data.unresolvedEchoWeights) == "table" and data.unresolvedEchoWeights or nil,
		wizardMeta = type(data.wizardMeta) == "table" and data.wizardMeta or nil,
		settings    = settings,
		isPublic    = data.isPublic or false,
		validated   = data.validated or false,
		author      = ClampText(data.author, 80, "Unknown"),
		lastModified = ClampText(data.lastModified, 32, date("%Y-%m-%d %H:%M:%S")),
		copiedFrom  = type(data.copiedFrom) == "string" and data.copiedFrom:sub(1, 120) or nil,
		characterSnapshot = snapshot,
	})
	build.importedFrom = build.author
	EbonBuilds.Build.EnsureSettings(build)
	return build
end

function EbonBuilds.ExportImport.ImportBuild(b64String)
	local build = EbonBuilds.ExportImport.DecodeBuild(b64String)
	if not build then return nil end
	EbonBuildsDB.builds[build.id] = build
	EbonBuilds.Build.EnsureRuntime(build, false)
	EbonBuilds.Build.SetAutomationEnabled(build, false)
	if EbonBuilds.EventHub then EbonBuilds.EventHub.Bump("BUILD_LIBRARY_CHANGED", build.id, "imported") end
	EbonBuilds.Build.SetActive(build.id)
	return build
end

------------------------------------------------------------------------
-- Export dialog
------------------------------------------------------------------------

local exportDialog

local function CreateExportDialog()
	local f = CreateFrame("Frame", "EbonBuildsExportBuildDialog", UIParent)
	if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
		EbonBuilds.Debug.ProtectScript(f, "ExportImport.ExportDialog")
	end
	f:SetSize(700, 420)
	f:SetPoint("CENTER")
	EbonBuilds.Theme.ApplyBackdropDefinition(f)
	f:SetBackdropColor(0, 0, 0, 0.9)
	f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self:StartMoving() end
	end)
	f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", f, "TOP", 0, -12)
	title:SetText("Export Build")
	f._title = title

	local close = EbonBuilds.Theme.CreateButton(f)
	close:SetSize(80, 22)
	close:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
	close:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)

	local scroll = CreateFrame("ScrollFrame", "EbonBuildsExportScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOP",    title, "BOTTOM", 0, -8)
	scroll:SetPoint("BOTTOM", close, "TOP",     0,  8)
	scroll:SetPoint("LEFT",   f,     "LEFT",   14,  0)
	scroll:SetPoint("RIGHT",  f,     "RIGHT", -14,  0)

	local box = CreateFrame("EditBox", nil, scroll)
	if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
		EbonBuilds.Debug.ProtectScript(box, "ExportImport.ExportBox")
	end
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
	box:SetWidth(640)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(box)

	f._editBox = box
	exportDialog = f
end

function EbonBuilds.ExportImport.ShowExportDialog(build)
	if not exportDialog then CreateExportDialog() end
	local b64 = EbonBuilds.ExportImport.ExportBuild(build)
	if not b64 then return end
	exportDialog._title:SetText("Export Build")
	exportDialog._editBox:SetText(b64)
	exportDialog._editBox:HighlightText()
	exportDialog:Show()
end

------------------------------------------------------------------------
-- AI-readable export: a plain-text dump of everything that shapes this
-- build's scoring/automation -- weights, bonuses, thresholds, and (if
-- available) the Tuning Advisor's real observed-vs-target data -- meant
-- to be pasted into an external AI chat for analysis/tuning suggestions.
-- Deliberately NOT the compact sync format (that's for sharing between
-- EbonBuilds clients; this is for a human/AI to actually read).
------------------------------------------------------------------------

local function FormatBonusLine(label, bonus, mode, keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = bonus[k] or 0
        local sign = mode[k] and "x" or "+"
        parts[#parts + 1] = string.format("%s=%s%d", tostring(k), sign, v)
    end
    return label .. ": " .. table.concat(parts, ", ")
end

local QUALITY_LABELS = EbonBuilds.Quality.LABELS
local QUALITY_ORDER  = EbonBuilds.Quality.ORDER
local FAMILY_ORDER   = { "Tank", "Survivability", "Healer", "Caster", "Melee", "Ranged", "No family" }

function EbonBuilds.ExportImport.GenerateAIText(build)
    if not build then return "" end
    local s = build.settings or EbonBuilds.Build.DefaultSettings()
    local lines = {}
    local function add(fmt, ...)
        lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    add("=== EbonBuilds Settings Export (for AI analysis) ===")
    add("Build: %s | Class: %s | Spec: %s", build.title or "?", build.class or "?", tostring(build.spec or "?"))
    local readiness = EbonBuilds.Readiness and EbonBuilds.Readiness.Get(build)
    if readiness then
        add("Revision: %d | Strategy revision: %d | Readiness: %s | Evidence: %s",
            tonumber(build.revision) or tonumber(build.version) or 1,
            tonumber(build.strategyRevision) or 1, readiness.state or "?", readiness.evidenceTier or "INSUFFICIENT")
        add("Current-strategy evidence: %d completed run(s), %d decision(s)%s",
            readiness.completedRuns or 0, readiness.decisionCount or 0,
            readiness.reviewPending and " | review pending" or "")
    end
    add("Automation mode: %s", (s.rerollMode or "sum") == "ev" and "Smart (EV)" or "Classic")
    add("")

    add("--- Bonus settings ---")
    add("(+adds the value, x multiplies; below 1 in x mode reduces the score)")
    local qLabelBonus, qLabelMode = {}, {}
    for _, q in ipairs(QUALITY_ORDER) do
        qLabelBonus[QUALITY_LABELS[q]] = (s.qualityBonus and s.qualityBonus[q]) or 0
        qLabelMode[QUALITY_LABELS[q]]  = (s.qualityBonusMode and s.qualityBonusMode[q]) or false
    end
    local qualityKeys = {}
    for _, q in ipairs(QUALITY_ORDER) do qualityKeys[#qualityKeys + 1] = QUALITY_LABELS[q] end
    add(FormatBonusLine("Quality bonus", qLabelBonus, qLabelMode, qualityKeys))
    add(FormatBonusLine("Family bonus", s.familyBonus or {}, s.familyBonusMode or {}, FAMILY_ORDER))
    add("Novelty bonus: %s%d", (s.noveltyMode and "x" or "+"), s.noveltyValue or 0)
    add("")

    if (s.rerollMode or "sum") == "ev" then
        add("--- Automation thresholds (Smart/EV mode) ---")
        add("Smart Banish: %d%% of mean (average random card)", s.banishEVPct or 60)
        add("Smart Reroll: %d%% of expected best-of-3 from a reroll", s.rerollEVPct or 95)
        add("Smart Freeze: %d%% of expected best-of-3 of a future screen", s.freezeEVPct or 110)
    else
        add("--- Automation thresholds (Classic mode, % of this class's peak score) ---")
        add("Auto-Banish: %d%%", s.autoBanishPct or 0)
        add("Auto-Reroll: %d%%", s.autoRerollPct or 0)
        add("Reroll Guard: %d%% (blocks reroll if any single echo scores at/above this)", s.rerollGuardPct or 90)
        add("Auto-Freeze: %d%%", s.autoFreezePct or 0)
    end
    add("Freeze penalty: %d%% (score reduction applied to an already-frozen echo)", s.freezePenaltyPct or 0)
    add("")
    add("All thresholds also scale with remaining Banish/Reroll/Freeze charges (get")
    add("stricter as a resource runs low) -- see /ebb debug for the live-adjusted values.")
    add("")

    -- Tuning Advisor data, if any has been collected -- gives the AI real
    -- observed-vs-target numbers to reason from instead of just the
    -- configured percentages.
    if EbonBuilds.Calibration and EbonBuilds.Calibration.SampleCount() > 0 then
        add("--- Tuning Advisor: current strategy-revision data (%d samples) ---", EbonBuilds.Calibration.SampleCount())
        add("Calibration scope: %s (per-character rolling window; not community data)",
            EbonBuilds.Calibration.GetScope and EbonBuilds.Calibration.GetScope() or "unknown")
        local function addSuggestion(label, result, unit)
            if result.insufficientData then
                add("%s: not enough data yet (%d/30 samples)", label, result.sampleCount)
            else
                add("%s: currently %.0f%% -> %s ~%.0f%% of real offers (target ~%.0f%%); observed data suggests %.0f%%",
                    label, result.currentFieldPct,
                    result.direction == "above" and "catches" or "rejects",
                    result.currentFraction, result.targetFraction, result.suggestedFieldPct)
            end
        end
        if (s.rerollMode or "sum") == "ev" then
            addSuggestion("Smart Banish", EbonBuilds.Calibration.SuggestSmartBanish(s))
            addSuggestion("Smart Reroll", EbonBuilds.Calibration.SuggestSmartReroll(s))
            addSuggestion("Smart Freeze", EbonBuilds.Calibration.SuggestSmartFreeze(s))
        else
            addSuggestion("Banish", EbonBuilds.Calibration.SuggestBanish(s))
            addSuggestion("Reroll", EbonBuilds.Calibration.SuggestReroll(s))
            addSuggestion("Freeze", EbonBuilds.Calibration.SuggestFreeze(s))
        end
        add("")
    end

    -- Weight suggestions from collected DPS data, if any -- a read-only
    -- report, since weight changes
    -- are a bigger intervention and this data is noisier. Compares each
    -- echo against others currently sharing its exact weight value.
    if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.IsEnabled() then
        local suggestions = EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)
        if #suggestions > 0 then
            add("--- Weight suggestions from DPS data (review before applying) ---")
            add("DPS is tracked by Echo family because some server builds do not expose the active rank.")
            add("A suggestion therefore means applying the same signed delta to every available rank,")
            add("never replacing the rank-specific weight table.")
            for _, sug in ipairs(suggestions) do
                add("%s: apply %+d to all available ranks (current max %d -> %d; %.0f%% %s tier average, %.0f vs %.0f DPS, %d samples)",
                    sug.name, sug.delta or (sug.suggestedWeight - sug.currentWeight),
                    sug.currentWeight, sug.suggestedWeight,
                    math.abs(sug.deviationPct), sug.deviationPct > 0 and "above" or "below",
                    sug.avgDPS, sug.tierAvgDPS, sug.sampleCount)
            end
            add("")
        end
    end

    -- Weight suggestions from Manual Training Mode -- a different kind of
    -- evidence than DPS (revealed preference: what you actually chose,
    -- not how well it performed). See BuildOverview's "Training: ON/OFF"
    -- toggle.
    if EbonBuilds.ManualTraining then
        local trainSuggestions = EbonBuilds.ManualTraining.SuggestWeightAdjustments(build)
        if #trainSuggestions > 0 then
            add("--- Weight suggestions from Manual Training (review before applying) ---")
            add("Based on manual picks rather than measured performance. Rank-aware observations")
            add("change only the offered rank; legacy family-level observations nudge every rank.")
            for _, sug in ipairs(trainSuggestions) do
                local target = sug.quality ~= nil
                    and ((EbonBuilds.Quality.LABELS or {})[sug.quality] or tostring(sug.quality))
                    or "all available ranks"
                local reason = sug.direction == "raise"
                    and "preferred over higher-scored alternatives"
                    or "passed over for lower-scored alternatives"
                add("%s [%s]: %d -> %d suggested (%s; net evidence %d, raise %d / lower %d)",
                    sug.name, target, sug.currentWeight, sug.suggestedWeight, reason,
                    sug.count, sug.raiseCount or 0, sug.lowerCount or 0)
            end
            add("")
        end
    end

    -- Quality Bonus suggestions -- experimental, report only, no
    -- auto-apply path exists for this. Compares DPS-per-weight-point
    -- across quality tiers instead of individual echoes.
    if EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.IsEnabled() then
        local bonusSuggestions = EbonBuilds.EchoPerformance.SuggestQualityBonusAdjustment(build)
        if #bonusSuggestions > 0 then
            add("--- Quality Bonus suggestions (experimental, report only) ---")
            add("Compares average DPS-per-final-score-point across quality tiers. A tier still")
            add("delivering above-average value despite its current modifier suggests raising it")
            add("further; below-average suggests the modifier is inflating that tier's score")
            add("beyond what it earns. More speculative than the per-echo suggestions above --")
            add("this affects every echo of that quality at once, so treat it cautiously.")
            for _, sug in ipairs(bonusSuggestions) do
                add("%s quality bonus: %d -> %d suggested (%.0f%% %s average value-per-score, %d echoes)",
                    sug.qualityLabel, sug.currentBonus, sug.suggestedBonus,
                    math.abs(sug.deviationPct), sug.deviationPct > 0 and "above" or "below", sug.tierEchoCount)
            end
            add("")
        end

        -- Family Bonus suggestions -- same idea as Quality, but only
        -- uses echoes with exactly one matching family (or none).
        -- Multi-family echoes get every matching family's modifier
        -- applied to the same score at once (see Scoring.ApplyFamilyBonuses),
        -- so untangling one family's own contribution from a multi-family
        -- echo would need real regression -- this sidesteps that by
        -- simply not using ambiguous data, the same way co-active
        -- clusters are excluded above.
        local familySuggestions = EbonBuilds.EchoPerformance.SuggestFamilyBonusAdjustment(build)
        if #familySuggestions > 0 then
            add("--- Family Bonus suggestions (experimental, report only) ---")
            add("Same comparison as Quality Bonus, restricted to echoes with exactly ONE")
            add("matching family (or none) -- multi-family echoes are excluded entirely rather")
            add("than guessed at, since their score already stacks several family modifiers at once.")
            for _, sug in ipairs(familySuggestions) do
                add("%s family bonus: %d -> %d suggested (%.0f%% %s average value-per-score, %d echoes)",
                    sug.family, sug.currentBonus, sug.suggestedBonus,
                    math.abs(sug.deviationPct), sug.deviationPct > 0 and "above" or "below", sug.tierEchoCount)
            end
            add("")
        end
    end

    -- Locked echo slots
    add("--- Locked echoes (always picked if offered) ---")
    local anyLocked = false
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        local spellId = build.lockedEchoes and build.lockedEchoes[i]
        if spellId then
            anyLocked = true
            local name = GetSpellInfo(spellId) or ("spellId " .. spellId)
            add("Slot %d: %s", i, name)
        end
    end
    if not anyLocked then add("(none)") end
    add("")

    local whitelistedNames = {}
    for name, enabled in pairs(s.echoWhitelist or {}) do
        if enabled then whitelistedNames[#whitelistedNames + 1] = name end
    end
    if #whitelistedNames > 0 then
        table.sort(whitelistedNames)
        add("--- Protected Echoes (automation will not banish any rank) ---")
        add(table.concat(whitelistedNames, ", "))
        add("")
    end

    -- Banned echoes. Multiple quality tiers of the same echo are banned as
    -- separate spellIds, so dedupe by display name (showing how many
    -- tiers) instead of listing "Arcane Bond" five times in a row.
    local banList = s.echoBanList or {}
    local bannedCounts = {}
    for spellId in pairs(banList) do
        if EbonBuilds.Scoring.IsBanned(spellId, s) then
            local name = GetSpellInfo(spellId) or ("spellId " .. spellId)
            bannedCounts[name] = (bannedCounts[name] or 0) + 1
        end
    end
    local bannedNames = {}
    for name, count in pairs(bannedCounts) do
        bannedNames[#bannedNames + 1] = count > 1 and string.format("%s (x%d)", name, count) or name
    end
    if #bannedNames > 0 then
        table.sort(bannedNames)
        add("--- Banned echoes (max banish priority, ignore score) ---")
        add(table.concat(bannedNames, ", "))
        add("")
    end

    if EbonBuilds.EchoPolicy then
        local policyGroups = {}
        for _, policy in ipairs(EbonBuilds.EchoPolicy.ORDER or {}) do policyGroups[policy] = {} end
        for name, policy in pairs(s.echoPolicies or {}) do
            if policyGroups[policy] then
                local visibleName = EbonBuilds.Weights and EbonBuilds.Weights.VisibleName and EbonBuilds.Weights.VisibleName(name) or name
                policyGroups[policy][#policyGroups[policy] + 1] = visibleName
            end
        end
        local anyPolicy = false
        for _, policy in ipairs(EbonBuilds.EchoPolicy.ORDER or {}) do
            if policy ~= EbonBuilds.EchoPolicy.NORMAL and #policyGroups[policy] > 0 then anyPolicy = true end
        end
        if anyPolicy then
            add("--- Conditional Echo policies ---")
            for _, policy in ipairs(EbonBuilds.EchoPolicy.ORDER or {}) do
                local names = policyGroups[policy]
                if policy ~= EbonBuilds.EchoPolicy.NORMAL and #names > 0 then
                    table.sort(names)
                    add("%s: %s", EbonBuilds.EchoPolicy.Definition(policy).label, table.concat(names, ", "))
                end
            end
            add("")
        end
    end

    -- Class-eligible echoes: EVERY echo available to this class (not just
    -- ones with a configured weight), each with its actual effect
    -- description -- reuses EchoTableRows.BuildBestByName, the exact same
    -- name-grouping the Echo Weights tab itself uses, so this list is
    -- guaranteed consistent with what you see on screen. Lets an AI judge
    -- whether a 0-weighted echo actually looks worth raising, or whether
    -- a weighted one doesn't really fit the spec, instead of only seeing
    -- names and numbers with no idea what anything does.


    local function GetDescription(spellId)
        if utils and utils.GetSpellDescription then
            local ok, desc = pcall(utils.GetSpellDescription, spellId, 500, 1)
            if ok and desc and desc ~= "" then
                -- Collapse to one line and cap length -- tooltips can run
                -- to several lines, and this export already lists a lot
                -- of echoes; a short accurate summary beats a wall of text.
                desc = desc:gsub("[\r\n]+", " "):gsub("%s%s+", " ")
                if #desc > 160 then desc = desc:sub(1, 157) .. "..." end
                return desc
            end
        end
        return "(no description cached -- hover this echo's tooltip in-game once to cache it)"
    end

    local entries = {}
    if EbonBuilds.EchoProjection then
        for _, info in ipairs(EbonBuilds.EchoProjection.GetAvailable(build.class)) do
            local familyList = {}
            for _, fam in ipairs(info.families or {}) do familyList[#familyList + 1] = fam end
            local weightsTable = build.echoWeightsByRef or {}
            entries[#entries + 1] = {
                refKey = info.refKey,
                name = info.displayName or info.canonicalName or info.name,
                weights = EbonBuilds.Weights.DescribeFromWeights(weightsTable, info.refKey, info.qualities),
                sortWeight = EbonBuilds.Weights.MaxFromWeights(weightsTable, info.refKey, info.qualities),
                quality = QUALITY_LABELS[info.quality] or "?",
                families = #familyList > 0 and table.concat(familyList, "/") or "none",
                spellId = info.representativeSpellId or info.spellId,
                whitelisted = EbonBuilds.Scoring.IsWhitelisted(info.refKey, s),
            }
        end
    end
    table.sort(entries, function(a, b)
        if a.sortWeight ~= b.sortWeight then return a.sortWeight > b.sortWeight end
        return a.name < b.name
    end)

    add("--- Class-eligible echoes (%d for %s, all rank weights 0 = currently unweighted) ---",
        #entries, build.class or "?")
    local perfAvailable = EbonBuilds.EchoPerformance and EbonBuilds.EchoPerformance.IsEnabled()
        and EbonBuilds.EchoPerformance.IsDetailsAvailable()
    if perfAvailable then
        add("Format: Name | rank weights | highest quality | family/families | protection | appears in | avg DPS while active (samples) | effect")
        add("(DPS tracking is a rough signal, not a controlled measurement -- echoes stack together")
        add("and fights vary a lot, so this can't isolate any single echo's true effect on its own.")
        add("Sample counts marked \"shared\" came from other same-class EbonBuilds users over sync,")
        add("merged as aggregate averages only -- never raw combat data.)")

        -- Concrete evidence of that limitation: echoes with byte-identical
        -- avg DPS + sample count were active at the exact same sampling
        -- ticks (the same loadout, the same fights) -- their numbers
        -- reflect the whole active set, not any one echo individually, so
        -- they can't be compared against each other from this data alone.
        local clusters = {}
        for _, e in ipairs(entries) do
            local perf = EbonBuilds.EchoPerformance.GetStats(e.name)
            if perf then
                local key = string.format("%.2f|%d", perf.avgDPS, perf.sampleCount)
                clusters[key] = clusters[key] or {}
                clusters[key][#clusters[key] + 1] = e.name
            end
        end
        local clusterLines = {}
        for _, names in pairs(clusters) do
            if #names > 1 then
                table.sort(names)
                clusterLines[#clusterLines + 1] = table.concat(names, ", ")
            end
        end
        if #clusterLines > 0 then
            add("NOTE: these groups were always active together during tracking -- their identical")
            add("DPS numbers reflect the whole active set that run, not any one echo in the group:")
            for _, line in ipairs(clusterLines) do
                add("  - %s", line)
            end
        end
    else
        add("Format: Name | rank weights | highest quality | family/families | protection | appears in | effect")
    end
    for _, e in ipairs(entries) do
        local appearText = "?"
        if EbonBuilds.Calibration and EbonBuilds.Calibration.GetAppearanceStats then
            local ap = EbonBuilds.Calibration.GetAppearanceStats(e.name)
            if ap then
                appearText = string.format("%.1f%% (%d evals)", ap.pct, ap.totalEvals)
            end
        end
        if perfAvailable then
            local perf = EbonBuilds.EchoPerformance.GetStats(e.name)
            local perfText
            if perf then
                if perf.communityCount and perf.communityCount > 0 then
                    perfText = string.format("%.0f DPS (%d, %d own+%d shared)", perf.avgDPS, perf.sampleCount, perf.personalCount, perf.communityCount)
                else
                    perfText = string.format("%.0f DPS (%d)", perf.avgDPS, perf.sampleCount)
                end
            else
                perfText = "no data"
            end
            add("%s | %s | %s | %s | %s | %s | %s | %s", e.name, e.weights, e.quality,
                e.families, e.whitelisted and "protected" or "normal", appearText, perfText,
                GetDescription(e.spellId))
        else
            add("%s | %s | %s | %s | %s | %s | %s", e.name, e.weights, e.quality,
                e.families, e.whitelisted and "protected" or "normal", appearText,
                GetDescription(e.spellId))
        end
    end

    return table.concat(lines, "\n")
end

function EbonBuilds.ExportImport.ShowAIExportDialog(build)
    if not exportDialog then CreateExportDialog() end
    local text = EbonBuilds.ExportImport.GenerateAIText(build)
    exportDialog._title:SetText("Export for AI (plain text)")
    exportDialog._editBox:SetText(text)
    exportDialog._editBox:HighlightText()
    exportDialog:Show()
end

------------------------------------------------------------------------
-- Import dialog
------------------------------------------------------------------------

local importDialog

local function CreateImportDialog()
	local f = CreateFrame("Frame", "EbonBuildsImportBuildDialog", UIParent)
	if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
		EbonBuilds.Debug.ProtectScript(f, "ExportImport.ImportDialog")
	end
	f:SetSize(700, 420)
	f:SetPoint("CENTER")
	EbonBuilds.Theme.ApplyBackdropDefinition(f)
	f:SetBackdropColor(0, 0, 0, 0.9)
	f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self:StartMoving() end
	end)
	f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", f, "TOP", 0, -12)
	title:SetText("Import Build")

	local import = EbonBuilds.Theme.CreateButton(f)
	import:SetSize(80, 22)
	import:SetPoint("BOTTOM", f, "BOTTOM", -50, 12)
	import:SetText("Import")
	import:SetScript("OnClick", function()
		local text = f._editBox:GetText() or ""
		local build = EbonBuilds.ExportImport.ImportBuild(text)
		if build then
			f:Hide()
			if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
				EbonBuilds.BuildList.Refresh()
			end
			EbonBuilds.ViewRouter.Show("buildOverview", { build = build })
		else
			f._error:Show()
		end
	end)

	local cancel = EbonBuilds.Theme.CreateButton(f)
	cancel:SetSize(80, 22)
	cancel:SetPoint("BOTTOM", f, "BOTTOM", 50, 12)
	cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function() f:Hide() end)

	local scroll = CreateFrame("ScrollFrame", "EbonBuildsImportScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOP",    title,  "BOTTOM", 0, -8)
	scroll:SetPoint("BOTTOM", import, "TOP",     0,  8)
	scroll:SetPoint("LEFT",   f,      "LEFT",   14,  0)
	scroll:SetPoint("RIGHT",  f,      "RIGHT", -14,  0)

	local box = CreateFrame("EditBox", nil, scroll)
	if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
		EbonBuilds.Debug.ProtectScript(box, "ExportImport.ImportBox")
	end
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
	box:SetWidth(640)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(box)

	local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	hint:SetPoint("TOPLEFT",  box, "TOPLEFT",  2, -2)
	hint:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -2)
	hint:SetJustifyH("LEFT")
	hint:SetJustifyV("TOP")
	hint:SetTextColor(0.5, 0.5, 0.5, 1)
	hint:SetText("Paste the exported build string here and click Import.")

	box:SetScript("OnEditFocusGained", function() hint:Hide() end)
	box:SetScript("OnEditFocusLost", function()
		if (box:GetText() or "") == "" then hint:Show() end
	end)
	box:SetScript("OnTextChanged", function()
		if box:HasFocus() then hint:Hide()
		elseif (box:GetText() or "") == "" then hint:Show()
		else hint:Hide() end
	end)

	local error = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	error:SetPoint("BOTTOM", import, "TOP", 0, 4)
	error:SetTextColor(1, 0.3, 0.3, 1)
	error:SetText("Invalid import string. Please check and try again.")
	error:Hide()
	f._error = error

	f._editBox = box
	importDialog = f
end

function EbonBuilds.ExportImport.ShowImportDialog()
	if not importDialog then CreateImportDialog() end
	importDialog._editBox:SetText("")
	importDialog._error:Hide()
	importDialog:Show()
	importDialog._editBox:SetFocus()
end
