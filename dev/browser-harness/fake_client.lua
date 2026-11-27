-- A fake WoW: Forever client for the browser harness. It defines the globals
-- the addon's files call, keeps Collections' own settings so a test can see
-- whether the addon left them as it found them, and fires events at the
-- frames that registered for them. Dev-only; never shipped.
local Fake = {}
-- The C_* tables already made to record calls (Fake.new makes new ones).
local traceWrapped = setmetatable({}, { __mode = "k" })
-- Lua's own global functions as the harness found them: a click's recorder
-- (c.click) wraps every other global function, and pcall and xpcall.
local STANDARD = {}
for name, v in pairs(_G) do
    if type(v) == "function" then STANDARD[name] = v end
end
local rawPcall = pcall

local PLAYER_CLASS = 9 -- Warlock, the character the probe ran on

-- Enum.TransmogCollectionType (TransmogSharedDocumentation.lua:6-40).
local CATEGORIES = { None = 0, Head = 1, Shoulder = 2, Back = 3, Chest = 4, Shirt = 5, Tabard = 6, Wrist = 7,
    Hands = 8, Waist = 9, Legs = 10, Feet = 11, Wand = 12, OneHAxe = 13, OneHSword = 14, OneHMace = 15, Dagger = 16,
    Fist = 17, Shield = 18, Holdable = 19, TwoHAxe = 20, TwoHSword = 21, TwoHMace = 22, Staff = 23, Polearm = 24,
    Bow = 25, Gun = 26, Crossbow = 27, Warglaives = 28, Paired = 29 }
Fake.CATEGORIES = CATEGORIES
-- The inventory slot each armor category is listed for (spec 4.3), and the
-- weapon slot of each weapon category in the fixed split.
local SLOT_OF_CATEGORY = { [1] = 1, [2] = 3, [3] = 15, [4] = 5, [5] = 4, [6] = 19, [7] = 9, [8] = 10, [9] = 6,
    [10] = 7, [11] = 8, [12] = 18, [13] = 16, [14] = 16, [15] = 16, [16] = 16, [17] = 16, [18] = 17, [19] = 17,
    [20] = 16, [21] = 16, [22] = 16, [23] = 16, [24] = 16, [25] = 18, [26] = 18, [27] = 18 }
Fake.SLOT_OF_CATEGORY = SLOT_OF_CATEGORY
-- The client's names of the weapon categories, made up for the fake.
local CATEGORY_NAMES = { [12] = "Wands", [13] = "One-Handed Axes", [14] = "One-Handed Swords",
    [15] = "One-Handed Maces", [16] = "Daggers", [17] = "Fist Weapons", [18] = "Shields", [19] = "Held In Off-hand",
    [20] = "Two-Handed Axes", [21] = "Two-Handed Swords", [22] = "Two-Handed Maces", [23] = "Staves",
    [24] = "Polearms", [25] = "Bows", [26] = "Guns", [27] = "Crossbows", [28] = "Warglaives" }
-- The weapon categories GetCategoryInfo answers for under each class filter,
-- as /tcprobe weapons measured them on 2026-11-25 (main hand, off hand,
-- ranged); 28 and 29 answer for no class.
local WEAPON_CATEGORIES_OF_CLASS = {}
for classID, categories in pairs({
    [1] = { 13, 14, 15, 16, 17, 20, 21, 22, 23, 24, 18, 19, 25, 26, 27 },
    [2] = { 13, 14, 15, 20, 21, 22, 24, 18, 19 },
    [3] = { 13, 14, 16, 17, 20, 21, 23, 24, 19, 25, 26, 27 },
    [4] = { 13, 14, 15, 16, 17, 19, 25, 26, 27 },
    [5] = { 15, 16, 23, 19, 12 },
    [7] = { 13, 15, 16, 17, 20, 22, 23, 18, 19 },
    [8] = { 14, 16, 23, 19, 12 },
    [9] = { 16, 23, 19, 12 },
    [11] = { 15, 16, 17, 22, 23, 24, 19 },
}) do
    WEAPON_CATEGORIES_OF_CLASS[classID] = {}
    for _, category in ipairs(categories) do WEAPON_CATEGORIES_OF_CLASS[classID][category] = true end
end

-- A fixture of one category (default Head): total appearances from id
-- `first` + 1 on (default 1000), the first `collected` of them (by id)
-- collected through one of their three sources, and two hidden visuals.
-- classes is not read by the fake: a category's list is the same under
-- every class filter (measured in game on 2026-11-25).
function Fake.appearances(total, collected, category, first)
    local list = {}
    first = first or 1000
    for i = 1, total do
        local id = first + i
        local sources = { id * 10 + 1, id * 10 + 2, id * 10 + 3 }
        list[#list + 1] = {
            id = id, uiOrder = total - i, minIlvl = i, sources = sources, category = category,
            collectedSource = i <= collected and sources[3] or nil,
            classes = { [PLAYER_CLASS] = true, [8] = true },
        }
    end
    local extra = first * 9 + 1
    list[#list + 1] = { id = extra, uiOrder = 0, sources = { extra * 10 + 1 }, hide = true, category = category,
        classes = { [PLAYER_CLASS] = true } }
    list[#list + 1] = { id = extra + 1, uiOrder = 0, sources = { extra * 10 + 11 }, hide = true, category = category,
        classes = { [PLAYER_CLASS] = true } }
    return list
end

