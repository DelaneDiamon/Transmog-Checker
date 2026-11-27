-- The settings page (slice D2, addon-settings v1, layout A): one category
-- in the game's Options > AddOns, made with the client's settings API
-- (Blizzard_Settings_Shared/Blizzard_Settings.lua). A preview of the item
-- tooltip at the top, then "Item tooltip" with six settings and "Appearances
-- tab" with Scan prices when tab opens (labels: slice F, F1). Each
-- setting is a proxy setting (Settings.RegisterProxySetting(category,
-- variable, variableType, name, defaultValue, getValue, setValue),
-- Blizzard_Settings.lua:178-180) over the addon's own stored value: TC.Setting / TC.SetSetting, and for Scan when
-- shown the browser state's accessor, so each value has one place; a change
-- made elsewhere (a slash shortcut, the funnel menu) is told to the page
-- through TC.WatchSettings and the setting's NotifyUpdate
-- (Blizzard_Setting.lua:179-188). Blizzard's Defaults button sets each to the
-- default it was registered with (Blizzard_SettingsPanel.lua:500-525).
-- Nothing is made at load: the page is registered once the saved table is
-- in place (TransmogChecker.lua, ADDON_LOADED), and the preview's frames are
-- made when the page first shows. Without the API nothing is registered and
-- Available answers false.
TC = TC or {}
TC.Settings = {}

local Page = TC.Settings

local NAME = "TransmogChecker"
local SECTION_TOOLTIP, SECTION_BROWSER = "Item tooltip", "Appearances tab"
-- The rows of "Item tooltip" (addon-settings v1, "Every setting"): label,
-- tooltip and, for a dropdown, its choices. "Include grey & white items" is
-- the inverse of the stored skipPoorAndCommon: ticked, the lines show on
-- them. A label fits the row's label column without "…": GameFontNormal
-- (Friz Quadrata 12, Fonts.xml:275-277) from the row's x 37 to 85 left of
-- its centre (Blizzard_SettingControls.lua:356-360), about 195 wide in the
-- default panel, 27 characters (slice F, F1). The hover text's title is the
-- label; its first sentence says what the setting does.
local ROWS = {
    { key = "tooltipShow", label = "Show collection status",
        tip = "Adds lines to item tooltips that say whether the item's appearance is collected." },
    { key = "tooltipStyle", label = "Tooltip style",
        tip = "Full: the status, how to collect it, the lowest price and other items. Compact: the status on the item's name line.",
        choices = { { "full", "Full" }, { "compact", "Compact" } } },
    { key = "notCollectedColor", label = "\"Not collected\" text color", tip = "The color of \"Not collected\" on item tooltips.",
        choices = { { "orange", "|cFFFF7F00Orange|r" }, { "lightBlue", "|cFF87ABFFLight blue|r" }, { "white", "White" } } },
    { key = "otherItems", label = "Other items with this look",
        tip = "Lists the other items that give the same appearance. Full shows where each comes from; Compact shows only how many.",
        choices = { { "notCollected", "Only when not collected" }, { "always", "Always" }, { "off", "Never" } } },
    { key = "lowestPrice", label = "Lowest auction price",
        tip = "Shows the lowest auction price the Appearances tab has seen for this appearance since you logged in or reloaded. Full style only." },
    { key = "skipPoorAndCommon", label = "Include grey & white items",
        tip = "Also shows collection status on grey (Poor) and white (Common) items.", inverted = true },
}
-- The funnel menu's entry keeps its longer wording, "Scan prices when the
-- tab opens"; the funnel's Settings… opens the page at this label.
local SCAN = { key = "scanWhenShown", label = "Scan prices when tab opens",
    tip = "Scans the auction house for the selected slot each time the Appearances tab is shown." }

local category
-- the registered settings by stored key
local settings = {}

local function say(text)
    print("|cFF9D9D9DTC:|r " .. text)
end

local function variable(key)
    return NAME .. "_" .. key
end

---------------------------------------------------------------- the preview

