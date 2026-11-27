-- The item tooltip's lines (TC-15, slice D1: item-tooltip v3): whether the
-- item's appearance is collected, by the browser's rule
-- (TC.Appearances.OfItem), in one of two styles. Full: a blank line, the
-- status, how to collect it, the lowest price the browser saw this session
-- and the other items that carry it. Compact: the status on the right of the
-- item's name line, the number of other items, and the bags' sentence. On
-- WoW: Forever any character collects any appearance; nothing depends on
-- class, armor type or level.
TC = TC or {}
TC.Tooltip = {}

local Tooltip = TC.Tooltip

-- The browser's marks (TC_BrowserPanel.lua:76, 79): the collected check and
-- the bag of an appearance in the bags or bought, not collected.
local MARKS = { check = "Interface\\RaidFrame\\ReadyCheck-Ready", bag = "Interface\\PaperDollInfoFrame\\UI-GearManager-ItemIntoBag" }
-- The list of other items takes at most this many lines: up to 4 items in
-- full, else 3 and "and N more items"; its rows are indented by ROW_INDENT.
local LIST_CAP, ROW_INDENT = 4, 12
-- Coin atlases of this build's money frame, as the browser draws prices
-- (TC_BrowserPanel.lua:84-86).
local COIN_ATLAS = { gold = "coin-gold", silver = "coin-silver", copper = "coin-copper" }
local L = TC.L
local function coinLetter(coin)
    return coin == "gold" and L.COIN_GOLD or coin == "silver" and L.COIN_SILVER or L.COIN_COPPER
end
-- The tooltip's primary info names these getters for an item in the bags
-- (TooltipDataHandler.lua:543-544).
local BAG_GETTERS = { GetBagItem = true, GetBagItemChild = true }

local function Debug(...)
    if TC.Config and TC.Config.debug then
        print("|cFF9D9D9DTC Debug:|r", ...)
    end
end

-- Blizzard's own "not collected" line is hidden whenever our lines show.
local hideStrings
local function StripBlizzardNotCollected(tooltip)
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

-- What is known of an item per item link, kept until the collection
-- changes, an item in waiting gets its data, or a setting changes (stamp);
-- false for an item that gets no line. waiting: items whose data a kept
-- answer lacks (the item's bind type, a listed item's name); requested:
-- items whose data was asked for this session.
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