-- opts:
--   appearances     fixture list (default: 370 Head appearances, 5 collected);
--                   an entry's category is Head (1) unless it says another
--   noCategoryInfo  GetCategoryInfo answers nothing for every category, as
--                   it did for feet in game
--   categoryInfo    { [category] = { name, isWeapon, canHaveIllusions,
--                   canMainHand, canOffHand, canRanged } } replaces the fake's
--                   answers under every class filter (by default a weapon
--                   category answers, with the fixed split's flags, when the
--                   class filter's class has it in the measured table;
--                   armor categories answer nothing)
--   classCategories { [classID] = { category, ... } } replaces the measured
--                   weapon categories of those classes
--   lagByOne        a GetCategoryInfo read in the frame of a SetClassFilter
--                   write answers for the class set one write earlier
--   classFilter     Collections' class filter at the start (default the player's)
--   playerClass     UnitClass's { name, class file, id } (default the Warlock)
--   uncollectedShown, collectedShown, search: Collections' other settings
--   listRaises      GetCategoryAppearances raises an error (true: always;
--                   a number: on that many first reads)
--   listRaisesFor   GetCategoryAppearances raises for that category
--   noEnumMembers   a list of { enum name, member } the client lacks
--   noAuctionErrors Enum.AuctionHouseError is nil
--   listNil         GetCategoryAppearances returns nil
--   listEmpty       the first that many reads of GetCategoryAppearances
--                   return an empty table
--   setClassRaises  SetClassFilter changes the filter and then raises
--   setClassRaisesFor  SetClassFilter for that class changes the filter and
--                   then raises
--   setClassIgnoredFor SetClassFilter for that class changes nothing
--   setClassIgnoredAt  a list of call numbers (the first call is 1) of
--                   SetClassFilter that change nothing
--   getClassFilterRaises  GetClassFilter raises an error
--   setClassFires   SetClassFilter fires TRANSMOG_COLLECTION_UPDATED at once
--   noTransmog      C_TransmogCollection is nil
--   noList          C_TransmogCollection.GetCategoryAppearances is nil
--   noCompare       CollectionWardrobeUtil is nil
--   noSortSources   CollectionWardrobeUtil.SortSources is nil
--   sourcesNil      GetAppearanceSources returns nil
--   noButtonTemplate  CreateFrame raises for UIPanelButtonTemplate
--   noMenuTemplates CreateFrame raises for the menu's dropdown templates
--   noMenuAPI       the dropdown templates lack SetupMenu and the text methods
--   noFontObjects   the GameFont* font objects are nil
--   items           { [itemID] = { name, quality, bindType, subType, load,
--                   classID, subClassID } }:
--                   item data; load nil means cached at the start, a number
--                   loads that many seconds after RequestLoadItemDataByID,
--                   "never" never loads, "fail" answers
--                   ITEM_DATA_LOAD_RESULT with success false 0.1 s after
--                   the request and never loads. classID and subClassID are
--                   what GetItemInfoInstant answers at once, loaded or not; a
--                   listed item without them answers nothing. An item not
--                   listed is a cached bind-on-equip green cloth armor piece
--                   named "Item <id>".
--   noItemInstant   C_Item.GetItemInfoInstant is nil
--   noClassList     C_SpecializationInfo and C_CreatureInfo are nil
--   sourceItems     { [sourceID] = itemID } (default: the source id itself)
--   sourceInfoNil   GetSourceInfo answers nothing
--   noAuctionHouse  C_AuctionHouse is nil
--   noAuction       a list of C_AuctionHouse function names that are nil
--   noTimer         C_Timer is nil
--   noItemTransmog  C_TransmogCollection.GetItemInfo is nil
--   noScanEnums     Enum.ItemClass is nil
--   noMoney         GetMoney is nil (c.money is the player's copper)
--   noEscHandlers   RegisterGameMenuEscHandler is nil
--   noTemplates     { [template] = true }: CreateFrame raises for those
--   noAtlases       true, or { [atlas] = true }: C_Texture.GetAtlasInfo
--                   answers nothing for every atlas, or for those
--   noSetLight      models have no SetLight
--   noGetOwner      GameTooltip has no GetOwner
--   noMaskAPI       CreateMaskTexture and AddMaskTexture are nil
--   noLightMakers   CreateColor and CreateVector3D are nil
--   fileIDs         GetFileIDFromPath exists and answers these ({ [path] = id })
--   missingFiles    { [path] = true }: SetTexture answers false for those
--   settings        the client has the settings API (see c.settings)
--   realSortSources CollectionWardrobeUtil.SortSources is Blizzard's
--   drops           { [sourceID] = drops } for GetAppearanceSourceDrops
--   useErrors       { [sourceID] = text }: the sources' useError
--   holidays        { [sourceID] = name } for GetSourceRequiredHoliday;
--                   holidayRaises: it raises
--   sets, setInfo, noSets: C_TransmogSets (see there)
--   items also take minLevel and equipLoc (GetItemInfo, GetItemInfoInstant)
--   and icon (GetItemIconByID; false: none)
--   an appearance's sourceTypes: the source type of each source (default 4)
--   filterCategory  Collections' search-and-filter category at the start
--                   (TC-43, measured in game on 2026-11-26): the one category
--                   whose list Collections' filters narrow. Its list leaves
--                   out the not collected appearances while uncollectedShown
--                   is false, the collected ones while collectedShown is
--                   false, and an appearance whose filteredOut is true (what
--                   else narrowed 245 to 80 in game); hidden visuals stay.
--                   GetCategoryTotal is never narrowed;
--                   GetFilteredCategoryTotal is the total less what the
--                   filters leave out, so below it only for that category.
--                   An appearance whose unlisted is true is counted in both
--                   totals and never listed (a category short for another
--                   reason, TC-43 QA E1).
--   filterLag      when a SetSearchAndFilterCategory write reaches a list
--                   read: nil at once, "frame" on the next frame, "never"
--   filterCategoryFires  SetSearchAndFilterCategory fires
--                   TRANSMOG_COLLECTION_UPDATED at once
--   noFilterCategorySet  C_TransmogCollection.SetSearchAndFilterCategory is nil
--   noCategoryTotal C_TransmogCollection.GetCategoryTotal is nil
--   listRaisesOn    { [n] = true }: the nth GetCategoryAppearances call raises
--   listRaisesAway  GetCategoryAppearances raises while the filter category
--                   read is Paired (29)
--   noFilteredTotal C_TransmogCollection.GetFilteredCategoryTotal is nil
--   totalRaises     GetCategoryTotal raises
--   categoryRaisesOn { [n] = true }: the nth SetSearchAndFilterCategory call
--                   raises and changes nothing (not in c.writes)
--   c.writes: every write to Collections' class filter and search-and-filter
--   category, in order, as { kind = "class" or "category", value, at }
function Fake.new(opts)
    opts = opts or {}
    local c = {
        widgets = {}, misuse = {}, forbidden = {}, auctionTouches = {},
        tryOn = {}, cameras = {}, printed = {},
        collections = {
            classFilter = opts.classFilter or PLAYER_CLASS,
            uncollectedShown = opts.uncollectedShown == nil and false or opts.uncollectedShown,
            collectedShown = opts.collectedShown == nil and true or opts.collectedShown,
            search = opts.search or "",
            filterCategory = opts.filterCategory,
        },
        writes = {}, listCalls = 0, listed = {}, categoryInfoCalls = 0, itemAppearances = {},
    }
    local appearances = opts.appearances or Fake.appearances(370, 5)
    local byID, collectedSources = {}, {}
    for _, a in ipairs(appearances) do
        a.category = a.category or CATEGORIES.Head
        byID[a.id] = a
        if a.collectedSource then collectedSources[a.collectedSource] = true end
    end
    c.collectedSources = collectedSources
    -- the inventory slot each source is worn in
    c.slotOfSource, c.categoryOfSource = {}, {}
    for _, a in ipairs(appearances) do
        for _, source in ipairs(a.sources) do
            c.slotOfSource[source], c.categoryOfSource[source] = SLOT_OF_CATEGORY[a.category], a.category
        end
    end

    local function misuse(cond, what)
        if not cond then c.misuse[#c.misuse + 1] = what end
    end
    -- The calls a click makes before its PlaceBid: from the start of a
    -- c.click until PlaceBid, every frame method, every C_* function (on
    -- C_AuctionHouse every field read but PlaceBid's), a ticker's Cancel and
    -- GetMoney is recorded in c.trace by name, and so are, while the click
    -- runs, every other global function, pcall, xpcall and every function
    -- of a TC module (wrapForClick); each bid keeps its list as bid.before.
    c.trace = {}
    local function traced(name)
        if c.tracing then c.trace[#c.trace + 1] = name end
    end
    function c.snapshot()
        local s = {}
        for k, v in pairs(c.collections) do s[k] = v end
        return s
    end

    -- Widgets: every method exists. Known ones keep state; the rest record
    -- the call, so a test can read what the panel did.
    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:SetScript(name, fn) self.scripts[name] = fn end
    function methods:GetScript(name) return self.scripts[name] end
    -- ScriptObject:HookScript runs the hook after the script there is.
    function methods:HookScript(name, fn)
        local old = self.scripts[name]
        self.scripts[name] = function(...)
            if old then old(...) end
            fn(...)
        end
    end
    -- A button's highlight held on (SimpleFrameAPIDocumentation.lua:983).
    function methods:LockHighlight() self.highlightLocked = true end
    function methods:UnlockHighlight() self.highlightLocked = false end
    -- The pointer: a test sets w.mouseOver on the frames under it.
    function methods:IsMouseOver() return self.mouseOver == true end
    function methods:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[#self.points + 1] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
    end
    function methods:ClearAllPoints() self.points = {} end
    -- every point moved by (x, y) (SimpleScriptRegionResizingAPIDocumentation.lua:10-20)
    function methods:AdjustPointsOffset(x, y)
        for _, p in ipairs(self.points) do p.x, p.y = p.x + x, p.y + y end
    end
    function methods:SetSize(w, h) self.width, self.height = w, h end
    function methods:SetWidth(w) self.width = w end
    function methods:SetHeight(h) self.height = h end
    function methods:GetSize() return self.width, self.height end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    -- Visibility as the client keeps it: a frame is visible when it and every
    -- parent is shown, and OnShow / OnHide fire when that changes, for the
    -- frame and for each shown child under it. Children get theirs before
    -- the parent's own script runs, the worst order for a child that must not
    -- see OnShow (the client's real order is not established).
    local function visible(w)
        while w do
            if not w.shown then return false end
            w = w.parent
        end
        return true
    end
    local function cascade(w, script)
        for _, child in ipairs(w.children) do
            if child.shown then cascade(child, script) end
        end
        if w.scripts[script] then w.scripts[script](w) end
    end
    function methods:Show()
        if self.shown then return end
        self.shown = true
        if visible(self) then cascade(self, "OnShow") end
    end
    function methods:Hide()
        if not self.shown then return end
        local was = visible(self)
        self.shown = false
        if was then cascade(self, "OnHide") end
    end
    function methods:IsVisible() return visible(self) end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:IsShown() return self.shown end
    function methods:GetParent() return self.parent end
    -- A frame moved to another parent (nil: none) leaves the old one's children.
    function methods:SetParent(parent)
        if self.parent then
            for i, child in ipairs(self.parent.children) do
                if child == self then table.remove(self.parent.children, i) break end
            end
        end
        self.parent = parent
        if parent then parent.children[#parent.children + 1] = self end
    end
    -- A frame is one level above its parent until SetFrameLevel says otherwise.
    function methods:SetFrameLevel(level) self.level = level end
    function methods:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel() + 1 or 0) end
    function methods:IsObjectType(t)
        return t == self.kind or t == "Frame" or (t == "Button" and self.kind == "DropdownButton")
    end
    -- An edit box runs OnTextChanged(self, userInput) when its text changes;
    -- c.type is the player typing.
    function methods:SetText(text)
        local changed = self.text ~= text
        self.text = text
        if self.kind == "EditBox" and changed and self.scripts.OnTextChanged then
            self.scripts.OnTextChanged(self, false)
        end
    end
    function methods:SetFocus() self.focus = true end
    function methods:ClearFocus() self.focus = false end
    function methods:HasFocus() return self.focus == true end
    function methods:GetText() return self.text end
    -- a font string's text width: 6 for each character shown; a colour code
    -- draws nothing and a texture's markup (|T...|t) draws one 12 wide (slice E).
    -- In GameTooltipTextSmall, a 10 point font where the others are 12
    -- (Fonts.xml:1385-1387, 1403-1405), 5 for each.
    -- Characters, not bytes (i18n slice C): a UTF-8 character counts once
    -- (Latin and Cyrillic alike), a full-width one twice: CJK and Hangul,
    -- the three-byte characters led by E3 to ED (U+3000-U+DFFF) or EF
    -- (U+F000-U+FFFF, the full-width forms among them).
    local function perCharacter(w) return w.template == "GameTooltipTextSmall" and 5 or 6 end
    local function columns(text)
        local n = 0
        for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            local lead = ch:byte(1)
            n = n + ((#ch == 3 and ((lead >= 0xE3 and lead <= 0xED) or lead == 0xEF)) and 2 or 1)
        end
        return n
    end
    Fake.columns = columns
    local function shownColumns(text)
        return columns((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ".."))
    end
    -- i18n flags: a texture's markup draws as wide as it states
    -- (|Tpath:height:width|t), its height without a width, two characters'
    -- for a height of 0 (the text's, as before).
    local function textureWidths(text, per)
        local width = 0
        for spec in (text or ""):gmatch("|T(.-)|t") do
            local height, stated = spec:match("^[^:]*:(%d+):?(%d*)")
            stated = tonumber(stated) or tonumber(height) or 0
            width = width + (stated > 0 and stated or 2 * per)
        end
        return width
    end
    function methods:GetStringWidth()
        local per = perCharacter(self)
        return columns((self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) * per
            + textureWidths(self.text, per)
    end
    -- A button's text width (SimpleButtonAPIDocumentation.lua:244): its text
    -- by the same measure, 5 for each in GameFontHighlightSmall (10 point,
    -- Fonts.xml), else 6.
    function methods:GetTextWidth()
        local small = self.font and self.font.name == "GameFontHighlightSmall"
        return shownColumns(self.text) * (small and 5 or 6)
    end
    -- a font string's text height: a line's height for each line of its
    -- characters' width wrapped at its width (one line without a width),
    -- none for no text. A line is 10 in GameTooltipTextSmall, 12 in the
    -- others; a text with a CJK or Hangul character 1.25 times that (i18n
    -- slice D: the game's tooltip fonts take a taller member for those
    -- alphabets, 12 or 13 where the roman one is 10, Fonts.xml:1403-1420;
    -- the real pixel heights are unverified).
    local function lineHeight(w, text)
        local base = w.template == "GameTooltipTextSmall" and 10 or 12
        local wide = false
        for ch in text:gmatch("[\227-\237\239][\128-\191][\128-\191]") do wide = true break end
        return wide and base * 1.25 or base
    end
    Fake.lineHeight = lineHeight
    function methods:GetStringHeight()
        local text = self.text or ""
        local n = columns(text)
        if n == 0 then return 0 end
        local width = self.width
        return (width and width > 0 and math.ceil(n * perCharacter(self) / width) or 1) * lineHeight(self, text)
    end
    function methods:GetName() return self.name end
    function methods:SetEnabled(on) self.enabled = on and true or false end
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end
    function methods:IsEnabled() return self.enabled ~= false end
    -- SetTexture answers whether it took the file
    -- (SimpleTextureBaseAPIDocumentation.lua:604-619); missingFiles lists the
    -- paths it fails for. The call is kept as any other is.
    function methods:SetTexture(...)
        self.calls.SetTexture = { ... }
        self.callCount.SetTexture = (self.callCount.SetTexture or 0) + 1
        return not (opts.missingFiles and opts.missingFiles[(...)])
    end
    function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function methods:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function methods:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
    -- Keyboard input (SimpleFrameAPIDocumentation.lua:247-256, 1426-1435):
    -- SetPropagateKeyboardInput is restricted, recorded as misuse in combat.
    -- A frame passes no key on until told to (the client's default is
    -- inferred, the worst case for the fake).
    function methods:EnableKeyboard(on) self.keyboard = on and true or false end
    function methods:IsKeyboardEnabled() return self.keyboard == true end
    function methods:SetPropagateKeyboardInput(on)
        misuse(not c.combat, "SetPropagateKeyboardInput in combat")
        if c.combat then c.propagateInCombat = c.propagateInCombat + 1 end
        self.propagate = on and true or false
    end
    -- the draw layer, the template and the sublevel are kept on the region
    function methods:CreateTexture(name, layer, template, sublevel)
        local w = c.newWidget("Texture", name, self, template)
        w.layer, w.sublevel = layer, sublevel
        return w
    end
    function methods:CreateFontString(name, layer, template)
        local w = c.newWidget("FontString", name, self, template)
        w.layer = layer
        -- noStringHeight: the font strings have no GetStringHeight
        if opts.noStringHeight then w.GetStringHeight = false end
        return w
    end
    -- Masks (SimpleFrameAPIDocumentation.lua:113-127,
    -- SimpleTextureAPIDocumentation.lua:10): a texture keeps its masks in
    -- w.masks; noMaskAPI: neither call exists.
    function methods:CreateMaskTexture() return c.newWidget("MaskTexture", nil, self) end
    function methods:AddMaskTexture(mask)
        misuse(type(mask) == "table" and mask.kind == "MaskTexture", "AddMaskTexture argument")
        self.masks = self.masks or {}
        self.masks[#self.masks + 1] = mask
    end
    -- A button's font string (SimpleButtonAPIDocumentation): one, made on asking.
    function methods:GetFontString()
        if self.kind ~= "Button" then return nil end
        self.fontString = self.fontString or c.newWidget("FontString", nil, self)
        return self.fontString
    end
    -- ModelLight (SharedScriptObjectModelLightDocumentation.lua:6-17):
    -- every call is kept in c.lights; noSetLight: models have no SetLight.
    c.lights = {}
    function methods:SetLight(enabled, light)
        misuse(type(enabled) == "boolean" and type(light) == "table" and type(light.point) == "table"
            and type(light.ambientIntensity) == "number" and type(light.diffuseIntensity) == "number", "SetLight arguments")
        c.lights[#c.lights + 1] = { model = self, enabled = enabled, light = light }
    end
    -- SimpleButtonAPIDocumentation.lua:423-430: the argument is a font object.
    function methods:SetNormalFontObject(font)
        misuse(type(font) == "table", "SetNormalFontObject with " .. type(font))
        self.font = font
    end
    function methods:TryOn(source)
        misuse(type(source) == "number", "TryOn with " .. tostring(source))
        c.tryOn[#c.tryOn + 1] = { model = self, source = source }
        -- a piece replaces the one worn in its inventory slot
        self.worn = self.worn or {}
        self.worn[c.slotOfSource[source] or 0] = source
        return 0
    end
    -- DressUpModel:Undress takes off everything TryOn put on.
    function methods:Undress()
        self.worn = {}
        self.callCount.Undress = (self.callCount.Undress or 0) + 1
    end
    -- SimpleModelAPIDocumentation.lua:745-757; the fake's transform is the
    -- identity, so a test reads the camera-space position it was given.
    function methods:TransformCameraSpaceToModelSpace(v)
        misuse(type(v) == "table" and v.x and v.y and v.z, "TransformCameraSpaceToModelSpace argument")
        return { GetXYZ = function() return v.x, v.y, v.z end }
    end
    function methods:SetItemAppearance(appearanceID)
        misuse(type(appearanceID) == "number", "SetItemAppearance with " .. tostring(appearanceID))
        c.itemAppearances[#c.itemAppearances + 1] = { model = self, appearance = appearanceID }
    end
    local meta = { __index = function(w, key)
        if key == "GetOwner" and opts.noGetOwner then return nil end
        if key == "SetLight" and (opts.noSetLight or w.kind ~= "DressUpModel") then return nil end
        if (key == "CreateMaskTexture" or key == "AddMaskTexture") and opts.noMaskAPI then return nil end
        local method = methods[key]
        if method then
            return function(self, ...)
                traced(tostring(self.kind) .. ":" .. key)
                return method(self, ...)
            end
        end
        if type(key) == "string" and key:match("^[A-Z]") then
            return function(self, ...)
                traced(tostring(self.kind) .. ":" .. key)
                self.calls[key] = { ... }
                self.callCount[key] = (self.callCount[key] or 0) + 1
            end
        end
        return nil
    end }
    function c.newWidget(kind, name, parent, template)
        local w = setmetatable({ kind = kind, name = name, parent = parent, template = template, shown = true,
            events = {}, scripts = {}, points = {}, calls = {}, callCount = {}, children = {} }, meta)
        if parent then parent.children[#parent.children + 1] = w end
        c.widgets[#c.widgets + 1] = w
        if name then _G[name] = w end
        return w
    end
    function c.type(box, text)
        box.focus = true
        box.text = text
        if box.scripts.OnTextChanged then box.scripts.OnTextChanged(box, true) end
    end
    function c.fire(event, ...)
        local targets = {}
        for _, w in ipairs(c.widgets) do
            if w.events[event] and w.scripts.OnEvent then targets[#targets + 1] = w end
        end
        for _, w in ipairs(targets) do w.scripts.OnEvent(w, event, ...) end
        return #targets
    end

    -- Globals the existing files and the libraries read.
    TC, TC_ItemChecker, TransmogCheckerDB, AuctionHouseFrame, LibStub = nil, nil, nil, nil, nil
    -- The client's text language (the textLocale CVar): opts.locale, else
    -- enUS; a test changes c.locale.
    c.locale = opts.locale or "enUS"
    function GetLocale() return c.locale end
    -- The game's popups (Blizzard_StaticPopup/StaticPopup.lua:309): each
    -- shown one in c.popups as { which, dialog }; c.reloads counts ReloadUI.
    -- The button texts are made up for the fake (no GlobalStrings).
    c.popups, c.reloads = {}, 0
    StaticPopupDialogs = {}
    function StaticPopup_Show(which)
        c.popups[#c.popups + 1] = { which = which, dialog = StaticPopupDialogs[which] }
    end
    function ReloadUI() c.reloads = c.reloads + 1 end
    RELOADUI, LATER, ACCEPT, CANCEL = "Reload UI", "Later", "Accept", "Cancel"
    strmatch = string.match
    WOW_PROJECT_MAINLINE, WOW_PROJECT_CAMELOT = 1, 99
    WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
    SlashCmdList = {}
    Enum = {
        TooltipDataType = { Item = 0 },
        TransmogCollectionType = CATEGORIES,
        TransmogCollectionTypeMeta = { NumValues = 30 },
        TransmogType = { Appearance = 0 },
        TransmogModification = { Main = 0 },
        -- ItemConstantsDocumentation.lua:249-261, AuctionHouseEnumsDocumentation.lua:122-135
        ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4 },
        AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 },
        -- ItemConstantsDocumentation.lua:182-246, 269-296, 618-646
        ItemClass = { Weapon = 2, Armor = 4 },
        ItemArmorSubclass = { Generic = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Cosmetic = 5, Shield = 6 },
        ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6,
            Sword1H = 7, Sword2H = 8, Warglaive = 9, Staff = 10, Unarmed = 13, Generic = 14, Dagger = 15, Thrown = 16,
            Crossbow = 18, Wand = 19 },
        InventoryType = { IndexHeadType = 1, IndexShoulderType = 3, IndexBodyType = 4, IndexChestType = 5,
            IndexWaistType = 6, IndexLegsType = 7, IndexFeetType = 8, IndexWristType = 9, IndexHandType = 10,
            IndexWeaponType = 13, IndexShieldType = 14, IndexCloakType = 16, IndexTabardType = 19,
            IndexRobeType = 20, IndexHoldableType = 23 },
        -- AuctionHouseEnumsDocumentation.lua:25-51
        AuctionHouseError = { NotEnoughMoney = 0, HigherBid = 1, BidIncrement = 2, BidOwn = 3, ItemNotFound = 4,
            RestrictedAccountTrial = 5, HasRestriction = 6, IsBusy = 7, Unavailable = 8, ItemHasQuote = 9,
            DatabaseError = 10, MinBid = 11, NotEnoughItems = 12, RepairItem = 13, UsedCharges = 14, QuestItem = 15,
            BoundItem = 16, ConjuredItem = 17, LimitedDurationItem = 18, IsBag = 19, EquippedBag = 20,
            WrappedItem = 21, LootItem = 22, DoubleBid = 23, FavoritesMaxed = 24, ItemNotAvailable = 25,
            ItemBoundToAccountUntilEquip = 26 },
    }
    if opts.noScanEnums then Enum.ItemClass = nil end
    if opts.noAuctionErrors then Enum.AuctionHouseError = nil end
    -- a list of { enum, member } the client lacks
    for _, missing in ipairs(opts.noEnumMembers or {}) do Enum[missing[1]][missing[2]] = nil end
    -- A tooltip keeps its owner, anchor and lines: SetOwner starts it
    -- over; each line is { text, r, g, b, wrap, right, rr, rg, rb }. GetItem
    -- answers the item c.hoverItem showed in it.
    local function newTooltip(name)
        local t = c.newWidget("GameTooltip", name)
        t.lines = {}
        function t:SetOwner(owner, anchor)
            self.owner, self.anchor, self.lines, self.item = owner, anchor, {}, nil
            self.calls.SetOwner = { owner, anchor }
        end
        if not opts.noGetOwner then function t:GetOwner() return self.owner end end
        -- The left font string of line n, global <name>TextLeft<n> as the
        -- client names it: it reads and writes the tooltip's line n.
        local function defineLeft(tip, n)
            if not name then return end
            _G[name .. "TextLeft" .. n] = {
                GetText = function() return tip.lines[n] and tip.lines[n].text end,
                SetText = function(_, text) if tip.lines[n] then tip.lines[n].text = text end end,
                Hide = function() if tip.lines[n] then tip.lines[n].hidden = true end end,
            }
        end
        -- The right font string of line n, <name>TextRight<n>: shown with a
        -- double line, hidden with a single one. c.rightWriteFails: SetText
        -- changes nothing; c.noRightRegions: there is none.
        local function defineRight(tip, n)
            if not name then return end
            if c.noRightRegions then _G[name .. "TextRight" .. n] = nil return end
            _G[name .. "TextRight" .. n] = {
                GetText = function() return tip.lines[n] and tip.lines[n].right end,
                SetText = function(_, text)
                    if tip.lines[n] and not c.rightWriteFails then tip.lines[n].right = text end
                end,
                SetTextColor = function(_, r, g, b)
                    if tip.lines[n] then tip.lines[n].rr, tip.lines[n].rg, tip.lines[n].rb = r, g, b end
                end,
                Show = function() if tip.lines[n] then tip.lines[n].rightShown = true end end,
                Hide = function() if tip.lines[n] then tip.lines[n].rightShown = false end end,
                IsShown = function() return tip.lines[n] ~= nil and tip.lines[n].rightShown == true end,
            }
        end
        function t:AddLine(text, r, g, b, wrap, leftOffset)
            self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b, wrap = wrap, leftOffset = leftOffset }
            defineLeft(self, #self.lines)
            defineRight(self, #self.lines)
            self.calls.AddLine = { text, r, g, b, wrap }
        end
        function t:AddDoubleLine(text, right, r, g, b, rr, rg, rb, wrap, leftOffset)
            self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b, right = right, rr = rr, rg = rg, rb = rb,
                wrap = wrap, leftOffset = leftOffset, rightShown = true }
            defineLeft(self, #self.lines)
            defineRight(self, #self.lines)
        end
        function t:NumLines() return #self.lines end
        function t:GetItem()
            if self.item then return "Item", self.item end
        end
        -- TooltipDataHandlerMixin:GetPrimaryTooltipInfo (TooltipDataHandler.lua:393):
        -- the info c.hoverItem was given, such as { getterName = "GetBagItem" }
        function t:GetPrimaryTooltipInfo() return self.info end
        return t
    end
    GameTooltip = newTooltip("GameTooltip")
    -- another tooltip, such as ItemRefTooltip, made when a test asks
    c.newTooltip = newTooltip
    -- TooltipDataProcessor (TooltipDataProcessor.lua): the post-calls the
    -- addon registered, each { dataType, fn }. c.hoverItem(link, tooltip)
    -- shows the item in the tooltip (GameTooltip by default), as a bag
    -- button's OnEnter and every UpdateTooltip after it do, and runs the
    -- item post-calls; it answers the tooltip's lines as text.
    c.postCalls = {}
    TooltipDataProcessor = { AddTooltipPostCall = function(dataType, fn)
        c.postCalls[#c.postCalls + 1] = { dataType = dataType, fn = fn }
    end }
    -- info: the tooltip's primary info (a bag item's is { getterName = "GetBagItem" }).
    function c.hoverItem(link, tooltip, info)
        tooltip = tooltip or GameTooltip
        tooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
        tooltip.item, tooltip.info = link, info
        -- c.tooltipPre(tooltip): what Blizzard has put in the tooltip before the post-calls
        if c.tooltipPre then c.tooltipPre(tooltip) end
        for _, post in ipairs(c.postCalls) do
            if post.dataType == Enum.TooltipDataType.Item then post.fn(tooltip, { type = post.dataType }) end
        end
        local out = {}
        for i, line in ipairs(tooltip.lines) do out[i] = line.text end
        return out
    end
    -- the tooltip's lines as text, "left | right" for a double line
    function c.tooltipTexts()
        local out = {}
        for i, line in ipairs(GameTooltip.lines) do out[i] = line.right and (line.text .. " | " .. line.right) or line.text end
        return out
    end
    -- ColorMixin and Vector3D makers (Blizzard_SharedXMLBase/Color.lua:3,
    -- Blizzard_SharedXML/Vector3D.lua:93); noLightMakers: neither exists.
    if not opts.noLightMakers then
        function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        function CreateVector3D(x, y, z) return { x = x, y = y, z = z } end
    else
        CreateColor, CreateVector3D = nil, nil
    end
    -- GetFileIDFromPath: absent unless a test gives fileIDs ({ [path] = id
    -- or false }); a path not listed has none.
    GetFileIDFromPath = opts.fileIDs and function(path) return opts.fileIDs[path] or nil end or nil
    -- The client's strings the tile tooltip reads, in retail wording (made up
    -- for the fake: the clone has no GlobalStrings).
    TRANSMOG_SOURCE_1, TRANSMOG_SOURCE_2, TRANSMOG_SOURCE_3, TRANSMOG_SOURCE_4 = "Boss Drop", "Quest", "Vendor", "World Drop"
    TRANSMOG_SOURCE_6, TRANSMOG_SOURCE_BOSS_DROP = "Profession", 1
    TRANSMOG_COLLECTED, WARDROBE_OTHER_ITEMS = "Collected", "Other items using this appearance:"
    RETRIEVING_ITEM_INFO = "Retrieving item information"
    WARDROBE_TOOLTIP_ENCOUNTER_SOURCE, WARDROBE_TOOLTIP_BOSS_DROP_FORMAT = "%s (%s)", "Drop: %s"
    WARDROBE_TOOLTIP_BOSS_DROP_FORMAT_WITH_DIFFICULTIES = "Drop: %s (%s)"
    WARDROBE_TOOLTIP_CYCLE_ARROW_ICON, WARDROBE_TOOLTIP_CYCLE_SPACER_ICON = "> ", "  "
    TRANSMOG_APPEARANCE_USABLE_HOLIDAY = "Requires the holiday %s."
    TRANSMOG_SOURCE_5 = "Achievement"
    -- slot names by equip location (GlobalStrings, as Blizzard_EncounterJournal.lua:170-190 reads them)
    INVTYPE_HEAD, INVTYPE_FEET, INVTYPE_WAIST, INVTYPE_BODY, INVTYPE_CLOAK = "Head", "Feet", "Waist", "Shirt", "Back"
    INVTYPE_WEAPON, INVTYPE_SHIELD, INVTYPE_HOLDABLE, INVTYPE_RANGED = "One-Hand", "Off Hand", "Held In Off-hand", "Ranged"
    INVTYPE_RANGEDRIGHT, INVTYPE_CHEST = "Ranged", "Chest"
    UIParent = c.newWidget("Frame", "UIParent")
    GameFontNormal = not opts.noFontObjects and c.newWidget("Font", "GameFontNormal") or nil
    GameFontHighlightSmall = not opts.noFontObjects and c.newWidget("Font", "GameFontHighlightSmall") or nil
    GameFontDisableSmall = not opts.noFontObjects and c.newWidget("Font", "GameFontDisableSmall") or nil
    GameFontNormalMed3 = not opts.noFontObjects and c.newWidget("Font", "GameFontNormalMed3") or nil
    GameFontWhite = not opts.noFontObjects and c.newWidget("Font", "GameFontWhite") or nil
    -- the money display's fonts (GameFontStyles.xml:58-78)
    PriceFontWhite = not opts.noFontObjects and c.newWidget("Font", "PriceFontWhite") or nil
    PriceFontRed = not opts.noFontObjects and c.newWidget("Font", "PriceFontRed") or nil
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        c.printed[#c.printed + 1] = table.concat(parts, " ")
    end
    -- PlaySound (SoundDocumentation): recorded in c.sounds.
    c.sounds = {}
    function PlaySound(kit) c.sounds[#c.sounds + 1] = kit end
    -- The client's error handler records what it is given.
    c.errors = {}
    function geterrorhandler()
        return function(err) c.errors[#c.errors + 1] = tostring(err) end
    end
    function hooksecurefunc(object, name, hook)
        local original = object[name]
        object[name] = function(...)
            original(...)
            hook(...)
        end
    end
    -- SharedUIPanelTemplates.lua:477-509 with a made-up text width of 6 per
    -- letter (a full-width character two, Fake.columns) and 20 of padding;
    -- LibAHTab sizes its tab with them.
    function PanelTemplates_TabResize(tab, padding, absoluteSize, minWidth)
        tab.width = math.max(Fake.columns(tab.text or "") * 6 + 20 + (padding or 0), minWidth or 0)
    end
    function PanelTemplates_DeselectTab(tab) tab.selected = false end
    function PanelTemplates_SelectTab(tab) tab.selected = true end

    -- C_Texture.GetAtlasInfo (TextureUtilsDocumentation.lua:75-88): a table
    -- for an atlas the client has; noAtlases lists the ones it lacks (true:
    -- every one). c.atlasAsked records the names asked.
    c.atlasAsked = {}
    C_Texture = { GetAtlasInfo = function(atlas)
        misuse(type(atlas) == "string", "GetAtlasInfo with " .. type(atlas))
        c.atlasAsked[#c.atlasAsked + 1] = atlas
        local missing = opts.noAtlases == true or (type(opts.noAtlases) == "table" and opts.noAtlases[atlas])
        if missing then return nil end
        return { width = 32, height = 32, file = 1 }
    end }

    -- Blizzard_Menu's dropdowns (MenuTemplates.xml:3-39, 66-117) and the
    -- menu they open (DropdownButton.lua). A press runs the intrinsic
    -- OnMouseDown, which opens or closes the menu; opening runs the
    -- generator into a new root description. c.menu is the open menu:
    -- { owner, elements }, each element { kind = "radio" | "checkbox" |
    -- "button" | "title" | "divider", text, data, isSelected, setSelected, callback, enabled,
    -- elements }: a button with elements is a submenu
    -- (11_0_0_MenuImplementationGuide.lua:24-32), SetEnabled(false) greys an
    -- element (Menu.lua:830). c.choose picks an element as a click does, in
    -- the menu or a submenu: its responder runs, then every menu closes (a
    -- radio has no response of its own, MenuTemplates.lua:384-395,
    -- Menu.lua:2325-2350); a greyed element and a submenu's own button take
    -- no pick. noMenuTemplates: CreateFrame raises for both templates;
    -- noMenuAPI: the templates exist without SetupMenu and the text methods.
    local MENU_TEMPLATES = { WowStyle1DropdownTemplate = true, WowStyle1FilterDropdownTemplate = true }
    -- What the dropdown mixins define. A template frame has no catch-all for
    -- them: a name its template lacks is nil, as on the client.
    local MENU_API = { SetupMenu = true, CloseMenu = true, OpenMenu = true, IsMenuOpen = true,
        SetMenuOpen = true, GenerateMenu = true, SignalUpdate = true, OverrideText = true,
        SetDefaultText = true, GetMenuDescription = true }
    local dropdownMeta = { __index = function(w, key)
        if MENU_API[key] then return nil end
        return meta.__index(w, key)
    end }
    c.menuOpens = 0
    -- A menu callback that raises is recorded as misuse and raised again, as
    -- the client raises it.
    local function callback(fn, ...)
        local ok, result = pcall(fn, ...)
        if not ok then
            c.misuse[#c.misuse + 1] = "a menu callback raised: " .. tostring(result)
            error(result, 0)
        end
        return result
    end
    -- An element description: CreateRadio, CreateButton and CreateDivider
    -- add to it (MenuUtil.lua:209-230, 270) and answer the new element.
    local function newDescription(kind, text, data)
        local d = { kind = kind, text = text, data = data, elements = {} }
        function d:CreateRadio(radioText, isSelected, setSelected, radioData)
            misuse(type(isSelected) == "function" and type(setSelected) == "function", "CreateRadio arguments")
            local e = newDescription("radio", radioText, radioData)
            e.isSelected, e.setSelected = isSelected, setSelected
            self.elements[#self.elements + 1] = e
            return e
        end
        function d:CreateButton(buttonText, callback, buttonData)
            misuse(callback == nil or type(callback) == "function", "CreateButton callback")
            local e = newDescription("button", buttonText, buttonData)
            e.callback = callback
            self.elements[#self.elements + 1] = e
            return e
        end
        -- a checkbox keeps the menu open and asks isSelected again
        -- (MenuTemplates.lua:369-382, Menu.lua:2353-2360)
        function d:CreateCheckbox(boxText, isSelected, setSelected, boxData)
            misuse(type(isSelected) == "function" and type(setSelected) == "function", "CreateCheckbox arguments")
            local e = newDescription("checkbox", boxText, boxData)
            e.isSelected, e.setSelected = isSelected, setSelected
            self.elements[#self.elements + 1] = e
            return e
        end
        -- a title takes no pick (MenuTemplates.lua:294-303)
        function d:CreateTitle(titleText)
            local e = newDescription("title", titleText)
            self.elements[#self.elements + 1] = e
            return e
        end
        function d:CreateDivider() self.elements[#self.elements + 1] = { kind = "divider" } end
        function d:SetEnabled(on) self.enabled = on end
        return d
    end
    local function newDropdown(name, parent, template)
        local w = c.newWidget("DropdownButton", name, parent, template)
        setmetatable(w, dropdownMeta)
        local selectionText = template == "WowStyle1DropdownTemplate"
        w.intrinsic = "DropdownButton"
        -- the template's own size (Blizzard_Menu/Mainline/MenuTemplates.xml:4)
        if selectionText then w.width, w.height = 120, 25 end
        w.Text = w:CreateFontString()
        w.scripts.OnMouseDown = function(self) self:SetMenuOpen(not self:IsMenuOpen()) end
        -- the filter template's ButtonStateBehaviorMixin: its displaced
        -- regions move by (x, y) on a press and back on the release, the
        -- text by (2, -1) unless SetDisplacedRegions says otherwise
        -- (ButtonStateBehavior.lua:14-18, 59-92; MenuTemplates.lua:1019-1020)
        if template == "WowStyle1FilterDropdownTemplate" then
            w.displacedRegions, w.displaceX, w.displaceY = { w.Text }, 2, -1
            function w:SetDisplacedRegions(x, y, ...)
                self.displacedRegions, self.displaceX, self.displaceY = { ... }, x, y
            end
            local function displace(self, sign)
                if not self:IsEnabled() then return end
                for _, region in ipairs(self.displacedRegions) do
                    region:AdjustPointsOffset(sign * self.displaceX, sign * self.displaceY)
                end
            end
            local press = w.scripts.OnMouseDown
            w.scripts.OnMouseDown = function(self) press(self) displace(self, 1) end
            w.scripts.OnMouseUp = function(self) displace(self, -1) end
        end
        if opts.noMenuAPI then return w end
        -- DropdownTextMixin:SetText (MenuTemplates.lua:731-734); the filter
        -- template starts on FILTER and has its Background
        -- (MenuTemplates.xml:91)
        function w:SetText(text)
            self.text = text
            self.Text.text = text
        end
        if template == "WowStyle1FilterDropdownTemplate" then
            w:SetText("Filter")
            w.Background = w:CreateTexture()
        else
            -- DropdownSelectionTextMixin:OverrideText (MenuTemplates.lua:804-811):
            -- the text stays, whatever the selection
            function w:OverrideText(text)
                if not text then return end
                self.disableSelectionText = true
                self:SetText(text)
            end
        end
        -- DropdownButton.lua:255-264: the generator fills a new root
        -- description (a generator that raises is reported, not raised:
        -- securecallfunction), then SignalUpdate
        function w:GenerateMenu()
            if not self.menuGenerator then return end
            local root = newDescription("root")
            local ok, err = pcall(self.menuGenerator, self, root)
            if not ok then
                c.misuse[#c.misuse + 1] = "a menu generator raised: " .. tostring(err)
                geterrorhandler()(err)
            end
            self.menuRoot = root
            self:SignalUpdate()
        end
        -- DropdownButton.lua:279-288, 326-345 and DropdownSelectionTextMixin:
        -- UpdateToMenuSelections (MenuTemplates.lua:826-857): every radio's
        -- selected callback is evaluated; the selected radio's text becomes
        -- the text unless OverrideText was used
        function w:SignalUpdate()
            local text
            for _, e in ipairs(self.menuRoot and self.menuRoot.elements or {}) do
                if e.kind == "radio" and callback(e.isSelected, e.data) and text == nil then text = e.text end
            end
            if selectionText and not self.disableSelectionText then self:SetText(text or self.defaultText) end
        end
        -- DropdownButton.lua:246-248 (generated at once when shown) and
        -- DropdownSelectionTextMixin:OnShow (MenuTemplates.lua:869-873)
        function w:SetupMenu(generator)
            misuse(type(generator) == "function", "SetupMenu without a generator")
            self.menuGenerator = generator
            if self.shown then self:GenerateMenu() end
        end
        if selectionText then w.scripts.OnShow = function(self) self:GenerateMenu() end end
        function w:IsMenuOpen() return c.menu ~= nil and c.menu.owner == self end
        function w:OpenMenu()
            if not self:IsEnabled() or self:IsMenuOpen() or not self.menuGenerator then return end
            self:GenerateMenu()
            c.menu = { owner = self, elements = self.menuRoot.elements }
            c.menuOpens = c.menuOpens + 1
            -- DropdownButton.lua:128-129 and 85-88: the button is told, the
            -- menu already set or already cleared
            self:OnMenuOpened(c.menu)
        end
        -- DropdownButton.lua:132-139: closing signals an update
        function w:CloseMenu()
            local was = self:IsMenuOpen()
            if was then c.menu = nil end
            if was then self:OnMenuClosed() end
            self:SignalUpdate()
        end
        function w:SetMenuOpen(open) if open then self:OpenMenu() else self:CloseMenu() end end
        return w
    end
    -- The open menu's radios and checkboxes as { text, selected, enabled,
    -- checkbox }, titles as { text, title }, buttons as
    -- { text, enabled, submenu } (submenu: its entries, or nil), dividers
    -- as "-".
    local function entries(elements)
        local out = {}
        for _, e in ipairs(elements) do
            if e.kind == "divider" then
                out[#out + 1] = "-"
            elseif e.kind == "radio" or e.kind == "checkbox" then
                out[#out + 1] = { text = e.text, selected = callback(e.isSelected, e.data), enabled = e.enabled ~= false,
                    checkbox = e.kind == "checkbox" or nil }
            elseif e.kind == "title" then
                out[#out + 1] = { text = e.text, title = true }
            else
                out[#out + 1] = { text = e.text, enabled = e.enabled ~= false,
                    submenu = e.elements[1] and entries(e.elements) or nil }
            end
        end
        return out
    end
    function c.menuEntries() return entries(c.menu and c.menu.elements or {}) end
    local function pick(elements, text)
        for _, e in ipairs(elements) do
            if e.kind ~= "divider" and e.elements[1] then
                local found = pick(e.elements, text)
                if found ~= nil then return found end
            elseif e.text == text and e.kind ~= "divider" and e.kind ~= "title" then
                if e.enabled == false then return false end
                local fn = (e.kind == "radio" or e.kind == "checkbox") and e.setSelected or e.callback
                local response = fn and callback(fn, e.data, { context = 1, buttonName = "LeftButton" }, c.menu)
                misuse(response == nil, "a responder answered " .. tostring(response))
                -- a checkbox's Refresh: the menu stays open as built
                if e.kind == "checkbox" then return true end
                local owner = c.menu.owner
                c.menu = nil
                owner:OnMenuClosed()
                owner:SignalUpdate()
                return true
            end
        end
    end
    function c.choose(text)
        return pick(c.menu and c.menu.elements or {}, text) == true
    end

    function CreateFrame(kind, name, parent, template)
        if (opts.noButtonTemplate and template == "UIPanelButtonTemplate")
            or (template and opts.noTemplates and opts.noTemplates[template]) then
            error("fake: unknown template " .. template)
        end
        if MENU_TEMPLATES[template] then
            if opts.noMenuTemplates then error("fake: unknown template " .. template) end
            misuse(kind == "DropdownButton", "CreateFrame kind " .. tostring(kind) .. " for " .. template)
            return newDropdown(name, parent, template)
        end
        misuse(kind == "Frame" or kind == "Button" or kind == "DressUpModel" or kind == "EditBox",
            "CreateFrame kind " .. tostring(kind))
        local w = c.newWidget(kind, name, parent, template)
        -- CollectionsBackgroundTemplate's corners (SharedCollectionTemplates.xml:176-200)
        if template == "CollectionsBackgroundTemplate" then
            -- inherits InsetFrameTemplate with useParentLevel (SharedUIPanelTemplates.xml:389)
            w.level = parent:GetFrameLevel()
            for _, key in ipairs({ "BGCornerTopLeft", "BGCornerTopRight", "BGCornerBottomLeft", "BGCornerBottomRight" }) do
                w[key] = w:CreateTexture()
            end
        end
        -- MoneyDisplayFrameMixin:SetAmount (MoneyFrame.lua:557-572): the
        -- fake shows the amount as text in the item list's form ("1g 5c"),
        -- so a test reads the price the same way with or without it
        if template == "MoneyDisplayFrameTemplate" then
            w.SetAmount = function(self, copper)
                traced("MoneyDisplayFrame:SetAmount")
                misuse(type(copper) == "number", "SetAmount with " .. type(copper))
                self.amount = copper
                local words = {}
                local parts = { math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100 }
                for i, letter in ipairs({ "g", "s", "c" }) do
                    if parts[i] > 0 then words[#words + 1] = parts[i] .. letter end
                end
                self.text = table.concat(words, " ")
            end
            w.SetFontObject = function(self, font)
                traced("MoneyDisplayFrame:SetFontObject")
                self.font = font
            end
        end
        return w
    end
    function UnitClass(unit)
        misuse(unit == "player", "UnitClass unit")
        if opts.playerClass then return unpack(opts.playerClass) end
        return "Warlock", "WARLOCK", PLAYER_CLASS
    end
    -- The nine classes in the client's order, as the probe read them on
    -- 2026-11-25 (C_SpecializationInfo.GetAllClassIDs), and their info
    -- (CreatureInfoDocumentation.lua:127-135).
    local CLASSES = { [1] = { "Warrior", "WARRIOR" }, [2] = { "Paladin", "PALADIN" }, [3] = { "Hunter", "HUNTER" },
        [4] = { "Rogue", "ROGUE" }, [5] = { "Priest", "PRIEST" }, [7] = { "Shaman", "SHAMAN" },
        [8] = { "Mage", "MAGE" }, [9] = { "Warlock", "WARLOCK" }, [11] = { "Druid", "DRUID" } }
    Fake.CLASS_IDS = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }
    C_SpecializationInfo = not opts.noClassList and { GetAllClassIDs = function()
        local out = {}
        for i, id in ipairs(Fake.CLASS_IDS) do out[i] = id end
        return out
    end } or nil
    C_CreatureInfo = not opts.noClassList and { GetClassInfo = function(classID)
        local info = CLASSES[classID]
        return info and { className = info[1], classFile = info[2], classID = classID } or nil
    end } or nil
    -- ColorUtil.lua:66-73: r, g, b and the colour string; the fake's colours.
    function GetClassColor(classFile)
        return 1, 1, 1, "ff" .. (classFile or "none")
    end
    function Model_ApplyUICamera(model, cameraID)
        misuse(type(model) == "table" and type(cameraID) == "number", "Model_ApplyUICamera arguments")
        c.cameras[#c.cameras + 1] = cameraID
        -- the camera this model was last framed with
        model.uiCamera = cameraID
    end
    -- CameraDocumentation.lua:21-43: a position, a facing and an animation.
    function GetUICameraInfo(cameraID)
        misuse(type(cameraID) == "number", "GetUICameraInfo with " .. type(cameraID))
        return 1, 0, 0, 0, 0, 0, 0, 0, -1, false
    end

    -- The clock: GetTime, C_Timer.After and C_Timer.NewTicker run on it, and
    -- c.advance moves it, running every timer that falls due on the way.
    c.now = 1000
    local timers = {}
    local function after(delay, fn)
        local t = { at = c.now + delay, fn = fn }
        timers[#timers + 1] = t
        return t
    end
    c.after = after
    function c.advance(seconds)
        local stop = c.now + seconds
        while true do
            local due, index
            for i, t in ipairs(timers) do
                if t.at <= stop and (not due or t.at < due.at) then due, index = t, i end
            end
            if not due then break end
            table.remove(timers, index)
            c.now = math.max(c.now, due.at)
            if not due.cancelled then due.fn() end
        end
        c.now = stop
    end
    function c.pendingTimers()
        local n = 0
        for _, t in ipairs(timers) do if not t.cancelled then n = n + 1 end end
        return n
    end
    function GetTime() return c.now end
    -- C_Timer.After(0) runs on the next frame; c.frame() runs one frame.
    c.FRAME = 0.016
    function c.frame() c.advance(c.FRAME) end
    -- every ticker made, in order, with its interval (ticker.seconds)
    c.tickers = {}
    C_Timer = not opts.noTimer and {
        After = function(seconds, fn) after(seconds == 0 and c.FRAME or seconds, fn) end,
        NewTicker = function(seconds, fn, iterations)
            local ticker = { runs = 0 }
            local function tick()
                if ticker.cancelled then return end
                ticker.runs = ticker.runs + 1
                fn(ticker)
                if not ticker.cancelled and (not iterations or ticker.runs < iterations) then
                    ticker.timer = after(seconds, tick)
                end
            end
            ticker.timer = after(seconds, tick)
            ticker.seconds = seconds
            c.tickers[#c.tickers + 1] = ticker
            function ticker:Cancel()
                traced("ticker:Cancel")
                self.cancelled = true
                if self.timer then self.timer.cancelled = true end
            end
            return ticker
        end,
    } or nil

    -- Item data: what C_Item answers before and after an item loads.
    local itemDefs = opts.items or {}
    local itemLoaded = {}
    c.loadRequests = {}
    c.itemInfoCalls, c.transmogInfoCalls = 0, 0
    local function itemDef(itemID)
        return itemDefs[itemID] or { name = "Item " .. itemID, quality = 2, bindType = 2, subType = "Cloth",
            classID = 4, subClassID = 1 }
    end
    local function isLoaded(itemID)
        if itemLoaded[itemID] ~= nil then return itemLoaded[itemID] end
        return itemDef(itemID).load == nil
    end
    -- An item id, or an item link's ("|Hitem:<id>:...|h"), as the calls
    -- that take ItemInfo accept either; nil for anything else.
    local function idOf(item)
        if type(item) == "number" then return item end
        return type(item) == "string" and tonumber(item:match("item:(%d+)")) or nil
    end
    c.idOf = idOf
    C_Item = {
        -- ItemDocumentation.lua:659-679: itemID, itemType, itemSubType,
        -- itemEquipLoc, icon, classID, subClassID, without item data.
        GetItemInfoInstant = not opts.noItemInstant and function(item)
            local itemID = idOf(item)
            misuse(itemID ~= nil, "GetItemInfoInstant with " .. type(item))
            c.instantCalls = (c.instantCalls or 0) + 1
            local d = itemDef(itemID)
            if not d.classID then return nil end
            return itemID, "Armor", d.subType or "", d.equipLoc or "INVTYPE_FEET", 0, d.classID, d.subClassID
        end or nil,
        -- ItemDocumentation.lua:611-623: the item's icon file id, nilable;
        -- an item's icon (false: none), else 100000 + its id
        GetItemIconByID = function(item)
            local itemID = idOf(item)
            misuse(itemID ~= nil, "GetItemIconByID with " .. type(item))
            local icon = itemDef(itemID).icon
            if icon == false then return nil end
            return icon or 100000 + itemID
        end,
        -- c.qualityColorRaises: the next that many calls raise
        GetItemQualityColor = function(quality)
            misuse(type(quality) == "number", "GetItemQualityColor with " .. type(quality))
            if (c.qualityColorRaises or 0) > 0 then
                c.qualityColorRaises = c.qualityColorRaises - 1
                error("fake: GetItemQualityColor failed")
            end
            -- c.qualityColors: { [quality] = { r, g, b } } in place of white
            local color = c.qualityColors and c.qualityColors[quality]
            if color then return color[1], color[2], color[3], "ff000000" end
            return 1, 1, 1, "ffffffff"
        end,
        -- ItemDocumentation.lua:626-656: 1 name, 3 quality, 4 item level,
        -- 5 required level (minLevel, default 1), 7 subtype, 9 equip
        -- location (equipLoc, default INVTYPE_FEET), 14 bind type; nothing
        -- until the data has loaded.
        GetItemInfo = function(item)
            c.itemInfoCalls = c.itemInfoCalls + 1
            local itemID = idOf(item)
            if not itemID or not isLoaded(itemID) then return nil end
            local d = itemDef(itemID)
            return d.name, "link", d.quality, 1, d.minLevel == nil and 1 or d.minLevel, "Armor", d.subType, 1,
                d.equipLoc or "INVTYPE_FEET", 0, 0, d.classID or 4, d.subClassID or 1, d.bindType
        end,
        IsItemDataCachedByID = function(itemID) return isLoaded(itemID) end,
        -- ItemDocumentation.lua:1020-1036; the names are the fake's
        GetItemSubClassInfo = function(classID, subClassID)
            misuse(type(classID) == "number" and type(subClassID) == "number", "GetItemSubClassInfo arguments")
            return ("Subclass %d.%d"):format(classID, subClassID), false
        end,
        RequestLoadItemDataByID = function(itemID)
            misuse(type(itemID) == "number", "RequestLoadItemDataByID with " .. type(itemID))
            c.loadRequests[#c.loadRequests + 1] = itemID
            local load = itemDef(itemID).load
            if isLoaded(itemID) or load == "never" or c.loading[itemID] then return end
            c.loading[itemID] = true
            if load == "fail" then
                return after(0.1, function() c.fire("ITEM_DATA_LOAD_RESULT", itemID, false) end)
            end
            after(load, function()
                itemLoaded[itemID] = true
                c.fire("ITEM_DATA_LOAD_RESULT", itemID, true)
            end)
        end,
    }
    c.loading = {}

    -- The auction house. Every C_AuctionHouse access is recorded in
    -- auctionTouches. c.ah holds the fake server: listings (rows with name,
    -- itemID, itemLevel, itemSuffix, minPrice, totalQuantity) answer a name
    -- browse by case-insensitive substring, in pages of pageSize, answerDelay
    -- after the send; the throttle closes on every send and opens readyDelay
    -- later, with AUCTION_HOUSE_THROTTLED_SYSTEM_READY unless readyEvent is
    -- false. silent: no answer ever; fail: AUCTION_HOUSE_BROWSE_FAILURE
    -- instead of rows; neverReady: the throttle stays closed once closed.
    local ah = { ready = true, sends = {}, more = {}, listings = {}, keyNames = {}, pageSize = 500,
        answerDelay = 0.25, readyDelay = 0.3, readyEvent = true, keyInfoCalls = 0, keyAsked = {}, keyKnown = {}, keyCount = {},
        keyEvent = true, keyNever = {}, searches = {}, searchListings = {}, searchResults = {}, dropSearches = 0,
        searchRepeat = true, repeatDelay = 0.3, bids = {}, bidOutcome = "completed", bidError = 4 }
    c.ah = ah
    local function closeThrottle()
        ah.ready = false
        if ah.neverReady then return end
        after(ah.readyDelay, function()
            ah.ready = true
            if ah.readyEvent then c.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end
        end)
    end
    local function rowOf(l)
        return { itemKey = { itemID = l.itemID, itemLevel = l.itemLevel or 0, itemSuffix = l.itemSuffix or 0,
            battlePetSpeciesID = 0 }, minPrice = l.minPrice, totalQuantity = l.totalQuantity or 1,
            containsOwnerItem = false }
    end
    local function answer(event, payload)
        if ah.silent then return end
        after(ah.answerDelay, function()
            if ah.fail then return c.fire("AUCTION_HOUSE_BROWSE_FAILURE") end
            c.fire(event, payload)
        end)
    end
    local AH = {
        -- readyRaises: every call raises
        IsThrottledMessageSystemReady = function()
            if ah.readyRaises then error("fake: IsThrottledMessageSystemReady failed") end
            return ah.ready
        end,
        SendBrowseQuery = function(query)
            misuse(ah.ready or ah.sendingForeign, "SendBrowseQuery while the throttle is closed")
            ah.sends[#ah.sends + 1] = { query = query, at = c.now, foreign = ah.sendingForeign }
            closeThrottle()
            local text = (query.searchString or ""):lower()
            local pages, page = {}, nil
            for _, l in ipairs(ah.listings) do
                if l.name:lower():find(text, 1, true) then
                    if not page or #page >= ah.pageSize then page = {}; pages[#pages + 1] = page end
                    page[#page + 1] = rowOf(l)
                end
            end
            ah.pages, ah.delivered, ah.results = pages, 0, {}
            ah.delivered = 1
            for _, row in ipairs(pages[1] or {}) do ah.results[#ah.results + 1] = row end
            answer("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        end,
        RequestMoreBrowseResults = function()
            misuse(ah.ready, "RequestMoreBrowseResults while the throttle is closed")
            ah.more[#ah.more + 1] = c.now
            closeThrottle()
            ah.delivered = ah.delivered + 1
            local page = ah.pages[ah.delivered] or {}
            for _, row in ipairs(page) do ah.results[#ah.results + 1] = row end
            answer("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", page)
        end,
        GetBrowseResults = function() return ah.results or {} end,
        HasFullBrowseResults = function() return (ah.delivered or 0) >= #(ah.pages or {}) end,
        -- As the client does: the first call for a key answers nothing and
        -- ITEM_KEY_ITEM_INFO_RECEIVED fires 12 ms later (9 to 14 ms measured);
        -- from then on the call answers a table, with the name keyNames
        -- gives, if any. keyEvent false: the info arrives without the event
        -- (only polling sees it); keyNever[text]: the info never arrives.
        GetItemKeyInfo = function(itemKey)
            misuse(type(itemKey) == "table", "GetItemKeyInfo with " .. type(itemKey))
            ah.keyInfoCalls = ah.keyInfoCalls + 1
            local text = itemKey.itemID .. ":" .. itemKey.itemSuffix
            ah.keyCount[text] = (ah.keyCount[text] or 0) + 1
            if not ah.keyAsked[text] and not ah.keyNever[text] then
                ah.keyAsked[text] = true
                after(0.012, function()
                    ah.keyKnown[text] = true
                    if ah.keyEvent then c.fire("ITEM_KEY_ITEM_INFO_RECEIVED", itemKey.itemID) end
                end)
            end
            if not ah.keyKnown[text] then return nil end
            return { itemID = itemKey.itemID, itemName = ah.keyNames[text], quality = 2 }
        end,
        -- The search for one item variant (AuctionHouseDocumentation.lua:1031-1044).
        -- As the client does (spec 4.5): a send while the key's info is not
        -- there, or one of the first dropSearches sends, is dropped silently:
        -- the throttle stays open and no answer comes. Otherwise the throttle
        -- closes and ITEM_SEARCH_RESULTS_UPDATED(itemKey) comes answerDelay
        -- later, and again repeatDelay (0.3 s) after that unless searchRepeat
        -- is false.
        -- searchListings[text] are the results, ItemSearchResultInfo tables.
        SendSearchQuery = function(itemKey, sorts, separateOwnerItems)
            misuse(ah.ready, "SendSearchQuery while the throttle is closed")
            misuse(type(itemKey) == "table" and type(sorts) == "table" and type(separateOwnerItems) == "boolean",
                "SendSearchQuery arguments")
            local text = itemKey.itemID .. ":" .. itemKey.itemSuffix
            local record = { itemKey = itemKey, sorts = sorts, separate = separateOwnerItems, at = c.now }
            ah.searches[#ah.searches + 1] = record
            if not ah.keyKnown[text] or ah.dropSearches > 0 then
                ah.dropSearches = math.max(0, ah.dropSearches - 1)
                record.dropped = true
                return
            end
            closeThrottle()
            if ah.silent then return end
            local function deliver()
                local results = {}
                for i, r in ipairs(ah.searchListings[text] or {}) do
                    local copy = { itemKey = itemKey }
                    for k, v in pairs(r) do copy[k] = v end
                    results[i] = copy
                end
                ah.searchResults[text] = results
                c.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = itemKey.itemID, itemLevel = itemKey.itemLevel,
                    itemSuffix = itemKey.itemSuffix, battlePetSpeciesID = itemKey.battlePetSpeciesID })
            end
            after(ah.answerDelay, function()
                deliver()
                if ah.searchRepeat then after(ah.repeatDelay, deliver) end
            end)
        end,
        GetNumItemSearchResults = function(itemKey)
            misuse(type(itemKey) == "table", "GetNumItemSearchResults with " .. type(itemKey))
            return #(ah.searchResults[itemKey.itemID .. ":" .. itemKey.itemSuffix] or {})
        end,
        GetItemSearchResultInfo = function(itemKey, index)
            misuse(type(itemKey) == "table" and type(index) == "number", "GetItemSearchResultInfo arguments")
            return (ah.searchResults[itemKey.itemID .. ":" .. itemKey.itemSuffix] or {})[index]
        end,
        -- The buyout (AuctionHouseDocumentation.lua:852-862). Each call is
        -- recorded with whether it was made inside a click the fake started
        -- (c.click) and on which button. bidOutcome: "completed" (default)
        -- fires AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID) 0.2 s later,
        -- "error" AUCTION_HOUSE_SHOW_ERROR with the code bidError (default 4,
        -- ItemNotFound: the auction was sold), "other" a completion for
        -- another auction id, "silent" nothing.
        PlaceBid = function(auctionID, amount)
            misuse(type(auctionID) == "number" and type(amount) == "number", "PlaceBid arguments")
            ah.bids[#ah.bids + 1] = { auctionID = auctionID, amount = amount, inClick = c.clicking ~= nil,
                button = c.clicking, at = c.now, before = c.clicking and c.trace or nil }
            c.tracing = false
            -- bidRaises: this one call raises after it is recorded
            if ah.bidRaises then
                ah.bidRaises = nil
                error("fake: PlaceBid failed")
            end
            local outcome, code = ah.bidOutcome, ah.bidError
            after(0.2, function()
                if outcome == "completed" then
                    c.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
                elseif outcome == "error" then
                    c.fire("AUCTION_HOUSE_SHOW_ERROR", code)
                elseif outcome == "other" then
                    c.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID + 1)
                end
            end)
        end,
    }
    -- Another addon, or Blizzard's own code, sends a browse; it goes through
    -- whatever hooks are on C_AuctionHouse.SendBrowseQuery.
    function c.foreignBrowse(query)
        ah.sendingForeign = true
        C_AuctionHouse.SendBrowseQuery(query or { searchString = "", sorts = {}, filters = {} })
        ah.sendingForeign = nil
    end
    for _, name in ipairs(opts.noAuction or {}) do AH[name] = nil end
    C_AuctionHouse = not opts.noAuctionHouse and setmetatable({}, { __index = function(_, key)
        c.auctionTouches[#c.auctionTouches + 1] = key
        if key ~= "PlaceBid" then traced("C_AuctionHouse." .. tostring(key)) end
        return AH[key]
    end }) or nil

    -- The player's money in copper (PlayerScriptDocumentation.lua:642-649).
    c.money = 100 * 10000
    GetMoney = not opts.noMoney and function() return c.money end or nil

    -- A real click by the player: OnClick runs only on a shown, enabled
    -- button, and c.clicking names the button while it runs, so PlaceBid
    -- can tell a call made inside the click from any other.
    -- While the click runs, every global function the fake (or the addon)
    -- defined, pcall and xpcall, and every function of the TC modules are
    -- wrapped to record themselves in c.trace; the click restores them.
    local function wrapForClick()
        local wrapped = {}
        local function wrap(tbl, key, label)
            local fn = tbl[key]
            wrapped[#wrapped + 1] = { tbl, key, fn }
            tbl[key] = function(...)
                traced(label)
                return fn(...)
            end
        end
        local globals = {}
        for name, v in pairs(_G) do
            if type(name) == "string" and type(v) == "function"
                and (STANDARD[name] ~= v or name == "pcall" or name == "xpcall") then
                globals[#globals + 1] = name
            end
        end
        for _, name in ipairs(globals) do wrap(_G, name, name) end
        local modules = {}
        for moduleName, module in pairs(type(TC) == "table" and TC or {}) do
            if type(module) == "table" then
                for key, v in pairs(module) do
                    if type(v) == "function" then modules[#modules + 1] = { module, key, "TC." .. moduleName .. "." .. key } end
                end
            end
        end
        for _, m in ipairs(modules) do wrap(m[1], m[2], m[3]) end
        return function()
            for i = #wrapped, 1, -1 do
                local w = wrapped[i]
                w[1][w[2]] = w[3]
            end
        end
    end
    function c.click(button, mouse)
        if not (button and visible(button) and button:IsEnabled() and button.scripts.OnClick) then return false end
        c.clicking, c.trace, c.tracing = button, {}, true
        local unwrap = wrapForClick()
        local ok, err = rawPcall(button.scripts.OnClick, button, mouse or "LeftButton", false)
        unwrap()
        c.clicking, c.tracing = nil, false
        if not ok then error(err, 0) end
        return true
    end

    -- Escape (Blizzard_GameMenuEsc.lua:76-113): handlers in priority order,
    -- the first that answers true takes it; otherwise CloseAllWindows
    -- (AddOnPost, UIParentPanelManager.lua:1190) closes the auction window.
    GameMenuEscPriority = { Dialog = 1, Menu = 2, AddOn = 8, AddOnPost = 9 }
    c.escHandlers = {}
    RegisterGameMenuEscHandler = not opts.noEscHandlers and function(priority, handler)
        misuse(type(priority) == "number" and type(handler) == "function", "RegisterGameMenuEscHandler arguments")
        c.escHandlers[#c.escHandlers + 1] = { priority = priority, handler = handler }
        table.sort(c.escHandlers, function(a, b) return a.priority < b.priority end)
    end or nil
    function c.escape()
        for _, entry in ipairs(c.escHandlers) do
            if entry.handler() then return "handled" end
        end
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() then c.closeAuction() end
        return "closed windows"
    end

    -- A key press by the player: the last made shown frame with keyboard
    -- enabled and an OnKeyDown script gets it first; when no frame takes it,
    -- or that frame passes it on, the game's own handling follows (Escape:
    -- c.escape). c.keys records each press: { key, frame, passed }.
    -- c.combat is InCombatLockdown's answer; c.enterCombat and c.leaveCombat
    -- change it and fire PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED.
    -- c.kept records each key a frame kept: { key, frame }; record.kept says
    -- it for one press. c.propagateInCombat counts SetPropagateKeyboardInput
    -- calls made in combat.
    c.keys, c.kept, c.propagateInCombat = {}, {}, 0
    function InCombatLockdown() return c.combat == true end
    function c.enterCombat()
        c.combat = true
        c.fire("PLAYER_REGEN_DISABLED")
    end
    function c.leaveCombat()
        c.combat = false
        c.fire("PLAYER_REGEN_ENABLED")
    end
    function c.key(key)
        local target
        for _, w in ipairs(c.widgets) do
            if w.keyboard and w.scripts.OnKeyDown and visible(w) then target = w end
        end
        local record = { key = key, frame = target }
        c.keys[#c.keys + 1] = record
        if target then target.scripts.OnKeyDown(target, key) end
        record.passed = not target or target.propagate == true
        record.kept = not record.passed
        if record.kept then c.kept[#c.kept + 1] = { key = key, frame = target } end
        if record.passed and key == "ESCAPE" then c.escape() end
        return record
    end

    if not opts.noCompare then
        CollectionWardrobeUtil = {
            -- This client's comparator, copied from
            -- Blizzard_FrameXMLUtil/Camelot/CollectionsUtilOverrides.lua:1-27.
            CompareAppearance = function(source1, source2)
                if source1.isCollected ~= source2.isCollected then return source1.isCollected end
                if source1.isUsable ~= source2.isUsable then return source1.isUsable end
                if source1.isFavorite ~= source2.isFavorite then return source1.isFavorite end
                if source1.canDisplayOnPlayer ~= source2.canDisplayOnPlayer then return source1.canDisplayOnPlayer end
                if source1.isHideVisual ~= source2.isHideVisual then return source1.isHideVisual end
                if source1.hasActiveRequiredHoliday ~= source2.hasActiveRequiredHoliday then
                    return source1.hasActiveRequiredHoliday
                end
                if source1.minIlvl and source2.minIlvl then return source1.minIlvl < source2.minIlvl end
                if source1.uiOrder and source2.uiOrder then return source1.uiOrder > source2.uiOrder end
                return source1.sourceID > source2.sourceID
            end,
            -- Not Blizzard's: highest source id first, enough to tell the
            -- sorted list from the one the client gives. realSortSources:
            -- Blizzard's, copied from Blizzard_FrameXMLUtil/CollectionsUtil.lua:43-76
            -- without a primary visual or source.
            SortSources = not opts.noSortSources and function(sources)
                table.sort(sources, opts.realSortSources and function(s1, s2)
                    if s1.isCollected ~= s2.isCollected then return s1.isCollected end
                    if s1.isValidSourceForPlayer ~= s2.isValidSourceForPlayer then return s1.isValidSourceForPlayer end
                    if s1.quality and s2.quality then
                        if s1.quality ~= s2.quality then return s1.quality > s2.quality end
                    else
                        return s1.quality
                    end
                    return s1.sourceID > s2.sourceID
                end or function(a, b) return a.sourceID > b.sourceID end)
                return sources
            end or nil,
        }
    else
        CollectionWardrobeUtil = nil
    end

    -- Fake.forbiddenTotal counts the forbidden calls of every client made.
    local function forbid(name)
        return function()
            c.forbidden[#c.forbidden + 1] = name
            Fake.forbiddenTotal = (Fake.forbiddenTotal or 0) + 1
        end
    end
    local col = c.collections
    -- the class filter before the latest write, while that write is in this
    -- frame: what GetCategoryInfo answers by under lagByOne
    local lagged
    -- the search-and-filter category list reads are narrowed by (filterLag)
    local applied = col.filterCategory
    local function narrowedOut(a)
        if a.hide then return false end
        local isCollected = a.collectedSource ~= nil
        return a.filteredOut or (isCollected and not col.collectedShown) or (not isCollected and not col.uncollectedShown)
    end
    local T = {
        GetCategoryAppearances = function(category, location)
            c.listCalls = c.listCalls + 1
            c.listed[#c.listed + 1] = { category = category, slotID = type(location) == "table" and location.slotID }
            misuse(SLOT_OF_CATEGORY[category] ~= nil, "GetCategoryAppearances category " .. tostring(category))
            misuse(type(location) == "table" and location.slotID == SLOT_OF_CATEGORY[category] and location.type == 0
                and location.modification == 0, "GetCategoryAppearances location for " .. tostring(category))
            if (opts.listRaisesOn or {})[c.listCalls] then error("fake: GetCategoryAppearances failed") end
            if opts.listRaisesAway and applied == 29 then error("fake: GetCategoryAppearances failed pointed away") end
            if opts.listRaisesFor == category then error("fake: GetCategoryAppearances failed for " .. category) end
            if opts.listRaises == true or (tonumber(opts.listRaises) or 0) >= c.listCalls then
                error("fake: GetCategoryAppearances failed")
            end
            if opts.listNil then return nil end
            if (opts.listEmpty or 0) >= c.listCalls then return {} end
            local result = {}
            -- the client's own order is by id, descending: not Collections' order
            for i = #appearances, 1, -1 do
                local a = appearances[i]
                if a.category == category and not a.unlisted and not (category == applied and narrowedOut(a)) then
                    -- the fields of TransmogCategoryAppearanceInfo
                    -- (TransmogItemsDocumentation.lua:1190-1207)
                    result[#result + 1] = { visualID = a.id, uiOrder = a.uiOrder, minIlvl = a.minIlvl,
                        isHideVisual = a.hide or false, isCollected = a.collectedSource ~= nil, isUsable = true,
                        isFavorite = false, canDisplayOnPlayer = true, exclusions = 0, hasRequiredHoliday = false,
                        hasActiveRequiredHoliday = false, isValidForEquippedItem = false }
                end
            end
            return result
        end,
        -- TransmogItemsDocumentation.lua:317-330: every appearance of the
        -- category, hidden visuals too, under no filter (in game: feet 371
        -- of 371 entries, head 245 while its list had 1). While listNil or
        -- listEmpty makes the list answer nothing, the total is 0 too: a
        -- category the client has not loaded (assumed, unverified in game).
        GetCategoryTotal = function(category)
            if opts.totalRaises then error("fake: GetCategoryTotal failed") end
            if opts.listNil or (opts.listEmpty or 0) >= c.listCalls then return 0 end
            local n = 0
            for _, a in ipairs(appearances) do
                if a.category == category then n = n + 1 end
            end
            return n
        end,
        -- TransmogItemsDocumentation.lua:432-445; Collections' progress bar
        -- (Blizzard_Wardrobe.lua:1189-1190). In game: head 1 of 245 while
        -- the filter category was Head, feet 371 of 371.
        GetFilteredCategoryTotal = function(category)
            if opts.listNil or (opts.listEmpty or 0) >= c.listCalls then return 0 end
            local n = 0
            for _, a in ipairs(appearances) do
                if a.category == category and not (category == applied and narrowedOut(a)) then n = n + 1 end
            end
            return n
        end,
        -- TransmogItemsDocumentation.lua:1085-1093
        SetSearchAndFilterCategory = function(category)
            misuse(type(category) == "number", "SetSearchAndFilterCategory with " .. type(category))
            c.categorySetCalls = (c.categorySetCalls or 0) + 1
            if (opts.categoryRaisesOn or {})[c.categorySetCalls] then error("fake: SetSearchAndFilterCategory failed") end
            c.writes[#c.writes + 1] = { kind = "category", value = category, at = c.now }
            col.filterCategory = category
            if opts.filterLag == "frame" then
                after(c.FRAME, function() applied = col.filterCategory end)
            elseif opts.filterLag ~= "never" then
                applied = category
            end
            if opts.filterCategoryFires then c.fire("TRANSMOG_COLLECTION_UPDATED") end
        end,
        GetAllAppearanceSources = function(id)
            local a = byID[id]
            if not a then return nil end
            local copy = {}
            for i, s in ipairs(a.sources) do copy[i] = s end
            return copy
        end,
        GetAppearanceSources = function(id, category, location)
            local a = byID[id]
            misuse(a and category == a.category and type(location) == "table"
                and location.slotID == SLOT_OF_CATEGORY[category], "GetAppearanceSources arguments")
            if not a or opts.sourcesNil then return nil end
            c.sourcesCalls = (c.sourcesCalls or 0) + 1
            -- AppearanceSourceInfo (AppearanceSourceDocumentation.lua:6-30):
            -- the item's name and quality only once its data is in; the
            -- source type from the fixture's sourceTypes (default 4)
            local infos = {}
            for i, s in ipairs(a.sources) do
                local itemID = (opts.sourceItems or {})[s] or s
                local loaded = isLoaded(itemID)
                infos[i] = { sourceID = s, visualID = id, itemID = itemID, isCollected = collectedSources[s] == true,
                    sourceType = a.sourceTypes and a.sourceTypes[i] or 4, isValidSourceForPlayer = true,
                    name = loaded and itemDef(itemID).name or nil, quality = loaded and itemDef(itemID).quality or nil,
                    useError = (opts.useErrors or {})[s] }
            end
            return infos
        end,
        -- TransmogItemsDocumentation: a boss drop's encounters, from opts.drops[sourceID]
        GetAppearanceSourceDrops = function(sourceID) return (opts.drops or {})[sourceID] end,
        -- TransmogItemsDocumentation.lua:647-661: the holiday's name or
        -- nothing, from opts.holidays; holidayRaises: it raises
        GetSourceRequiredHoliday = function(sourceID)
            misuse(type(sourceID) == "number", "GetSourceRequiredHoliday with " .. type(sourceID))
            if opts.holidayRaises then error("fake: GetSourceRequiredHoliday failed") end
            return (opts.holidays or {})[sourceID]
        end,
        PlayerHasTransmogItemModifiedAppearance = function(sourceID)
            -- c.collectedRaises: it raises (a test sets and clears it)
            if c.collectedRaises then error("fake: PlayerHasTransmogItemModifiedAppearance failed") end
            return collectedSources[sourceID] == true
        end,
        -- AppearanceSourceInfo (AppearanceSourceDocumentation.lua:6-30), the
        -- fields the browser reads.
        GetSourceInfo = function(sourceID)
            misuse(type(sourceID) == "number", "GetSourceInfo with " .. type(sourceID))
            if opts.sourceInfoNil then return nil end
            return { sourceID = sourceID, itemID = (opts.sourceItems or {})[sourceID] or sourceID, sourceType = 1,
                categoryID = c.categoryOfSource[sourceID] or CATEGORIES.None }
        end,
        -- TransmogItemsDocumentation.lua:521-536: an item's appearance and
        -- source, or nothing; by the fixture's sources (sourceItems).
        GetItemInfo = function(item)
            local itemID = idOf(item)
            misuse(itemID ~= nil, "C_TransmogCollection.GetItemInfo with " .. type(item))
            c.transmogInfoCalls = c.transmogInfoCalls + 1
            for _, a in ipairs(appearances) do
                for _, s in ipairs(a.sources) do
                    if ((opts.sourceItems or {})[s] or s) == itemID then return a.id, s end
                end
            end
        end,
        GetAppearanceCameraID = function() return 486 end,
        -- TransmogItemsDocumentation.lua:296-315: name, isWeapon,
        -- canHaveIllusions, canMainHand, canOffHand, canRanged, or nothing.
        GetCategoryInfo = function(category)
            misuse(type(category) == "number", "GetCategoryInfo with " .. type(category))
            c.categoryInfoCalls = c.categoryInfoCalls + 1
            if opts.noCategoryInfo then return nil end
            local info = opts.categoryInfo and opts.categoryInfo[category]
            if info then return unpack(info) end
            local class = lagged or col.classFilter
            local has = WEAPON_CATEGORIES_OF_CLASS[class]
            if opts.classCategories and opts.classCategories[class] then
                has = {}
                for _, n in ipairs(opts.classCategories[class]) do has[n] = true end
            end
            if opts.categoryInfo or not (has and has[category]) then return nil end
            local slotID = SLOT_OF_CATEGORY[category]
            return CATEGORY_NAMES[category], true, false, slotID == 16, slotID == 17, slotID == 18
        end,
        GetClassFilter = function()
            if opts.getClassFilterRaises then error("fake: GetClassFilter failed") end
            return col.classFilter
        end,
        SetClassFilter = function(classID)
            c.setClassCalls = (c.setClassCalls or 0) + 1
            c.writes[#c.writes + 1] = { kind = "class", value = classID, at = c.now }
            if opts.setClassIgnoredFor == classID then return end
            for _, n in ipairs(opts.setClassIgnoredAt or {}) do
                if n == c.setClassCalls then return end
            end
            -- a read in this frame answers for the class set one write earlier
            if opts.lagByOne then
                lagged = col.classFilter
                after(c.FRAME, function() lagged = nil end)
            end
            col.classFilter = classID
            if opts.setClassFires then c.fire("TRANSMOG_COLLECTION_UPDATED") end
            if opts.setClassRaises or opts.setClassRaisesFor == classID then error("fake: SetClassFilter failed") end
        end,
        GetUncollectedShown = function() return col.uncollectedShown end,
        SetUncollectedShown = function(v) col.uncollectedShown = v end,
        GetCollectedShown = function() return col.collectedShown end,
        SetCollectedShown = function(v) col.collectedShown = v end,
        SetSearch = function(_, text) col.search = text end,
        ClearSearch = function() col.search = "" end,
        GetAppearanceInfoBySource = forbid("GetAppearanceInfoBySource"),
        AccountCanCollectSource = forbid("AccountCanCollectSource"),
        PlayerCanCollectSource = forbid("PlayerCanCollectSource"),
        PlayerHasTransmog = forbid("PlayerHasTransmog"),
    }
    if opts.noList then T.GetCategoryAppearances = nil end
    if opts.noFilterCategorySet then T.SetSearchAndFilterCategory = nil end
    if opts.noCategoryTotal then T.GetCategoryTotal = nil end
    if opts.noFilteredTotal then T.GetFilteredCategoryTotal = nil end
    if opts.noItemTransmog then T.GetItemInfo = nil end
    C_TransmogCollection = not opts.noTransmog and T or nil
    -- ContainerDocumentation.lua:175-190, 313-325: the player's bags,
    -- c.bags[bag] = { itemID or false per slot } (a test may change it; the
    -- backpack has 16 empty slots by default); c.bagReads counts
    -- GetContainerNumSlots calls. noContainer: C_Container is nil.
    c.bags, c.bagReads = opts.bags or { [0] = { false, false, false, false, false, false, false, false,
        false, false, false, false, false, false, false, false } }, 0
    Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 }
    NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5
    C_Container = not opts.noContainer and {
        GetContainerNumSlots = function(bag)
            misuse(type(bag) == "number", "GetContainerNumSlots with " .. type(bag))
            c.bagReads = c.bagReads + 1
            return #(c.bags[bag] or {})
        end,
        GetContainerItemID = function(bag, slot)
            misuse(type(bag) == "number" and type(slot) == "number", "GetContainerItemID with " .. type(bag))
            local id = (c.bags[bag] or {})[slot]
            return id or nil
        end,
    } or nil
    -- TransmogSetsDocumentation.lua:167-181, 215-229, 520-540: the sets of
    -- a source (opts.sets, { [sourceID] = { setID } }) and a set's info
    -- (opts.setInfo, { [setID] = { name, label } }); noSets: no C_TransmogSets.
    C_TransmogSets = not opts.noSets and {
        GetSetsContainingSourceID = function(sourceID)
            misuse(type(sourceID) == "number", "GetSetsContainingSourceID with " .. type(sourceID))
            return (opts.sets or {})[sourceID]
        end,
        GetSetInfo = function(setID)
            misuse(type(setID) == "number", "GetSetInfo with " .. type(setID))
            return (opts.setInfo or {})[setID]
        end,
    } or nil

    -- What Blizzard's AUCTION_HOUSE_SHOW handler does before an addon's runs:
    -- load Blizzard_AuctionHouseUI, which makes the frame with its three tabs.
    function c.loadAuctionUI()
        if AuctionHouseFrame then return end
        local frame = c.newWidget("Frame", "AuctionHouseFrame")
        frame.width, frame.height = 800, 538
        frame.Tabs = {}
        for i = 1, 3 do
            frame.Tabs[i] = c.newWidget("Button", "AuctionHouseFrameTab" .. i, frame)
            frame.Tabs[i].blizzard = true
        end
        frame.displayMode = { "BuyTab" }
        function frame:SetDisplayMode(mode) self.displayMode = mode end
        function frame:SetTitle(title) self.title = title end
        frame.shown = false
        -- AuctionHouseFrameMixin:OnShow puts the window on Buy
        -- (Blizzard_AuctionHouseFrame.lua:389-394).
        frame.scripts.OnShow = function(self) self:SetDisplayMode({ "BuyTab" }) end
    end

    -- The auction window opening and closing: Blizzard's handlers show and
    -- hide the frame (GameEvent.HandleAuctionHouseShow / Closed,
    -- Blizzard_Game/Mainline/EventImplementation.lua:454-465) before an
    -- addon's handler runs (the order is assumed).
    function c.openAuction()
        c.loadAuctionUI()
        AuctionHouseFrame:Show()
        c.fire("AUCTION_HOUSE_SHOW")
    end
    function c.closeAuction()
        AuctionHouseFrame:Hide()
        c.fire("AUCTION_HOUSE_CLOSED")
    end

    -- The client's settings API (Blizzard_Settings_Shared), only with
    -- opts.settings: Settings.RegisterVerticalLayoutCategory(name) answers a
    -- category and its layout (Blizzard_Settings.lua:154-156, Blizzard_
    -- SettingsInbound.lua:176-180), RegisterAddOnCategory puts it on the
    -- AddOns tab (:134-138), RegisterProxySetting(category, variable,
    -- variableType, name, defaultValue, getValue, setValue) (:178-180) makes
    -- a setting whose value is getValue's answer (Blizzard_Setting.lua:326-
    -- 360): SetValue is ignored while locked, writes through setValue only
    -- when the value differs, locked meanwhile, then tells the variable's
    -- listeners (:100-137, 261-263); SetValueToDefault applies the default
    -- (:139-148), NotifyUpdate tells the listeners the current value
    -- (:185-188). CreateCheckbox (only a boolean setting, Blizzard_
    -- Settings.lua:364-367), CreateDropdown (options required, :374-377) and
    -- the section header (Blizzard_SettingControls.lua:131-134) are
    -- initializers added to the layout; CreatePanelInitializer(template,
    -- data) (:355-357) is one the caller adds, whose frame is made from a
    -- template or, for a name that is no template, a native frame type
    -- (FrameFactory.lua:12-27). An initializer's modify predicates
    -- (Blizzard_SettingControls.lua:139-177) decide whether its row is
    -- enabled. OpenToCategory(id, element) (Blizzard_Settings.lua:144-146) is
    -- C_SettingsUtil.OpenSettingsPanel, restricted (SettingsUtilDocumentation
    -- .lua:15-17): from addon code in combat ShowUIPanel refuses it
    -- (UIParentPanelManager.lua:854-861, 886-888), counted in
    -- c.settings.blocked. c.settings.notified counts each variable's
    -- value-changed signals (what a shown control redraws on).
    c.settings = { categories = {}, addon = {}, opened = {}, blocked = 0, notified = {}, byVariable = {}, frames = {} }
    Settings, CreateSettingsListSectionHeaderInitializer, TransmogChecker_OpenSettings = nil, nil, nil
    if opts.settings then
        local listeners = {}
        local function trigger(setting, value)
            local variable = setting:GetVariable()
            c.settings.notified[variable] = (c.settings.notified[variable] or 0) + 1
            for _, fn in ipairs(listeners[variable] or {}) do fn(setting, value) end
        end
        local function listen(variable, fn)
            listeners[variable] = listeners[variable] or {}
            table.insert(listeners[variable], fn)
        end
        local function newInitializer(kind, template, data)
            local init = { kind = kind, frameTemplate = template, data = data or {} }
            function init:AddModifyPredicate(fn) self.modify = self.modify or {} table.insert(self.modify, fn) end
            function init:SetParentInitializer(parent, predicate)
                misuse(parent ~= nil and parent ~= self, "SetParentInitializer argument")
                self.parent = parent
                if predicate then self:AddModifyPredicate(predicate) end
            end
            function init:EvaluateModifyPredicates()
                for _, fn in ipairs(self.modify or {}) do if not fn() then return false end end
                return true
            end
            function init:AddEvaluateStateCVar(variable) self.evaluateOn = self.evaluateOn or {} table.insert(self.evaluateOn, variable) end
            function init:GetExtent() return nil end
            function init:InitFrame(frame) if frame.Init then frame:Init(self) end end
            function init:Resetter(frame) if frame.Release then frame:Release(self) end end
            function init:GetSetting() return self.data.setting end
            -- the list reads these fields in its own code (Blizzard_SettingsList
            -- .lua:57-71): one the addon wrote is misuse (c.settingsPage checks)
            init.own = { GetExtent = init.GetExtent, InitFrame = init.InitFrame, Resetter = init.Resetter }
            return init
        end
        Settings = { VarType = { Boolean = "boolean", String = "string", Number = "number" }, Default = { True = true, False = false } }
        function Settings.RegisterVerticalLayoutCategory(name)
            local category = { name = name, ID = 100 + #c.settings.categories, settings = {} }
            function category:GetID() return self.ID end
            local layout = { initializers = {} }
            function layout:AddInitializer(init) table.insert(self.initializers, init) return init end
            category.layout = layout
            table.insert(c.settings.categories, category)
            return category, layout
        end
        function Settings.RegisterAddOnCategory(category) table.insert(c.settings.addon, category) end
        function Settings.RegisterProxySetting(category, variable, variableType, name, defaultValue, getValue, setValue)
            misuse(type(variable) == "string" and type(name) == "string" and type(getValue) == "function"
                and type(setValue) == "function", "RegisterProxySetting arguments")
            misuse(type(defaultValue) == variableType, "RegisterProxySetting default for " .. tostring(variable))
            misuse(c.settings.byVariable[variable] == nil, "a second setting " .. tostring(variable))
            local s = { variable = variable, name = name, variableType = variableType, default = defaultValue }
            function s:GetVariable() return self.variable end
            function s:GetName() return self.name end
            function s:GetVariableType() return self.variableType end
            function s:GetDefaultValue() return self.default end
            function s:IsLocked() return self.locked end
            function s:GetValue() return getValue() end
            function s:ApplyValue(value)
                if getValue() ~= value then
                    misuse(type(value) == self.variableType, "a " .. type(value) .. " value for " .. variable)
                    self.locked = true
                    setValue(value)
                    self.locked = false
                end
                trigger(self, value)
            end
            function s:SetValue(value) if not self.locked then self:ApplyValue(value) end end
            function s:SetValueToDefault() self:ApplyValue(self.default) return true end
            function s:NotifyUpdate() trigger(self, getValue()) end
            function s:SetValueChangedCallback(fn) listen(variable, fn) end
            c.settings.byVariable[variable] = s
            table.insert(category.settings, s)
            return s
        end
        function Settings.GetSetting(variable) return c.settings.byVariable[variable] end
        function Settings.CreateControlTextContainer()
            local container = { data = {} }
            function container:Add(value, label, tooltip)
                table.insert(self.data, { value = value, label = label, text = label, tooltip = tooltip })
            end
            function container:GetData() return self.data end
            return container
        end
        local function control(kind, template, category, setting, options, tooltip)
            local init = newInitializer(kind, template, { setting = setting, name = setting:GetName(), options = options, tooltip = tooltip })
            category.layout:AddInitializer(init)
            return init
        end
        function Settings.CreateCheckbox(category, setting, tooltip)
            misuse(setting:GetVariableType() == "boolean", "CreateCheckbox with a " .. setting:GetVariableType() .. " setting")
            return control("checkbox", "SettingsCheckboxControlTemplate", category, setting, nil, tooltip)
        end
        function Settings.CreateDropdown(category, setting, options, tooltip)
            misuse(options ~= nil, "CreateDropdown without options")
            return control("dropdown", "SettingsDropdownControlTemplate", category, setting, options, tooltip)
        end
        function Settings.CreatePanelInitializer(template, data) return newInitializer("panel", template, data) end
        function CreateSettingsListSectionHeaderInitializer(name, tooltip)
            return newInitializer("header", "SettingsListSectionHeaderTemplate", { name = name, tooltip = tooltip })
        end
        function Settings.OpenToCategory(id, element)
            if c.combat then
                c.settings.blocked = c.settings.blocked + 1
                return
            end
            c.settings.opened[#c.settings.opened + 1] = { id = id, element = element }
            c.settings.current = id
        end
    end
    -- The page of the category the panel shows (the last opened), as the
    -- list draws it: each initializer a row { kind, name, tooltip, value,
    -- options (each { value, label, tooltip }), enabled, extent, frame }. A
    -- panel row gets a fresh frame of its template, or of the native type
    -- its template names, and its InitFrame; each listed row's
    -- value-changed signal re-evaluates its predicates (here: on reading).
    -- A row's extent is the initializer's GetExtent, else the template's
    -- height (Blizzard_SettingsList.lua:68-71). A frame of an XML template
    -- (c.templates, read from the .toc's XML files by c.loadToc) gets the
    -- template's mixin copied in, as the client does when it makes the frame.
    -- c.settingsPage(id) shows that category instead.
    local NATIVE = { Frame = true, Button = true }
    c.templates = {}
    function c.settingsPage(id)
        id = id or c.settings.current
        for _, category in ipairs(c.settings.categories) do
            if category.ID == id then
                local rows = {}
                for _, init in ipairs(category.layout.initializers) do
                    local setting = init.data.setting
                    local options = init.data.options
                    if type(options) == "function" then options = options() end
                    local row = { kind = init.kind, name = setting and setting:GetName() or init.data.name,
                        tooltip = init.data.tooltip, value = setting and setting:GetValue(), options = options,
                        enabled = init:EvaluateModifyPredicates(), extent = init:GetExtent(), init = init }
                    for key, fn in pairs(init.own) do
                        misuse(rawget(init, key) == fn, "a field written on the initializer: " .. key)
                    end
                    if init.kind == "panel" then
                        local template = c.templates[init.frameTemplate]
                        misuse(template ~= nil or NATIVE[init.frameTemplate] == true,
                            "a panel template the fake does not know: " .. tostring(init.frameTemplate))
                        local frame = c.newWidget(template and "Frame" or init.frameTemplate, nil, UIParent, init.frameTemplate)
                        if template then
                            row.extent = row.extent or template.height
                            local mixin = template.mixin and _G[template.mixin]
                            misuse(template.mixin == nil or type(mixin) == "table", "no global mixin " .. tostring(template.mixin))
                            for key, value in pairs(type(mixin) == "table" and mixin or {}) do frame[key] = value end
                        end
                        init:InitFrame(frame)
                        row.frame = frame
                        c.settings.frames[#c.settings.frames + 1] = { init = init, frame = frame }
                    end
                    rows[#rows + 1] = row
                end
                return rows, category
            end
        end
    end
    -- The list lets the page's frames go (the panel hides or another
    -- category is shown): each panel initializer's Resetter.
    function c.hideSettingsPage()
        for _, f in ipairs(c.settings.frames) do f.init:Resetter(f.frame) end
        c.settings.frames = {}
    end
    -- Blizzard's Defaults on the shown category
    -- (SettingsPanelMixin:SetCurrentCategorySettingsToDefaults,
    -- Blizzard_SettingsPanel.lua:500-525): each of its settings to its default.
    function c.settingsDefaults(id)
        id = id or c.settings.current
        for _, category in ipairs(c.settings.categories) do
            if category.ID == id then
                for _, s in ipairs(category.settings) do s:SetValueToDefault() end
            end
        end
    end
    -- The minimap's addon list (Blizzard_Minimap/Mainline/AddonCompartment.lua:
    -- 102-129, which Camelot's file extends): an addon whose .toc names
    -- AddonCompartmentFunc gets an entry; a click calls that global with the
    -- addon's name and the mouse button. Answers the entry { func, icon,
    -- called } (icon: IconTexture, else IconAtlas), or nil without one.
    function c.compartmentClick(dir, button)
        local meta = {}
        for line in io.lines(dir .. "/TransmogChecker.toc") do
            local key, value = line:gsub("\r", ""):match("^##%s*([%w]+):%s*(.-)%s*$")
            if key then meta[key] = value end
        end
        if not meta.AddonCompartmentFunc then return nil end
        local entry = { func = meta.AddonCompartmentFunc, icon = meta.IconTexture or meta.IconAtlas, text = meta.Title }
        local fn = _G[meta.AddonCompartmentFunc]
        misuse(type(fn) == "function", "no global " .. meta.AddonCompartmentFunc)
        if type(fn) == "function" then fn("TransmogChecker", button or "LeftButton") entry.called = true end
        return entry
    end

    -- An XML file's virtual frame templates, into c.templates: for each
    -- <Frame name=... virtual="true"> its mixin and its <Size y=...>. Only
    -- that much of the XML is modelled: no other element, no inherits.
    local function readTemplates(path)
        local file = assert(io.open(path, "r"))
        local text = file:read("*a")
        file:close()
        for attrs, body in text:gmatch("<Frame%s([^>]-)>(.-)</Frame>") do
            local name = attrs:match('name="([^"]+)"')
            if name and attrs:find('virtual="true"', 1, true) then
                misuse(_G[attrs:match('mixin="([^"]+)"') or ""] ~= nil or not attrs:find("mixin=", 1, true),
                    "a mixin that is no global when " .. path .. " loads")
                c.templates[name] = { mixin = attrs:match('mixin="([^"]+)"'),
                    height = tonumber(body:match('<Size[^>]-%sy="(%-?[%d%.]+)"')) }
            end
        end
    end

    -- Loads the addon's files in the .toc's order: a Lua file runs, an XML
    -- file's templates are read (readTemplates).
    function c.loadToc(dir)
        local loaded = {}
        for line in io.lines(dir .. "/TransmogChecker.toc") do
            line = line:gsub("\r", ""):gsub("\\", "/")
            if line ~= "" and line:sub(1, 2) ~= "##" then
                if line:match("%.xml$") then
                    readTemplates(dir .. "/" .. line)
                else
                    local chunk = assert(loadfile(dir .. "/" .. line))
                    chunk("TransmogChecker", {})
                end
                loaded[#loaded + 1] = line
            end
        end
        return loaded
    end

    -- Every C_* function this client made, and GetMoney, record themselves
    -- in c.trace while a click runs (C_AuctionHouse does in its __index).
    for name, ns in pairs(_G) do
        if type(name) == "string" and name:match("^C_") and type(ns) == "table" and name ~= "C_AuctionHouse"
            and not traceWrapped[ns] then
            traceWrapped[ns] = true
            for key, fn in pairs(ns) do
                if type(fn) == "function" then
                    ns[key] = function(...)
                        traced(name .. "." .. key)
                        return fn(...)
                    end
                end
            end
        end
    end
    if GetMoney then
        local getMoney = GetMoney
        GetMoney = function()
            traced("GetMoney")
            return getMoney()
        end
    end

    return c
end

return Fake