-- The preview (addon-settings v1, A): two sample tooltips side by side, an
-- item not collected with five other items and a price, and the same look
-- collected, drawn from the tooltip module's own lines (TC.Tooltip.Lines)
-- with the stored settings, in frames of the addon's own (no GameTooltip,
-- nothing read from the auction house). The list holds it in a frame of
-- TransmogCheckerPreviewTemplate (TC_Settings.xml), Blizzard's own pattern
-- (Settings.CreatePanelInitializer, Blizzard_Settings.lua:355-357, as
-- Nameplates.lua:556 and Subtitles.lua:76 use it): the row's height is the
-- template's (Blizzard_SettingsList.lua:68-71), and the initializer's own
-- InitFrame and Resetter call the frame's Init and Release
-- (ScrollUtil.lua:1697-1707), the mixin below. No field of the initializer
-- is written: the list reads them in its own code (Blizzard_SettingsList.lua:57-71).
local PREVIEW_X, PREVIEW_Y, SAMPLE_GAP, SAMPLE_WIDTH = 37, -8, 16, 290
local PAD, HEAD_HEIGHT, LINE_HEIGHT = 9, 17, 15
-- A sample is as wide as its widest line that does not wrap, a line's left
-- text, TEXT_GAP and its right text, as the game's tooltip sizes itself to
-- its lines (slice E, E1; the gap is inferred from the 40 between a line's
-- two texts in SharedTooltipTemplates.xml:36-39), at least SAMPLE_WIDTH;
-- the two stay inside the row, ROW_EDGE from its right edge. Where the row
-- is too narrow, a left text wraps before it would reach its right text.
local TEXT_GAP, ROW_EDGE = 40, 8
local CAPTION = "Preview: a sample item, not your collection"
local UNCOMMON, WHITE = "FF1EFF00", "FFFFFFFF"
local OTHERS = { "Ivycloth Boots of Intellect", "Ivycloth Boots of the Owl", "Ivycloth Boots of Spirit" }
local SAMPLES = {
    { name = "Ivycloth Boots of the Eagle", collected = false,
        known = { pending = "bags", price = { copper = 4150, age = "3 min ago" } } },
    { name = "Runecloth Boots", collected = true, known = {} },
}
local preview

local function sampleItem(collected)
    local source = _G.TRANSMOG_SOURCE_4 or "World Drop"
    local others = {}
    for i, name in ipairs(OTHERS) do others[i] = { name = name, color = UNCOMMON, source = source, collected = false } end
    return { collected = collected, bindsOnEquip = true, source = source, others = others, otherCount = 5 }
end

-- Line i of a sample: a frame with its left and right text; the first in
-- the tooltip's header font.
local function rowOf(sample, i)
    local row = sample.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, sample)
    local font = i == 1 and "GameTooltipHeaderText" or "GameTooltipText"
    row.left = row:CreateFontString(nil, "OVERLAY", font)
    row.left:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.right:SetJustifyH("RIGHT")
    sample.rows[i] = row
    return row
end

-- Writes a sample's lines (descriptions as TC.Tooltip.Lines gives them)
-- and answers the width they ask for.
local function fillSample(sample, lines)
    local wanted = SAMPLE_WIDTH
    for i, line in ipairs(lines) do
        local row = rowOf(sample, i)
        local left, right, color, rightColor = TC.Tooltip.Texts(line)
        row.left:SetWidth(0)
        row.left:SetText(left)
        row.left:SetTextColor(unpack(color or { 1, 1, 1 }))
        row.right:SetText(right or "")
        row.right:SetShown(right ~= nil)
        if rightColor then row.right:SetTextColor(unpack(rightColor)) end
        if not line.wrap then
            local width = row.left:GetStringWidth() + (right and TEXT_GAP + row.right:GetStringWidth() or 0)
            wanted = math.max(wanted, math.ceil(2 * PAD + (line.indent or 0) + width))
        end
    end
    for i = #lines + 1, #sample.rows do sample.rows[i]:Hide() end
    return wanted
end

-- Lays a sample's lines out in its width and sizes it to them.
local function placeSample(sample, lines, width)
    local inner, y = width - 2 * PAD, -PAD
    sample:SetWidth(width)
    for i, line in ipairs(lines) do
        local row = rowOf(sample, i)
        local indent = line.indent or 0
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sample, "TOPLEFT", PAD + indent, y)
        row:SetWidth(inner - indent)
        local room = inner - indent
        if row.right:IsShown() then room = room - TEXT_GAP - row.right:GetStringWidth() end
        local wrap = line.wrap == true or row.left:GetStringWidth() > room
        row.left:SetWidth(wrap and room or 0)
        row.left:SetWordWrap(wrap)
        local height = i == 1 and HEAD_HEIGHT or LINE_HEIGHT
        if wrap then height = math.max(height, row.left:GetStringHeight()) end
        row:SetHeight(height)
        row:Show()
        y = y - height
    end
    sample:SetHeight(PAD - y)
