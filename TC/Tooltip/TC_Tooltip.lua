-- The item tooltip's line (TC-15): whether the item's appearance is
-- collected, by the browser's rule (TC.Appearances.OfItem), and the other
-- items that carry it. On WoW: Forever any character collects any
-- appearance; nothing depends on class, armor type or level.
TC = TC or {}

local PREFIX = "|c" .. TC.COLORS.PREFIX .. "TC:|r "
local ALT = "|c" .. TC.COLORS.PREFIX .. "ALT:|r "
-- At most this many ALT lines, then "and N more".
local MAX_ALTS = 8
-- Collections' colour for a name that is not loaded (RED_FONT_COLOR).
local RETRIEVING_COLOR = "FFFF2020"

local function Debug(...)
    if TC.Config and TC.Config.debug then
        print("|cFF9D9D9DTC Debug:|r", ...)
    end
end

local hideStrings
local function StripBlizzardNotCollected(tooltip)
    if not (TC.Config and TC.Config.filterBlizzNotCollectedLine) then return end
    if not hideStrings then
        hideStrings = {}
        local candidates = {
            _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN,
            _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNCOLLECTED,
            _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_NOT_COLLECTED,
            _G.TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE,
        }
        for _, s in ipairs(candidates) do
            if type(s) == "string" and s ~= "" then
                hideStrings[s] = true
            end
        end
    end

    local name = tooltip:GetName()
    for i = 1, tooltip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and hideStrings[text] then
                line:SetText("")
                line:Hide()
            end
        end
    end
end

-- The lines per item link, kept until the collection changes, an item in
-- waiting gets its data, or a setting changes (stamp). waiting: items whose
-- data a kept answer lacks (the item's bind type, an ALT line's name);
-- requested: items whose data was asked for this session.
-- At most MEMO_MAX answers are kept: the table is emptied before the next
-- one is stored, so hovering thousands of auction rows cannot grow it.
local MEMO_MAX = 1000
local memo, memoCount, stamp, waiting, requested = {}, 0, nil, {}, {}