local SETTING_KEYS = { "tooltipShow", "tooltipStyle", "notCollectedColor", "otherItems", "lowestPrice", "skipPoorAndCommon" }
local function settingsStamp()
    local parts = { tostring(TC.Config ~= nil) }
    for _, key in ipairs(SETTING_KEYS) do parts[#parts + 1] = tostring(TC.Setting(key)) end
    return table.concat(parts, "/")
end

-- How many of n other items the list shows as rows.
local function rowsOf(n)
    return n <= LIST_CAP and n or LIST_CAP - 1
end

local function hexOf(r, g, b)
    local function byte(v) return math.floor(v * 255 + 0.5) end
    return ("FF%02X%02X%02X"):format(byte(r), byte(g), byte(b))
end

-- A listed item's name in its quality's colour; the client's "retrieving"
-- text in Collections' red until it is loaded, its data then asked for once.
local function nameOf(source)
    local name, quality = source.name, source.quality
    if not name and source.itemID then
        name = TC.Appearances.ItemName(source.itemID)
        if name then quality = select(3, C_Item.GetItemInfo(source.itemID)) end
    end
    if not name then
        if source.itemID then request(source.itemID) end
        return TC.ClientText("RETRIEVING_ITEM_INFO", "RETRIEVING_ITEM"), TC.COLORS.RETRIEVING
    end
    local color = TC.COLORS.WHITE
    if type(quality) == "number" and C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then color = hexOf(r, g, b) end
    end
    return name, color
end

-- What the tooltip needs of an item link, or false for no line: an item
-- that is not gear, a grey or white one while those are skipped, or one with
-- no appearance. { appearanceID, collected, bindsOnEquip, source (this
-- item's source in one line), others (the rows the list shows: name,
-- color, source, collected), otherCount }. The other items are the
-- appearance's sources in Collections' order but this item's.
local function itemOf(link)
    local instant = C_Item and C_Item.GetItemInfoInstant
    if not instant then return false end
    local itemID, _, _, equipLoc = instant(link)
    if not (itemID and equipLoc and TC.VALID_EQUIP_LOCS[equipLoc]) then return false end
    if TC.Config and TC.Setting("skipPoorAndCommon") then
        local quality = C_Item.GetItemInfo and select(3, C_Item.GetItemInfo(link))
        -- no quality yet: no line until the item's data says it is not grey or white
        if not quality then request(itemID) return false end
        if quality <= 1 then return false end
    end
    local found = TC.Appearances.OfItem(link)
    if not found then return false end
    if found.bindType == nil then request(itemID) end
    local binds = Enum and Enum.ItemBind
    local item = { appearanceID = found.appearance.id, collected = found.collected, others = {}, otherCount = 0,
        bindsOnEquip = found.bindType ~= nil and found.bindType == (binds and binds.OnEquip or 2) }
    local State = TC.BrowserState
    local others = {}
    for _, source in ipairs(TC.Appearances.Sources(found.appearance)) do
        if source.sourceID == found.sourceID then
            item.source = State.SourceLine(source)
        elseif source.itemID ~= itemID then
            others[#others + 1] = source
        end
    end
    item.otherCount = #others
    for i = 1, rowsOf(#others) do
        local source = others[i]
        local name, color = nameOf(source)
        item.others[i] = { name = name, color = color, source = State.SourceText(source), collected = source.isCollected }
    end
    return item
end

-- The lines for an item (itemOf's answer), the settings ({ style "full" or
-- "compact", color, others "notCollected", "always" or "off", price }) and
-- what is known at this show ({ pending "bags", "bought" or nil, price {
-- copper, age } or nil }). Answers { nameRight, lines }: nameRight is the
-- line description for the right of the name line (Compact), lines the
-- descriptions to add, each { text, color, right, rightColor, money, mark
-- ("check" or "bag"), wrap, indent }; colours are "AARRGGBB".
function Tooltip.Lines(item, settings, known)
    local C, W = TC.COLORS, TC.BrowserState.Wording()
    local pendingText = known.pending and W.pending[known.pending]
    if settings.style == "compact" then
        local right
        if item.collected then
            right = { text = W.collected, color = C.COLLECTED, mark = "check" }
        else
            local n = item.otherCount
            local count = (n > 0 and settings.others ~= "off") and (" |c" .. C.GREY .. TC.Plural("TOOLTIP_MORE_COUNT", n):format(n) .. "|r") or ""
            right = { text = W.notCollected .. count, color = settings.color }
        end
        local lines = {}
        if not item.collected and pendingText and item.bindsOnEquip then
            lines[1] = { text = pendingText, color = C.WHITE, mark = "bag", wrap = true }
        end
        return { nameRight = right, lines = lines }
    end
    local lines = { { text = " " } }
    if item.collected then
        lines[2] = { text = W.collected, color = C.COLLECTED, mark = "check" }
    else
        lines[2] = { text = W.notCollected, color = settings.color, mark = pendingText and "bag" or nil,
            right = item.source, rightColor = C.WHITE }
        if item.bindsOnEquip then
            lines[3] = { text = pendingText or L.BIND_ON_EQUIP_COLLECT, color = C.WHITE, wrap = true }
        end
        if settings.price and known.price then
            lines[#lines + 1] = { text = L.TOOLTIP_LOWEST_PRICE_AGE:format("|c" .. C.GREY .. known.price.age .. "|r"), color = C.GOLD,
                money = TC.BrowserState.MoneyParts(known.price.copper), rightColor = C.WHITE }
        end
    end
    local listed = settings.others == "always" or (settings.others == "notCollected" and not item.collected)
    if item.otherCount > 0 and listed then
        lines[#lines + 1] = { text = " " }
        lines[#lines + 1] = { text = W.otherItems, color = C.GOLD }
        for _, row in ipairs(item.others) do
            lines[#lines + 1] = { text = row.name, color = row.color, right = row.source,
                rightColor = row.collected and C.COLLECTED or C.WHITE, indent = ROW_INDENT }
        end
        if #item.others < item.otherCount then
            lines[#lines + 1] = { text = W.moreItems(item.otherCount - #item.others), color = C.GREY, indent = ROW_INDENT }
        end
    end
    return { lines = lines }
end

local function rgb(hex)
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- A line's left text with its mark before it.
local function leftText(line)
    return line.mark and ("|T" .. MARKS[line.mark] .. ":0|t " .. line.text) or line.text
end

-- A price as numbers each followed by a coin, marked up and spaced as the
-- game's money formatter does: a 14 square coin 2 right of its number, the
-- parts one space apart (Blizzard_SharedXML/MoneyFormatter.lua:63-67, 172,
-- 252); the browser's 12 square coin without the offset touched the next
-- number in the tooltip (testpass 1).
local function moneyMarkup(parts)
    local words = {}
    for i, part in ipairs(parts) do
        local coin = CreateAtlasMarkup and CreateAtlasMarkup(COIN_ATLAS[part.coin], 14, 14, 2, 0) or coinLetter(part.coin)
        words[i] = part.amount .. coin
    end
    return table.concat(words, " ")
end

-- A line description's texts as the tooltip shows them: the left with its
-- mark, the right (the price in coins, or the right text) or nil; and the
-- colours as r, g, b for each side (the settings page's preview draws them).
function Tooltip.Texts(line)
    local right = line.money and moneyMarkup(line.money) or line.right
    return leftText(line), right, line.color and { rgb(line.color) }, (line.rightColor or line.color) and { rgb(line.rightColor or line.color) }
end

-- The tooltip's settings from the stored values, as Tooltip.Lines takes them.
function Tooltip.Settings()
    return { style = TC.Setting("tooltipStyle"), color = TC.COLORS.NOT_COLLECTED[TC.Setting("notCollectedColor")],
        others = TC.Setting("otherItems"), price = TC.Setting("lowestPrice") }
end

local function addLine(tooltip, line)
    if not line.color then return tooltip:AddLine(line.text) end
    local r, g, b = rgb(line.color)
    local right = line.money and moneyMarkup(line.money) or line.right
    if right then
        local rr, rg, rb = rgb(line.rightColor or line.color)
        tooltip:AddDoubleLine(leftText(line), right, r, g, b, rr, rg, rb, line.wrap or false, line.indent)
    else
        tooltip:AddLine(leftText(line), r, g, b, line.wrap or false, line.indent)
    end
end

-- Compact: writes the line on the right of the name line, the tooltip's
-- first line (<name>TextRight1, SharedTooltipTemplates.xml:36), only when
-- that side is free: hidden or empty. Answers the text written once it
-- reads back, else nil, leaving the side as it was.
local function writeNameRight(tooltip, line)
    local name = tooltip.GetName and tooltip:GetName()
    local right = name and tooltip:NumLines() >= 1 and _G[name .. "TextRight1"]
    if not (right and right.GetText and right.SetText and right.IsShown and right.Show) then return nil end
    local was = right:GetText()
    if right:IsShown() and was and was ~= "" then return nil end
    local text = leftText(line)
    right:SetText(text)
    if right:GetText() ~= text then
        right:SetText(was)
        return nil
    end
    if right.SetTextColor then right:SetTextColor(rgb(line.color)) end
    right:Show()
    return text
end

-- What this addon last added to each tooltip, so a second post-call for
-- the same show adds nothing (SetOwner and ClearLines start the tooltip
-- over): the link, the line count, the last line's text and the text it
-- wrote on the name line.
local added = setmetatable({}, { __mode = "k" })
local function lineText(tooltip, side, n)
    local region = _G[tooltip:GetName() .. side .. n]
    return region and region.GetText and region:GetText()
end
local function alreadyAdded(tooltip, link)
    local mark = added[tooltip]
    if not (mark and mark.link == link and tooltip:NumLines() == mark.n) then return false end
    if lineText(tooltip, "TextLeft", mark.n) ~= mark.last then return false end
    if not mark.right then return true end
    local right = _G[tooltip:GetName() .. "TextRight1"]
    return right ~= nil and right:IsShown() and right:GetText() == mark.right
end

-- Whether a bag index is a carried bag: the backpack through the last
-- equipped bag (Enum.BagIndex, BagIndexConstantsDocumentation.lua:25-33;
-- NUM_TOTAL_EQUIPPED_BAG_SLOTS, Constants.lua:165-170). Bank tabs and the
-- keyring are outside it.
local function carriedBag(bag)
    if type(bag) ~= "number" then return false end
    local first = Enum and Enum.BagIndex and Enum.BagIndex.Backpack or 0
    return bag >= first and bag <= (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
end

-- "bags" for an item shown from a carried bag (SetBagItem(bag, slot) keeps
-- its arguments as getterArgs, TooltipDataHandler.lua:495-503; bank slots
-- use the same call, Camelot/BankFrame.lua:329-338), else what the browser
-- says is pending for its appearance.
local function pendingOf(tooltip, item)
    local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
    if type(info) == "table" and BAG_GETTERS[info.getterName] and type(info.getterArgs) == "table"
        and carriedBag(info.getterArgs[1]) then
        return "bags"
    end
    return TC.BrowserState.Pending(item.appearanceID)
end

local function priceOf(item)
    local copper, at = TC.BrowserState.SessionPrice(item.appearanceID)
    if copper then return { copper = copper, age = TC.BrowserState.Age(at) } end
end

-- Runs for every item tooltip of the game: whatever fails adds no line,
-- raises nothing and is reported once through the client's error handler.
local reported = false
local function AnnotateTooltip(tooltip)
    local ok, err = pcall(function()
        if not TC.Setting("tooltipShow") then return end
        local _, link = tooltip:GetItem()
        if not link or not tooltip:GetName() then return end
        if alreadyAdded(tooltip, link) then return end
        if stamp ~= settingsStamp() then memo, memoCount, stamp = {}, 0, settingsStamp() end
        local item = memo[link]
        if item == nil then
            item = itemOf(link)
            if memoCount >= MEMO_MAX then memo, memoCount = {}, 0 end
            memo[link] = item
            memoCount = memoCount + 1
            Debug("computed", link, item and "a line" or "no line")
        end
        if not item then return end
        local out = Tooltip.Lines(item, Tooltip.Settings(), { pending = pendingOf(tooltip, item), price = priceOf(item) })
        -- the name line's right side is written on GameTooltip only
        local written = out.nameRight and tooltip == GameTooltip and writeNameRight(tooltip, out.nameRight)
        -- the fallback: the name line's words as a line of their own
        if out.nameRight and not written then table.insert(out.lines, 1, out.nameRight) end
        for _, line in ipairs(out.lines) do addLine(tooltip, line) end
        StripBlizzardNotCollected(tooltip)
        local n = tooltip:NumLines()
        added[tooltip] = { link = link, n = n, last = lineText(tooltip, "TextLeft", n), right = written or nil }
        tooltip:Show()
    end)
    if not ok and not reported then
        reported = true
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
    end
end

-- The kept answers are dropped when the collection changes and when an item
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
    -- GameTooltip and ItemRefTooltip (a clicked chat link, ItemRef.xml:5);
    -- comparison, shopping and embedded tooltips stay untouched
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip or (ItemRefTooltip ~= nil and tooltip == ItemRefTooltip) then
            AnnotateTooltip(tooltip)
        end
    end)
end

print(L.LOADED_TOOLTIP)