end

-- The two samples' widths inside the row: each as wide as it asks, unless
-- the two do not fit; then the narrower keeps its width, up to half the
-- room, and the other takes the rest. A row of no width yet limits nothing
-- (the preview draws again when its size changes).
local function widthsIn(rowWidth, first, second)
    if not (rowWidth and rowWidth > 0) then return first, second end
    local room = math.floor(rowWidth - PREVIEW_X - SAMPLE_GAP - ROW_EDGE)
    if first + second <= room then return first, second end
    local half = math.floor(room / 2)
    if first <= half then return first, room - first end
    if second <= half then return room - second, second end
    return half, room - half
end

local function draw()
    if not (preview and preview:IsShown()) then return end
    local all, wanted = {}, {}
    for i, spec in ipairs(SAMPLES) do
        local item = sampleItem(spec.collected)
        local name = { text = spec.name, color = UNCOMMON }
        local lines = { name, { text = "Binds when equipped", color = WHITE },
            { text = "Feet", color = WHITE, right = "Cloth", rightColor = WHITE } }
        if TC.Setting("tooltipShow") then
            local out = TC.Tooltip.Lines(item, TC.Tooltip.Settings(), spec.known)
            -- Compact: the status on the right of the name line
            if out.nameRight then name.right, name.rightColor = (TC.Tooltip.Texts(out.nameRight)), out.nameRight.color end
            for _, line in ipairs(out.lines) do lines[#lines + 1] = line end
        end
        all[i], wanted[i] = lines, fillSample(preview.samples[i], lines)
    end
    local parent = preview:GetParent()
    local widths = { widthsIn(parent and parent:GetWidth(), wanted[1], wanted[2]) }
    local x = PREVIEW_X
    for i, sample in ipairs(preview.samples) do
        sample:ClearAllPoints()
        sample:SetPoint("TOPLEFT", preview, "TOPLEFT", x, PREVIEW_Y)
        placeSample(sample, all[i], widths[i])
        x = x + widths[i] + SAMPLE_GAP
    end
end

local function build(parent)
    preview = CreateFrame("Frame", nil, parent)
    preview.samples = {}
    for i = 1, #SAMPLES do
        local sample = CreateFrame("Frame", nil, preview)
        local background = sample:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.03, 0.03, 0.04, 0.94)
        sample.rows = {}
        preview.samples[i] = sample
    end
    local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -24, 8)
    caption:SetText(CAPTION)
    -- the row's width is the list's: the samples are placed again in it
    preview:SetScript("OnSizeChanged", draw)
end

local function showPreview(frame)
    if not preview then build(frame) end
    preview:SetParent(frame)
    preview:ClearAllPoints()
    preview:SetAllPoints(frame)
    preview:Show()
    draw()
end

local function releasePreview(frame)
    if preview and preview:GetParent() == frame then
        preview:Hide()
        preview:SetParent(nil)
    end
end

-- The template's mixin (TC_Settings.xml names it; this file loads first).
TransmogCheckerPreviewMixin = {}
function TransmogCheckerPreviewMixin:Init() showPreview(self) end
function TransmogCheckerPreviewMixin:Release() releasePreview(self) end

---------------------------------------------------------------- the page

local function hasAPI()
    return type(Settings) == "table" and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory
        and Settings.RegisterProxySetting and Settings.CreateCheckbox and Settings.CreateDropdown
        and Settings.CreateControlTextContainer and Settings.OpenToCategory and true or false
end

local function header(layout, text)
    if CreateSettingsListSectionHeaderInitializer and layout and layout.AddInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
end