local function request(itemID)
    waiting[itemID] = true
    if requested[itemID] or not (C_Item and C_Item.RequestLoadItemDataByID) then return end
    requested[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end

local function settingsStamp()
    local config = TC.Config or {}
    return tostring(config.hideCollectedAlts) .. tostring(config.skipPoorAndCommon)
end

local function statusLine(text, color)
    return PREFIX .. "|c" .. color .. text .. "|r"
end

-- One ALT line per other item of the appearance, in Collections' order:
-- its name in its quality's colour (the client's "retrieving" text until
-- it is loaded, its data then asked for once), its item id and its short
-- source as the browser words it.
local function addAltLines(lines, item)
    local others = {}
    for _, source in ipairs(TC.Appearances.Sources(item.appearance)) do
        if source.sourceID ~= item.sourceID then others[#others + 1] = source end
    end
    for i, source in ipairs(others) do
        if i > MAX_ALTS then
            lines[#lines + 1] = ALT .. "|c" .. TC.COLORS.PREFIX .. "and " .. (#others - MAX_ALTS) .. " more|r"
            break
        end
        local name, quality = source.name, source.quality
        if not name and source.itemID then
            name = TC.Appearances.ItemName(source.itemID)
            if name then quality = select(3, C_Item.GetItemInfo(source.itemID)) end
        end
        local hex = RETRIEVING_COLOR
        if name then
            hex = "FFFFFFFF"
            if type(quality) == "number" and C_Item and C_Item.GetItemQualityColor then
                local _, _, _, qualityHex = C_Item.GetItemQualityColor(quality)
                if qualityHex then hex = qualityHex end
            end
        elseif source.itemID then
            request(source.itemID)
        end
        local text = TC.BrowserState and TC.BrowserState.SourceText and TC.BrowserState.SourceText(source)
        local textColor = source.isCollected and TC.COLORS.STATUS.EXACT or TC.COLORS.PREFIX
        lines[#lines + 1] = ALT .. "|c" .. hex .. (name or RETRIEVING_ITEM_INFO or "Retrieving item information")
            .. "|r |c" .. TC.COLORS.PREFIX .. "[" .. tostring(source.itemID) .. "]|r"
            .. ((text and text ~= "") and (" |c" .. textColor .. "(" .. text .. ")|r") or "")
    end
end

-- The tooltip's lines for an item link: none for an item that is not gear,
-- a grey or white one with skipPoorAndCommon, or one with no appearance.
local function linesOf(link)
    local instant = C_Item and C_Item.GetItemInfoInstant
    if not instant then return {} end
    local itemID, _, _, equipLoc = instant(link)
    if not (itemID and equipLoc and TC.VALID_EQUIP_LOCS[equipLoc]) then return {} end
    local quality = C_Item.GetItemInfo and select(3, C_Item.GetItemInfo(link))
    if TC.Config and TC.Config.skipPoorAndCommon then
        -- no quality yet: no line until the item's data says it is not grey or white
        if not quality then request(itemID) return {} end
        if quality <= 1 then return {} end
    end
    local item = TC.Appearances.OfItem(link)
    if not item then return {} end
    if item.bindType == nil then request(itemID) end

    local lines, colors = {}, TC.COLORS.STATUS
    local collected = item.collected
    if collected and item.itemCollected then
        lines[1] = statusLine("EXACT COLLECTED", colors.EXACT)
    elseif collected then
        lines[1] = statusLine("MODEL COLLECTED", colors.MODEL)
    else
        lines[1] = statusLine("MODEL NOT COLLECTED", colors.MODEL_NOT)
        local binds = Enum and Enum.ItemBind
        if item.bindType ~= nil and item.bindType == (binds and binds.OnEquip or 2) then
            lines[2] = statusLine(TC.Appearances.BIND_ON_EQUIP_TEXT, colors.MODEL_NOT)
        end
    end
    if not (collected and TC.Config and TC.Config.hideCollectedAlts) then addAltLines(lines, item) end
    return lines
end

-- Whether the tooltip already carries our status line (the post-call can
-- run twice for one show; SetOwner and ClearLines empty the tooltip).
local function hasStatusLine(tooltip)
    local name = tooltip:GetName()
    if not name then return false end
    for i = 1, tooltip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        local text = line and line:GetText()
        if text and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find("^TC: ") then return true end
    end
    return false
end

-- Runs for every item tooltip of the game: whatever fails adds no line,
-- raises nothing and is reported once through the client's error handler.
local reported = false
local function AnnotateTooltip(tooltip)
    local ok, err = pcall(function()
        local _, link = tooltip:GetItem()
        if not link then return end
        if hasStatusLine(tooltip) then return end
        if stamp ~= settingsStamp() then memo, memoCount, stamp = {}, 0, settingsStamp() end
        local lines = memo[link]
        if not lines then
            lines = linesOf(link)
            if memoCount >= MEMO_MAX then memo, memoCount = {}, 0 end
            memo[link] = lines
            memoCount = memoCount + 1
            Debug("computed", link, #lines)
        end
        if lines[1] then
            for _, line in ipairs(lines) do tooltip:AddLine(line) end
            StripBlizzardNotCollected(tooltip)
            tooltip:Show()
        end
    end)
    if not ok and not reported then
        reported = true
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
    end
end

-- The kept lines are dropped when the collection changes and when an item
-- they wait for gets its data (ITEM_DATA_LOAD_RESULT, ItemDocumentation.lua:1855-1864).
local events = CreateFrame("Frame")
events:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event, itemID)
    if event == "TRANSMOG_COLLECTION_UPDATED" or waiting[itemID] then
        memo, memoCount, waiting = {}, 0, {}
    end
end)

-- MoP Classic tooltips have the OnTooltipSetItem script; WoW: Forever dropped
-- it and reports item tooltips through TooltipDataProcessor.
if GameTooltip:HasScript("OnTooltipSetItem") then
    GameTooltip:HookScript("OnTooltipSetItem", AnnotateTooltip)
elseif TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip then
            AnnotateTooltip(tooltip)
        end
    end)
end

print("TC_Tooltip: Module loaded.")
