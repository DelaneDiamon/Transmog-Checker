-- The settings page (slice D2, addon-settings v1, layout A): one category
-- in the game's Options > AddOns, made with the client's settings API
-- (Blizzard_Settings_Shared/Blizzard_Settings.lua). A preview of the item
-- tooltip at the top, the language under it, then "Item tooltip" with six settings and "Appearances
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
-- Every text is read from the locale table (Locales/) when the page is
-- registered or drawn: after ADDON_LOADED has set the language.
local L = TC.L
-- The rows of "Item tooltip" (addon-settings v1, "Every setting"): label,
-- tooltip and, for a dropdown, its choices (value, label, colour), each
-- text by its locale key. "Include grey & white items" is
-- the inverse of the stored skipPoorAndCommon: ticked, the lines show on
-- them. A label fits the row's label column without "…": GameFontNormal
-- (Friz Quadrata 12, Fonts.xml:275-277) from the row's x 37 to 85 left of
-- its centre (Blizzard_SettingControls.lua:356-360), about 195 wide in the
-- default panel, 27 characters (slice F, F1). The hover text's title is the
-- label; its first sentence says what the setting does.
local ROWS = {
    { key = "tooltipShow", labelKey = "SETTING_SHOW", tipKey = "SETTING_SHOW_TIP" },
    { key = "tooltipStyle", labelKey = "SETTING_STYLE", tipKey = "SETTING_STYLE_TIP",
        choices = { { "full", labelKey = "STYLE_FULL" }, { "compact", labelKey = "STYLE_COMPACT" } } },
    { key = "notCollectedColor", labelKey = "SETTING_COLOR", tipKey = "SETTING_COLOR_TIP",
        choices = { { "orange", labelKey = "COLOR_ORANGE", color = "FFFF7F00" },
            { "lightBlue", labelKey = "COLOR_LIGHT_BLUE", color = "FF87ABFF" }, { "white", labelKey = "COLOR_WHITE" } } },
    { key = "otherItems", labelKey = "SETTING_OTHERS", tipKey = "SETTING_OTHERS_TIP",
        choices = { { "notCollected", labelKey = "OTHERS_NOT_COLLECTED" }, { "always", labelKey = "OTHERS_ALWAYS" },
            { "off", labelKey = "OTHERS_NEVER" } } },
    { key = "lowestPrice", labelKey = "SETTING_PRICE", tipKey = "SETTING_PRICE_TIP" },
    { key = "skipPoorAndCommon", labelKey = "SETTING_GREYS", tipKey = "SETTING_GREYS_TIP", inverted = true },
}
-- The funnel menu's entry keeps its longer wording, "Scan prices when the
-- tab opens"; the funnel's Settings… opens the page at this label.
local SCAN = { key = "scanWhenShown", labelKey = "SETTING_SCAN", tipKey = "SETTING_SCAN_TIP" }
-- The language setting, the general row under the preview: Auto, then each
-- language with a locale file by its own name: English, then the others in
-- the order of their codes.
local function languageChoices()
    local codes = {}
    for code in pairs(TC.Locales) do
        if code ~= "enUS" then codes[#codes + 1] = code end
    end
    table.sort(codes)
    if TC.Locales.enUS then table.insert(codes, 1, "enUS") end
    local choices = { { "auto", labelKey = "LANGUAGE_AUTO" } }
    for _, code in ipairs(codes) do choices[#choices + 1] = { code, label = TC.Locales[code].name } end
    return choices
end
local LANGUAGE = { key = "language", labelKey = "SETTING_LANGUAGE", tipKey = "SETTING_LANGUAGE_TIP", choices = languageChoices }

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
-- The page fits the default Options panel without scrolling: the list shows
-- 551 and the headings and settings, the language among them, take 408,
-- which leaves 143 for this row (the arithmetic with its sources is in
-- dev/browser-harness/run.lua, "G1").
-- So the samples are drawn one font step under the game's tooltip: the name
-- in GameTooltipText (12) where the tooltip has GameTooltipHeaderText (14),
-- the lines in GameTooltipTextSmall (10) where it has GameTooltipText (12)
-- (FontStyles.xml:314-322, Fonts.xml:1273-1275, 1385-1387, 1403-1405), each
-- line LINE_SPACING taller than its text, and at least 14 for the name and
-- 12 for a line (the roman fonts' 12 and 10, plus 2); a price line is as
-- tall as its 14 coins (TC_Tooltip.lua:231). A line's height is read from
-- its font string once its text is set: the same fonts take a taller member
-- for Chinese and Korean (13 for the name, 12 or 13 for a line,
-- Fonts.xml:1385-1420). A sample shows the item's name and the addon's
-- lines only, with one other item (i18n slice D: three left a Chinese or
-- Korean sample taller than the row). The tallest combination (Full, other
-- items shown, price on) in English is 2 * 8 + 14 + 6 * 12 + 14 = 116; with
-- Chinese or Korean lines of 15 and a name of 17 (the harness's model) 132;
-- the template's 140 leaves the rest for real fonts.
local PREVIEW_X, PREVIEW_Y, SAMPLE_GAP, SAMPLE_WIDTH = 37, 0, 16, 150
local PAD, HEAD_HEIGHT, LINE_HEIGHT, COIN_HEIGHT, LINE_SPACING = 8, 14, 12, 14, 2
local NAME_FONT, LINE_FONT = "GameTooltipText", "GameTooltipTextSmall"
-- A Chinese or Korean character is drawn a full em wide and tall: at least
-- WIDE_EM, the largest of those members' heights in either font
-- (Fonts.xml:1389-1396, 1407-1416). A font string's own measure is taken
-- when it is larger. Inferred from the owner's screenshot of an English
-- client set to 简体中文, where the samples were sized narrower and the
-- lines stepped shorter than the Chinese text drew.
local WIDE_EM = 13
-- A sample is as wide as its widest line, a line's left text, TEXT_GAP and
-- its right text, as the game's tooltip sizes itself to its lines (slice E,
-- E1; the gap is inferred from the 40 between a line's two texts in
-- SharedTooltipTemplates.xml:36-39), at least SAMPLE_WIDTH; the two stay
-- inside the row, ROW_EDGE from its right edge. Where the row is too
-- narrow, a left text wraps before it would reach its right text.
local TEXT_GAP, ROW_EDGE = 40, 8
-- The caption: CAPTION_GAP under the shorter sample, at its left, wrapped
-- where it would pass the row's right edge.
local CAPTION_GAP = 4
local UNCOMMON = "FF1EFF00"
-- The sample items' names (locale keys) and how long ago the price was seen.
local OTHERS = { { nameKey = "PREVIEW_OTHER_1" } }
local AGE_MINUTES = 3
local SAMPLES = {
    { nameKey = "PREVIEW_ITEM", collected = false, pending = "bags", copper = 4150 },
    { nameKey = "PREVIEW_COLLECTED_ITEM", collected = true },
}
local preview

local function sampleItem(collected)
    local source = TC.ClientText("TRANSMOG_SOURCE_4", "SOURCE_WORLD_DROP")
    local others = {}
    for i, other in ipairs(OTHERS) do others[i] = { name = L[other.nameKey], color = UNCOMMON, source = source, collected = false } end
    return { collected = collected, bindsOnEquip = true, source = source, others = others, otherCount = #OTHERS }
end

-- What is known of a sample at this show: what is pending and its price.
local function sampleKnown(spec)
    if not spec.copper then return { pending = spec.pending } end
    return { pending = spec.pending,
        price = { copper = spec.copper, age = TC.Plural("AGE_MINUTES", AGE_MINUTES):format(AGE_MINUTES) } }
end

-- How many Chinese or Korean characters a text shows (the three-byte
-- characters U+3000 to U+DFFF and U+F000 to U+FFFF, the full-width forms
-- among them), its colour codes and textures left out.
local function wideCount(text)
    text = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    local n = 0
    for _ in text:gmatch("[\227-\237\239][\128-\191][\128-\191]") do n = n + 1 end
    return n
end

-- A font string's text width: its own measure, at least WIDE_EM for each
-- Chinese or Korean character.
local function widthOf(fs)
    return math.max(fs:GetStringWidth(), wideCount(fs:GetText()) * WIDE_EM)
end

-- A font string's text height in lines of at most width (nil: one line):
-- its own measure, at least WIDE_EM a line for a text with a Chinese or
-- Korean character.
local function heightOf(fs, width)
    local own = fs.GetStringHeight and fs:GetStringHeight() or 0
    if wideCount(fs:GetText()) == 0 then return own end
    local lines = width and width > 0 and math.ceil(widthOf(fs) / width) or 1
    return math.max(own, lines * WIDE_EM)
end

-- Line i of a sample: a frame with its left and right text; the first in
-- the name's font.
local function rowOf(sample, i)
    local row = sample.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, sample)
    local font = i == 1 and NAME_FONT or LINE_FONT
    row.left = row:CreateFontString(nil, "OVERLAY", font)
    row.left:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", font)
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
        local width = widthOf(row.left) + (right and TEXT_GAP + widthOf(row.right) or 0)
        wanted = math.max(wanted, math.ceil(2 * PAD + (line.indent or 0) + width))
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
        if row.right:IsShown() then room = room - TEXT_GAP - widthOf(row.right) end
        local wrap = widthOf(row.left) > room
        row.left:SetWidth(wrap and room or 0)
        row.left:SetWordWrap(wrap)
        -- as tall as its taller text, read now that the text and width are set
        local text = heightOf(row.left, wrap and room or nil)
        if row.right:IsShown() then text = math.max(text, heightOf(row.right)) end
        local height = math.max(i == 1 and HEAD_HEIGHT or LINE_HEIGHT, math.ceil(text) + LINE_SPACING)
        if line.money then height = math.max(height, COIN_HEIGHT) end
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
        local name = { text = L[spec.nameKey], color = UNCOMMON }
        local lines = { name }
        if TC.Setting("tooltipShow") then
            local out = TC.Tooltip.Lines(item, TC.Tooltip.Settings(), sampleKnown(spec))
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
    local first, second = preview.samples[1], preview.samples[2]
    local shorter = second:GetHeight() <= first:GetHeight() and second or first
    local caption = preview.caption
    caption:ClearAllPoints()
    caption:SetPoint("TOPLEFT", shorter, "BOTTOMLEFT", 0, -CAPTION_GAP)
    -- the room from the shorter sample's left to the row's right edge
    local room = parent and parent:GetWidth()
    room = room and room > 0 and math.floor(room - ROW_EDGE - (shorter == first and PREVIEW_X or PREVIEW_X + widths[1] + SAMPLE_GAP))
    caption:SetWidth(0)
    local wrap = room and widthOf(caption) > room or false
    caption:SetWidth(wrap and room or 0)
    caption:SetWordWrap(wrap)
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
    -- the caption in the lines' font, in the grey of GameFontDisableSmall
    local caption = preview:CreateFontString(nil, "OVERLAY", LINE_FONT)
    caption:SetJustifyH("LEFT")
    if DISABLED_FONT_COLOR and DISABLED_FONT_COLOR.GetRGB then
        caption:SetTextColor(DISABLED_FONT_COLOR:GetRGB())
    else
        caption:SetTextColor(0.5, 0.5, 0.5)
    end
    caption:SetText(L.PREVIEW_CAPTION)
    preview.caption = caption
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
    local setting = Settings.RegisterProxySetting(cat, variable(row.key), kind, L[row.labelKey], default, get, set)
    settings[row.key] = setting
    if not row.choices then return Settings.CreateCheckbox(cat, setting, L[row.tipKey]) end
    -- a choice's label: its own (a language's name) or its locale key's, in its colour
    local function label(choice)
        local text = choice.label or L[choice.labelKey]
        return choice.color and ("|c" .. choice.color .. text .. "|r") or text
    end
    local function options()
        local container = Settings.CreateControlTextContainer()
        local choices = type(row.choices) == "function" and row.choices() or row.choices
        for _, choice in ipairs(choices) do container:Add(choice[1], label(choice)) end
        return container:GetData()
    end
    return Settings.CreateDropdown(cat, setting, options, L[row.tipKey])
end

-- The game's reload prompt (StaticPopup_Show, Blizzard_StaticPopup/
-- StaticPopup.lua:309), in the form Blizzard's own reload dialogs take
-- (Blizzard_AddOnPerformance/AddOnPerformance.lua:1-13) with Blizzard's
-- button texts RELOADUI (Blizzard_AddOnList/AddonList.lua:541) and LATER
-- (Blizzard_WowSurveyUI/Blizzard_WowSurveyUI.lua:4): windows are built
-- once, so a new language shows after a reload. The buttons are the client's
-- RELOADUI and LATER in its own language, ours otherwise (TC.ClientText).
local RELOAD_DIALOG = "TRANSMOGCHECKER_RELOAD"
local function promptReload()
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs[RELOAD_DIALOG] = { text = L.RELOAD_PROMPT, button1 = TC.ClientText("RELOADUI", "RELOAD_UI"),
        button2 = TC.ClientText("LATER", "LATER"),
        OnAccept = function() if ReloadUI then ReloadUI() end end, timeout = 0, whileDead = 1, hideOnEscape = 1 }
    StaticPopup_Show(RELOAD_DIALOG)
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
    -- the language: stored at once, read after the reload the prompt offers
    control(cat, LANGUAGE, function() return TC.Setting("language") end, function(value)
        local was = TC.Setting("language")
        if TC.SetSetting("language", value) and value ~= was then promptReload() end
    end, TC.SettingDefault("language"))
    header(layout, L.SECTION_TOOLTIP)
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
        header(layout, L.SECTION_BROWSER)
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
        say(L.SETTINGS_AFTER_COMBAT)
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