-- A row's control: a checkbox for a true/false value, else a dropdown of
-- its choices (Blizzard_Settings.lua:364-377, 388-413; the choices as
-- Blizzard_ImplementationReadme.lua:174-181 builds them).
local function control(cat, row, get, set, default)
    local VarType = Settings.VarType or {}
    local kind = row.choices and (VarType.String or "string") or (VarType.Boolean or "boolean")
    local setting = Settings.RegisterProxySetting(cat, variable(row.key), kind, row.label, default, get, set)
    settings[row.key] = setting
    if not row.choices then return Settings.CreateCheckbox(cat, setting, row.tip) end
    local function options()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(row.choices) do container:Add(choice[1], choice[2]) end
        return container:GetData()
    end
    return Settings.CreateDropdown(cat, setting, options, row.tip)
end

-- A row is greyed while the predicate answers false, and looked at again
-- when the named setting changes (SettingsElementHierarchyMixin:
-- AddModifyPredicate and AddEvaluateStateCVar, which listens by setting
-- variable, Blizzard_SettingControls.lua:156-196, 350-353).
local function greyUnless(init, predicate, key)
    if not (init and init.AddModifyPredicate) then return end
    init:AddModifyPredicate(predicate)
    if init.AddEvaluateStateCVar then init:AddEvaluateStateCVar(variable(key)) end
end

-- A value changed somewhere: a shown control reads it again, unless the
-- change is the setting's own (locked while it writes, Blizzard_Setting.lua:
-- 124-137); the preview is drawn again.
local function changed(key)
    local setting = settings[key]
    if setting and setting.NotifyUpdate and not (setting.IsLocked and setting:IsLocked()) then setting:NotifyUpdate() end
    draw()
end

local function register()
    local cat, layout = Settings.RegisterVerticalLayoutCategory(NAME)
    if Settings.CreatePanelInitializer and layout and layout.AddInitializer then
        layout:AddInitializer(Settings.CreatePanelInitializer("TransmogCheckerPreviewTemplate", {}))
    end
    header(layout, SECTION_TOOLTIP)
    local function shown() return TC.Setting("tooltipShow") end
    for _, row in ipairs(ROWS) do
        local key, inverted = row.key, row.inverted
        local function get()
            if inverted then return not TC.Setting(key) end
            return TC.Setting(key)
        end
        local function set(value)
            if inverted then value = not value end
            TC.SetSetting(key, value)
        end
        local default = TC.SettingDefault(key)
        if inverted then default = not default end
        local init = control(cat, row, get, set, default)
        if key ~= "tooltipShow" then greyUnless(init, shown, "tooltipShow") end
        if key == "lowestPrice" then
            greyUnless(init, function() return TC.Setting("tooltipStyle") ~= "compact" end, "tooltipStyle")
        end
    end
    local State = TC.BrowserState
    if State and State.ScanWhenShown and State.SetScanWhenShown then
        header(layout, SECTION_BROWSER)
        control(cat, SCAN, State.ScanWhenShown, State.SetScanWhenShown, true)
    end
    Settings.RegisterAddOnCategory(cat)
    category = cat
end

-- Registers the page, once, where the client has the API. A registration
-- that raises leaves no page and is reported once through the client's
-- error handler.
function Page.Register()
    if category or not hasAPI() then return end
    local ok, err = pcall(register)
    if not ok then
        category = nil
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
        return
    end
    TC.WatchSettings(changed)
end

-- Whether the page exists: the entry points offer it only then.
function Page.Available()
    return category ~= nil
end

-- Opens the game's Options at the page, scrolled to the named setting when
-- one is given (Settings.OpenToCategory(categoryID, scrollToElementName),
-- Blizzard_Settings.lua:144-146, Blizzard_ImplementationReadme.lua:194-208).
-- It calls C_SettingsUtil.OpenSettingsPanel, which has restrictions
-- (SettingsUtilDocumentation.lua:15-17): the panel shows through
-- ShowUIPanel, which refuses addon code in combat
-- (UIParentPanelManager.lua:854-861, 886-888). In combat, one line, and the
-- page opens when combat ends. Answers false without the page.
local afterCombat
function Page.Open(element)
    if not category then return false end
    if InCombatLockdown and InCombatLockdown() then
        say("Settings open after combat.")
        if not afterCombat then
            afterCombat = CreateFrame("Frame")
            afterCombat:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                Settings.OpenToCategory(category:GetID(), self.element)
            end)
        end
        afterCombat.element = element
        afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
        return true
    end
    Settings.OpenToCategory(category:GetID(), element)
    return true
end
