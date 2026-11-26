-- The appearance browser's panel: a tab on the auction house window, added
-- through LibAHTab. Writing the auction frame's tab state by hand taints bag
-- clicks, so only the library touches the tab. The panel draws what
-- TC.BrowserState answers and forwards clicks to it; no rule lives here.

-- The library keeps one tab per id.
local TAB_ID = "TransmogChecker"
local TAB_TEXT = "Appearances"
local WINDOW_TITLE = "Appearance Browser"

-- Sizes and positions of layout B (appearance-browser-layout-flows v2), in
-- panel units from the panel's top left. Tiles and gaps are Collections' own.
-- The grid is always 8 columns of 3 rows; it never moves. It sits 2 higher
-- than layout B put it, at y 78 (testpass F3, F4).
local COLUMNS, ROWS = 8, 3
local GRID_X, GRID_Y = 28, 78
local TILE_WIDTH, TILE_HEIGHT = 78, 104
local GAP_X, GAP_Y = 16, 24
local MODEL_HEIGHT, STRIP_HEIGHT = 82, 20
local CHECK_SIZE = 16
-- The tile's frame (visual pass v2, board 6): Collections' tile art
-- (WardrobeItemsModelTemplate, Blizzard_Collections/Mainline/
-- Blizzard_Wardrobe.xml:12-18, 29-33, 56-62; Blizzard_Wardrobe.lua:1101-1108):
-- the border, bright for a collected appearance (decision 2A), the selected
-- glow for the open tile and the highlighted glow on hover, each tested with
-- C_Texture.GetAtlasInfo. Without an atlas, a 1-unit line in the board's
-- colour for it.
local EDGE_ATLAS, EDGE_COLLECTED_ATLAS = "transmog-wardrobe-border-uncollected", "transmog-wardrobe-border-collected"
local OPEN_ATLAS, HOVER_ATLAS = "transmog-wardrobe-border-selected", "transmog-wardrobe-border-highlighted"
local BORDER = { 0.302, 0.267, 0.216, 1 }
local BORDER_COLLECTED = { 0.643, 0.553, 0.384, 1 }
local BORDER_OPEN = { 1, 0.82, 0, 1 }
local BORDER_HOVER = { 0.965, 0.863, 0.604, 1 }
local WELL = { 0, 0, 0, 1 }
local TEXT_WHITE = { 1, 1, 1 }
-- The price strip, drawn only once something is known (decision 3A): a dark
-- plate, #1b1712 to #14110d, under a 1-unit line of #2d261d.
local STRIP_TOP, STRIP_BOTTOM, STRIP_LINE = { 0.106, 0.09, 0.071, 1 }, { 0.078, 0.067, 0.051, 1 }, { 0.176, 0.149, 0.114, 1 }
local STRIP_CHECKED = { 0.12, 0.12, 0.12, 1 }
-- Collections' model light, the values of ItemModelBaseMixin:OnLoad
-- (Blizzard_TransmogShared/Blizzard_TransmogShared.lua:655-667), for
-- SetLight(enabled, ModelLight) (SimpleModelAPIDocumentation.lua:563-571,
-- SharedScriptObjectModelLightDocumentation.lua:6-17).
local LIGHT = { point = { -1, 1, -1 }, ambient = 1.05, diffuse = 0 }
-- The flyout (layout B, section 6): 232 wide, as high as its parts (head
-- 66, which holds the summary line right of the model, rows of 40, foot 28)
-- and at most 300; four rows show, more scroll. It opens left of its tile
-- when it fits inside the panel there, else right (testpass F7), 8 from the
-- tile, its top 28 above the tile's, moved up so it never passes the grid's
-- bottom. The notch stays on the tile's middle.
local FLY_WIDTH, FLY_MAX, FLY_GAP, FLY_ABOVE = 232, 300, 8, 28
local GRID_BOTTOM = GRID_Y + ROWS * TILE_HEIGHT + (ROWS - 1) * GAP_Y
local FLY_HEAD, FLY_TEXT, FLY_ROW, FLY_NOTE, FLY_FOOT, FLY_ROWS = 66, 30, 40, 14, 28, 4
local FLY_INSIDE = FLY_WIDTH - 20
-- The head's texts start right of the model (x 62) and stop before the close mark.
local HEAD_TEXT_X = 62
local HEAD_TEXT_WIDTH = FLY_WIDTH - HEAD_TEXT_X - 28
local FLY_EDGE = { 0.54, 0.45, 0.30, 1 }
local FLY_FILL = { 0.04, 0.035, 0.03, 0.97 }
local NOTCH_SIZE = 12
-- Hairlines under the head and over the foot, and the scroll track (layout
-- B, board 6.1: #5a4a33, #2c251c).
local FLY_LINE, FLY_TRACK = { 0.353, 0.29, 0.2, 1 }, { 0.173, 0.145, 0.114, 1 }
-- Rows in the auction house's list language (visual pass, board 8): its row
-- stripe on alternate rows and its highlight on hover
-- (Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseItemList.xml:15,
-- 23), each tested; without them the board's colours.
local ROW_STRIPE_ATLAS, ROW_HIGHLIGHT_ATLAS = "auctionhouse-rowstripe-1", "auctionhouse-ui-row-highlight"
local ROW_STRIPE, ROW_HOVER = { 1, 1, 1, 0.045 }, { 1, 0.839, 0.471, 0.13 }
-- The fade over the last row when more rows follow below.
local FADE_HEIGHT = 16
local HEAD_MODEL_WIDTH, HEAD_MODEL_HEIGHT = 44, 58
-- A found row's Buy button.
local BUY_WIDTH, BUY_HEIGHT = 40, 18
-- Texture paths are inferred from mainline clients, not read for Forever.
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
-- The mark of a pending appearance (TC-39), the owner's choice in game; this
-- build's EquipmentFlyout.lua:521 uses the file.
local PENDING_TEXTURE = "Interface\\PaperDollInfoFrame\\UI-GearManager-ItemIntoBag"
-- A line of the head's small text; the pending sentence wraps, and the head
-- grows by what it takes beyond one line (four lines when it cannot be measured).
local HEAD_LINE, HEAD_LINES_MAX = 12, 4
local ARROW = "Interface\\Buttons\\UI-SpellbookIcon-%sPage-%s"
-- Coin atlases of this build's money frame (Blizzard_MoneyFrame/Shared/MoneyFrame.lua:347-354).
local COIN_ATLAS = { gold = "coin-gold", silver = "coin-silver", copper = "coin-copper" }
local COIN_LETTERS = { gold = "g", silver = "s", copper = "c" }
-- How often a shown item list redraws, so its age stays true.
local AGE_REDRAW = 15
-- The status line's progress bar (spec 2.8) in Collections' search bar look
-- (Blizzard_Collections/Mainline/Blizzard_Wardrobe.xml:339-390: a 0.4 black
-- back, the status bar texture, the achievement bar's three-piece border),
-- 72 x 11 (visual pass, board 9), and a placeholder's short bar (#3d352b).
local PROGRESS_WIDTH, PROGRESS_HEIGHT = 72, 11
local PROGRESS_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local PROGRESS_BORDER = "Interface\\AchievementFrame\\UI-Achievement-ProgressBar-Border"
local PROGRESS_BACK = { 0, 0, 0, 0.4 }
local BAR_WIDTH, BAR_HEIGHT = 30, 4
local BAR_COLOR = { 0.239, 0.208, 0.169, 1 }
local PROGRESS_COLOR = { 1, 0.82, 0, 1 }
-- The paging arrows' highlight (Blizzard_Collections/Shared/
-- Blizzard_CollectionTemplates.xml:200).
local ARROW_HIGHLIGHT = "Interface\\Buttons\\UI-Common-MouseHilight"
-- The panel's background: one Collections inset under the grid, the status
-- line and paging, from y 66 to the bottom (visual pass, board 2, decision
-- 1A), CollectionsBackgroundTemplate (Blizzard_SharedXML/Mainline/
-- SharedCollectionTemplates.xml:56-202) without its corner ornaments. Its
-- edge is 12 above the tiles (testpass F3).
local INSET_Y = 66
local INSET_CORNERS = { "BGCornerTopLeft", "BGCornerTopRight", "BGCornerBottomLeft", "BGCornerBottomRight" }
-- Parts of a line 6 apart.
local TOOLS_GAP = 6
-- The header row (layout B, 1.1): the slot row, Search and the funnel.
local MEDIA = "Interface\\AddOns\\TransmogChecker\\Media\\"
-- The scan action's glyph on the scan control, left of the text, when the
-- client has the atlas (the owner's choice).
local SCAN_ATLAS, SCAN_GLYPH = "UI-RefreshButton", 14
local SCAN_TIP = "Scans this slot's items on the auction house now."
-- The slot row: round buttons of 31, 2 apart, 19 between groups
-- (Blizzard_Collections/Camelot/Blizzard_Wardrobe.lua:24-27), starting at the
-- grid's left edge, x 28, where the catalogue and sweep toggles were
-- before (slice B). Collections' own art (WardrobeSlotButtonTemplate,
-- Blizzard_Collections/Mainline/Blizzard_Wardrobe.xml:99-130, and
-- CreateSlotButtons, Blizzard_Wardrobe.lua:460-503); that this client has
-- these atlases is read from source and unverified in game.
local SLOTS_X, SLOTS_Y, SLOT_SIZE, SLOT_GAP, GROUP_GAP = 28, 4, 31, 2, 19
local SLOT_ART, SLOT_SELECTED, SLOT_HIGHLIGHT = "transmog-nav-slot-%s", "transmog-nav-slot-selected", "bags-roundhighlight"
-- Search at x 642, y 9, 108 x 20; the funnel at x 757, y 4, 30 square, with
-- the world map's filter art (Blizzard_WorldMap/Mainline/
-- Blizzard_WorldMapTemplates.xml:7, 41) and the auction house's reset mark
-- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:867-871), as the
-- auction house's Filter button carries it (ClearFiltersButton,
-- Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSearchBar.xml:21-25),
-- while a choice differs from the start (layout B, 1.3). The funnel is 4
-- from the panel's right edge, so the mark is 18 square and sits in the
-- funnel's top right corner, its right edge on the funnel's and its top 2
-- below the panel's, clear of the frame's border (testpass F5).
local SEARCH_X, SEARCH_Y = 642, 9
local FUNNEL_X, FUNNEL_Y, FUNNEL_SIZE, MARK_SIZE, MARK_X, MARK_Y = 757, 4, 30, 18, -9, -7
-- The funnel's art is the owner's choice, the settings button of
-- Blizzard_DamageMeter/DamageMeterSettingsDropdownButton.xml:5-8, with its
-- hover and pressed forms; without it the world map's filter art.
local FUNNEL_ATLAS = "common-dropdown-a-button-settings-shadowless"
local FUNNEL_HOVER = "common-dropdown-a-button-settings-hover-shadowless"
local FUNNEL_PRESSED = "common-dropdown-a-button-settings-pressed-shadowless"
local FUNNEL_PRESSED_HOVER = "common-dropdown-a-button-settings-pressedhover-shadowless"
local FUNNEL_OPEN = "common-dropdown-a-button-settings-open-shadowless"
local FUNNEL_FALLBACK, RESET_ATLAS = "Map-Filter-Button", "auctionhouse-ui-filter-redx"
local FUNNEL_TEXT, FUNNEL_TIP = "Filter", "Filter and sort"
local CLASS_TEXT, RESET_TEXT = "Class: %s", "Reset filters"
local FOR_SALE_TEXT, SOURCE_TEXT, SORT_TEXT, SCAN_SHOWN_TEXT = "For sale only", "Source", "Sort", "Scan when shown"
-- A checkbox's mark in the panel's own list menu, without Blizzard's menu.
local TICKED, UNTICKED = "[x] ", "[ ] "
-- The band under the header: the count at x 28, y 42, and the weapon type
-- dropdown (Collections' width, Blizzard_Wardrobe.lua:568) at x 598, its
-- vertical centre at y 50 (a 22 high box from y 39, whatever height the
-- dropdown template gives it); 8 higher than layout B put it, so the grid
-- has room under it (testpass F3). The count has no width of its own.
local COUNT_X, COUNT_Y = 28, 42
local WEAPON_X, WEAPON_CENTRE, WEAPON_WIDTH, WEAPON_HEIGHT = 598, 50, 157, 22
-- The bottom row sits between the grid's edges: the status button, when
-- there is one, at the grid's left edge, always at one place and one width,
-- the status text after it; paging ends at the grid's right edge, with the
-- wheel mark before the page text (layout B, section 8). The row is 4 higher
-- than layout B put it, so the status button and the arrows, on one centre
-- line, end 6 and 5 above the panel's bottom (testpass F4). The page text is
-- one line, as wide as its widest form for the page count and PAGE_ROOM more.
local STATUS_Y, STATUS_BUTTON = 441, 110
local PAGING_Y, WHEEL_WIDTH, WHEEL_HEIGHT, PAGE_ROOM = 441, 16, 16, 4
local NEXT_TIP, PREVIOUS_TIP = "Next page", "Previous page"
local WHEEL_TIP, ARROW_HINT = "Mouse wheel over the tiles turns pages", "Mouse wheel over the tiles turns pages too."
-- The tile tooltip's minimum width (FrameAPITooltipDocumentation.lua:94-104):
-- the longest sentence, the bought one, takes at most three lines at it.
local TIP_MIN_WIDTH = 220

local State = TC.BrowserState

-- A button in Blizzard's panel style; the bare button still works without
-- the template.
local function newButton(parent, text, width, height, onClick)
    local ok, button = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not ok then
        button = CreateFrame("Button", nil, parent)
        -- SetNormalFontObject takes a font object (SimpleButtonAPIDocumentation.lua)
        if GameFontNormal then button:SetNormalFontObject(GameFontNormal) end
    end
    button:SetSize(width, height)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

-- A tooltip of a title and, when given, a grey line under it.
local function tooltip(frame, title, line)
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        if line then GameTooltip:AddLine(line, 0.5, 0.5, 0.5, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

-- A paging arrow; its tooltip says the wheel turns pages too (layout B, 8.1).
local function arrowButton(parent, direction, onClick, tip)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(22, 22)
    button:SetNormalTexture(ARROW:format(direction, "Up"))
    button:SetPushedTexture(ARROW:format(direction, "Down"))
    button:SetDisabledTexture(ARROW:format(direction, "Disabled"))
    button:SetHighlightTexture(ARROW_HIGHLIGHT, "ADD")
    button:SetScript("OnClick", onClick)
    tooltip(button, tip, ARROW_HINT)
    return button
end

-- Model_ApplyUICamera puts the camera at MODELFRAME_UI_CAMERA_POSITION, 4
-- units out along camera-space x, looking at the origin
-- (Blizzard_SharedXML/Mainline/ModelFrames.lua:70-88). A model whose slot has
-- a zoom (TC.Slots, spec 4.3) moves the camera out along the same line by
-- that factor, so a cloak is not cut off; no zoom leaves the appearance's own
-- camera. That a zoom of 1.236 frames a cloak whole is the owner's wish, to be
-- seen in game.

local function applyCamera(model)
    if not (model.tcCamera and Model_ApplyUICamera) then return end
    Model_ApplyUICamera(model, model.tcCamera)
    local fit = model.tcZoom
    -- Model_ApplyUICamera moved the camera only when the camera has a position
    local custom = GetUICameraInfo and GetUICameraInfo(model.tcCamera)
    if not (fit and fit > 1 and custom and model.TransformCameraSpaceToModelSpace and model.SetCameraPosition) then
        return
    end
    local from = MODELFRAME_UI_CAMERA_POSITION or { x = 4, y = 0, z = 0 }
    local position = model:TransformCameraSpaceToModelSpace({ x = from.x * fit, y = from.y * fit, z = from.z * fit })
    if position and position.GetXYZ then model:SetCameraPosition(position:GetXYZ()) end
end

-- Collections' flat light on a model, once, when the client has SetLight
-- and the vector and colour makers; a call that raises leaves the model as
-- it is. Its effect on these tiles is unverified in game.
local function light(model)
    if not (model.SetLight and CreateVector3D and CreateColor) then return end
    local p = LIGHT.point
    pcall(model.SetLight, model, true, { omnidirectional = false, point = CreateVector3D(p[1], p[2], p[3]),
        ambientIntensity = LIGHT.ambient, ambientColor = CreateColor(1, 1, 1),
        diffuseIntensity = LIGHT.diffuse, diffuseColor = CreateColor(1, 1, 1) })
end

-- The player's figure, drawn with the transmog skin and wearing only the
-- tile's piece, set up once as Blizzard's wardrobe does
-- (ItemModelBaseMixin:OnLoad, as the probe's tiles ran it in game).
local function newModel(parent, x, y, width, height)
    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    model:SetSize(width, height)
    model:SetAutoDress(false)
    light(model)
    model:SetUseTransmogSkin(true)
    model:SetUseTransmogChoices(true)
    model:SetObeyHideInTransmogFlag(true)
    model:SetUnit("player", false)
    model:SetKeepModelOnHide(true)
    -- Blizzard applies the camera again once the model is in
    -- (ItemModelBaseMixin:OnModelLoaded).
    model:SetScript("OnModelLoaded", applyCamera)
    return model
end

-- A weapon alone, without a unit, as the probe showed a dagger in game and
-- Blizzard's wardrobe shows weapons (Blizzard_Wardrobe.lua:1088-1093). A
-- frame is never switched between the armor and the weapon setup (spec
-- 4.1), so weapons have their own frames, made when first needed.
local function newWeaponModel(parent, x, y, width, height)
    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    model:SetSize(width, height)
    model:SetAutoDress(false)
    light(model)
    model:SetKeepModelOnHide(true)
    model:SetScript("OnModelLoaded", applyCamera)
    return model
end

-- Points the model's camera at the appearance's own, zoomed by its slot's
-- zoom; answers whether that changed anything.
local function frame(model, appearance)
    local TCol = C_TransmogCollection
    local cameraID = TCol and TCol.GetAppearanceCameraID and TCol.GetAppearanceCameraID(appearance.id)
    cameraID = type(cameraID) == "number" and cameraID or nil
    local entry = TC.Slots[appearance.slot]
    local zoom = entry and entry.zoom or 1
    if model.tcCamera == cameraID and model.tcZoom == zoom then return false end
    model.tcCamera, model.tcZoom = cameraID, zoom
    applyCamera(model)
    return true
end

-- Frames the model with the appearance's own camera; answers false when the
-- model already shows the appearance.
local function aim(model, appearance)
    if model.tcAppearance == appearance.id then return false end
    model.tcAppearance = appearance.id
    -- the camera is applied again even when it is the same, as before
    model.tcCamera = nil
    frame(model, appearance)
    return true
end

-- Frames the model on the slot, then puts the piece on. Paging only changes
-- the piece.
local function dress(model, appearance)
    if not aim(model, appearance) then return end
    -- the same frames serve every armor slot: a piece of another slot comes
    -- off first, as Blizzard undresses on a slot change
    -- (Blizzard_Wardrobe.lua:709-735); within one slot a piece replaces the last
    if model.tcSlot and model.tcSlot ~= appearance.slot and model.Undress then model:Undress() end
    model.tcSlot = appearance.slot
    local sourceID = TC.Appearances.DisplaySource(appearance)
    if sourceID then
        model:TryOn(sourceID)
    end
end

-- Frames the weapon model, then sets the appearance on it; without the
-- camera a weapon is tiny (spec 4.1).
local function dressWeapon(model, appearance)
    if aim(model, appearance) then model:SetItemAppearance(appearance.id) end
end

-- Shows the appearance on the armor model or, for a weapon, on the weapon
-- model holder[key], made the first time.
local function show(holder, key, armorModel, appearance, weapon, makeWeapon)
    if weapon then
        holder[key] = holder[key] or makeWeapon()
        armorModel:Hide()
        holder[key]:Show()
        dressWeapon(holder[key], appearance)
    else
        if holder[key] then holder[key]:Hide() end
        armorModel:Show()
        dress(armorModel, appearance)
    end
end

-- A tile's cell: its column and row from 0, and its top left in the grid.
local function cell(index)
    local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    return column, row, column * (TILE_WIDTH + GAP_X), row * (TILE_HEIGHT + GAP_Y)
end

-- A price as numbers each followed by a small coin, from the state's parts.
local function moneyMarkup(parts)
    local words = {}
    for i, part in ipairs(parts) do
        local coin = CreateAtlasMarkup and CreateAtlasMarkup(COIN_ATLAS[part.coin], 12, 12) or COIN_LETTERS[part.coin]
        words[i] = part.amount .. coin
    end
    return table.concat(words, " ")
end

-- An atlas the client has (C_Texture.GetAtlasInfo,
-- TextureUtilsDocumentation.lua:75-88).
local function hasAtlas(atlas)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- An atlas on a texture, when the client has SetAtlas (read from source).
local function setAtlas(texture, atlas, useAtlasSize)
    if texture.SetAtlas then texture:SetAtlas(atlas, useAtlasSize) end
end

-- A vertical gradient from bottom to top (SetGradient,
-- SimpleTextureBaseAPIDocumentation.lua:439-449), or the flat colour
-- without the colour maker.
local function gradient(texture, bottom, top, flat)
    texture:SetColorTexture(1, 1, 1, 1)
    if texture.SetGradient and CreateColor then
        texture:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top)))
    else
        texture:SetColorTexture(unpack(flat))
    end
end

-- Which of the tile's atlases the client has, asked once per panel.
local function tileArt()
    return { edge = hasAtlas(EDGE_ATLAS) and hasAtlas(EDGE_COLLECTED_ATLAS), open = hasAtlas(OPEN_ATLAS),
        hover = hasAtlas(HOVER_ATLAS),
        -- the pending mark's file, unless GetFileIDFromPath knows it is missing
        pending = not (GetFileIDFromPath and GetFileIDFromPath(PENDING_TEXTURE) == nil) }
end

-- An atlas texture of the tile's art on its button, centred, in the atlas's
-- size, as Collections' tile draws it.
local function glow(tile, atlas, sublevel, add)
    local texture = tile.button:CreateTexture(nil, "OVERLAY", nil, sublevel)
    texture:SetPoint("CENTER", tile, "CENTER", 0, 0)
    setAtlas(texture, atlas, true)
    if add then texture:SetBlendMode("ADD") end
    texture:Hide()
    return texture
end

-- The tile's markers from its state: the collected border and the check,
-- the pending mark (TC-39), the open glow, the hover glow. Without an atlas
-- its state colours the tile's line instead: open over hover over collected.
local function drawMarkers(tile)
    local art = tile.art
    tile.check:SetShown(tile.collected == true)
    if tile.pendingMark then tile.pendingMark:SetShown(tile.pending and not tile.collected) end
    if tile.edge then setAtlas(tile.edge, tile.collected and EDGE_COLLECTED_ATLAS or EDGE_ATLAS, true) end
    if tile.openGlow then tile.openGlow:SetShown(tile.isOpen == true) end
    if tile.hoverGlow then tile.hoverGlow:SetShown(tile.hovered == true) end
    local line = art.edge and WELL or (tile.collected and BORDER_COLLECTED or BORDER)
    if tile.hovered and not art.hover then line = BORDER_HOVER end
    if tile.isOpen and not art.open then line = BORDER_OPEN end
    tile.border:SetColorTexture(unpack(line))
end

local function newTile(grid, index, art, onClick, onWheel, onEnter, onLeave)
    local tile = CreateFrame("Frame", nil, grid)
    tile.index, tile.art = index, art
    tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
    local _, _, x, y = cell(index)
    tile:SetPoint("TOPLEFT", grid, "TOPLEFT", x, -y)
    tile.border = tile:CreateTexture(nil, "BACKGROUND")
    tile.border:SetAllPoints()
    local inside = tile:CreateTexture(nil, "BORDER")
    inside:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
    inside:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
    inside:SetColorTexture(unpack(WELL))
    -- The price strip, a plate shown only once something is known; the model
    -- and the tile keep their size without it (decision 3A).
    tile.strip = tile:CreateTexture(nil, "ARTWORK")
    tile.strip:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1 - MODEL_HEIGHT)
    tile.strip:SetSize(TILE_WIDTH - 2, STRIP_HEIGHT)
    gradient(tile.strip, STRIP_BOTTOM, STRIP_TOP, STRIP_CHECKED)
    tile.stripLine = tile:CreateTexture(nil, "ARTWORK", nil, 1)
    tile.stripLine:SetPoint("TOPLEFT", tile.strip, "TOPLEFT", 0, 0)
    tile.stripLine:SetSize(TILE_WIDTH - 2, 1)
    tile.stripLine:SetColorTexture(unpack(STRIP_LINE))
    tile.price = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.price:SetPoint("CENTER", tile.strip, "CENTER")
    tile.notForSale = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tile.notForSale:SetPoint("CENTER", tile.strip, "CENTER")
    -- a placeholder's short bar
    tile.bar = tile:CreateTexture(nil, "OVERLAY")
    tile.bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    tile.bar:SetPoint("CENTER", tile.strip, "CENTER")
    tile.bar:SetColorTexture(unpack(BAR_COLOR))
    tile.model = newModel(tile, 1, -1, TILE_WIDTH - 2, MODEL_HEIGHT)
    -- The check and the click sit on their own button above the model, so
    -- the model never covers them. A button takes left clicks by default;
    -- whether it also swallows the wheel is unverified, so it pages too.
    local above = CreateFrame("Button", nil, tile)
    above:SetAllPoints()
    above:SetFrameLevel(tile.model:GetFrameLevel() + 1)
    above:SetScript("OnClick", function() onClick(tile) end)
    above:EnableMouseWheel(true)
    above:SetScript("OnMouseWheel", function(_, delta) onWheel(delta) end)
    above:SetScript("OnEnter", function() onEnter(tile) end)
    above:SetScript("OnLeave", function() onLeave(tile) end)
    tile.button = above
    -- Collections' border on OVERLAY sublevel -1, 3 below the centre
    -- (Blizzard_Wardrobe.xml:12-18), the open and hover glows over it
    if art.edge then
        tile.edge = glow(tile, EDGE_ATLAS, -1)
        tile.edge:ClearAllPoints()
        tile.edge:SetPoint("CENTER", tile, "CENTER", 0, -3)
        tile.edge:Show()
    end
    if art.open then tile.openGlow = glow(tile, OPEN_ATLAS, 0, true) end
    if art.hover then tile.hoverGlow = glow(tile, HOVER_ATLAS, 1, true) end
    tile.check = above:CreateTexture(nil, "OVERLAY", nil, 2)
    tile.check:SetSize(CHECK_SIZE, CHECK_SIZE)
    tile.check:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -3, -3)
    tile.check:SetTexture(CHECK_TEXTURE)
    -- the pending mark where the check sits (an appearance is never both)
    if art.pending then
        tile.pendingMark = above:CreateTexture(nil, "OVERLAY", nil, 2)
        tile.pendingMark:SetSize(CHECK_SIZE, CHECK_SIZE)
        tile.pendingMark:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -3, -3)
        tile.pendingMark:SetTexture(PENDING_TEXTURE)
        tile.pendingMark:Hide()
    end
    return tile
end

-- A placeholder tile is the dark figure without an item. Undress is read
-- from this build's DressUpModel documentation
-- (FrameAPIDressUpModelDocumentation.lua:240) and not run in game.
local function undress(model)
    if model.tcAppearance == nil then return end
    model.tcAppearance, model.tcSlot = nil, nil
    if model.Undress then model:Undress() end
end

-- A placeholder's figure is undressed and framed like the slot's first listed
-- appearance, so all placeholders of a page look alike; without one the dark
-- tile with its bar stays.
local function drawPlaceholder(tile, cameraAppearance)
    if tile.weaponModel then tile.weaponModel:Hide() end
    if not cameraAppearance then return tile.model:Hide() end
    tile.model:Show()
    undress(tile.model)
    frame(tile.model, cameraAppearance)
end

local function drawTile(tile, shown)
    tile.appearance = shown.appearance
    tile.collected, tile.isOpen, tile.pending = shown.collected == true, shown.open == true, shown.pending == true
    drawMarkers(tile)
    tile.strip:SetShown(shown.strip ~= nil)
    tile.stripLine:SetShown(shown.strip ~= nil)
    tile.price:SetText(shown.money and moneyMarkup(shown.money) or "")
    tile.notForSale:SetText((shown.strip == "not for sale" or shown.strip == "no answer") and shown.price or "")
    tile.bar:SetShown(shown.strip == "bar")
    if shown.appearance then
        show(tile, "weaponModel", tile.model, shown.appearance, shown.weapon, function()
            return newWeaponModel(tile, 1, -1, TILE_WIDTH - 2, MODEL_HEIGHT)
        end)
    else
        drawPlaceholder(tile, shown.cameraAppearance)
    end
end

-- Colours a name by item quality; a name not loaded yet is a grey dash.
local function setName(fontString, name, quality)
    fontString:SetText(name or "-")
    local r, g, b = 0.5, 0.5, 0.5
    if name and type(quality) == "number" and C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(quality)
    end
    fontString:SetTextColor(r or 1, g or 1, b or 1)
end

-- A frame from a Blizzard template, or a bare one when the template is not
-- there (both templates are read from this build's source).
local function templated(kind, parent, template)
    local ok, frame = pcall(CreateFrame, kind, nil, parent, template)
    return ok and frame or nil
end

-- SetPropagateKeyboardInput is restricted (SimpleFrameAPIDocumentation.lua:
-- 1426-1435), so the flyout takes the keyboard only out of combat, as the buy
-- dialog does (TC_Buy); in combat Escape goes to the game. EnableKeyboard in
-- combat on this unprotected frame is inferred to be allowed, unverified.
local function inCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end
local function canPropagate(frame)
    return frame.SetPropagateKeyboardInput ~= nil and not inCombat()
end
local function setKeyboard(frame, on)
    if frame.EnableKeyboard then frame:EnableKeyboard(on) end
end
local function takeKeyboard(frame)
    if canPropagate(frame) then
        frame:SetPropagateKeyboardInput(true)
        setKeyboard(frame, true)
    else
        setKeyboard(frame, false)
    end
end

-- How many rows a flyout shows and its height, from its parts (layout B,
-- section 6).
local function flyoutSize(list, head)
    local fixed = head + FLY_FOOT + (list.text and FLY_TEXT or 0) + (list.foot.note and FLY_NOTE or 0)
    local rows = math.min(#list.rows, FLY_ROWS, math.floor((FLY_MAX - fixed) / FLY_ROW))
    return rows, fixed + rows * FLY_ROW
end

-- The flyout: the item list of the open tile beside it, over the tiles next
-- to it; head, body and foot (spec 2.6, layout B section 6). It draws the
-- list the state answers and forwards the close, Check again and Buy
-- clicks. Escape, the close mark and a click outside it and the tiles close
-- it; Escape touches none of Blizzard's Escape handling, it is kept by this
-- frame alone and only while no buy dialog is open. A click outside is told
-- by GLOBAL_MOUSE_DOWN (SystemDocumentation.lua:66) and IsMouseOver
-- (SimpleScriptRegionAPIDocumentation.lua:507), unverified in game. Built on
-- the first click on a tile; level puts it above the tiles.
local function newFlyout(panel, level, overTile)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetFrameLevel(level)
    frame:SetWidth(FLY_WIDTH)
    -- it takes the mouse, so the tiles under it take no click
    frame:EnableMouse(true)
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(unpack(FLY_EDGE))
    local fill = frame:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(unpack(FLY_FILL))
    -- the notch toward the tile: a square turned 45 degrees (SetRotation,
    -- SimpleTextureBaseAPIDocumentation.lua:527); without the call a square
    local function notchPart(layer, size, colour)
        local texture = frame:CreateTexture(nil, layer)
        texture:SetSize(size, size)
        texture:SetColorTexture(unpack(colour))
        if texture.SetRotation then texture:SetRotation(math.pi / 4) end
        return texture
    end
    local notch = { notchPart("BACKGROUND", NOTCH_SIZE + 2, FLY_EDGE), notchPart("BORDER", NOTCH_SIZE - 1, FLY_FILL) }

    -- head: the model, the type and, when collected, "Collected" with the
    -- tile's check
    local model = newModel(frame, 10, -8, HEAD_MODEL_WIDTH, HEAD_MODEL_HEIGHT)
    -- the tile's border around the small model, on a frame above it
    -- (visual pass, board 8); without the atlases none, as before
    local modelEdge
    if hasAtlas(EDGE_ATLAS) and hasAtlas(EDGE_COLLECTED_ATLAS) then
        local over = CreateFrame("Frame", nil, frame)
        over:SetFrameLevel(frame:GetFrameLevel() + 5)
        over:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
        over:SetSize(HEAD_MODEL_WIDTH, HEAD_MODEL_HEIGHT)
        modelEdge = over:CreateTexture(nil, "OVERLAY")
        modelEdge:SetPoint("TOPLEFT", over, "TOPLEFT", -3, 3)
        modelEdge:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", 3, -3)
    end
    -- hairlines under the head and over the foot (layout B, board 6.1)
    local function hairline()
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(unpack(FLY_LINE))
        return line
    end
    local headLine, footLine = hairline(), hairline()
    headLine:SetWidth(FLY_INSIDE)
    footLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, FLY_FOOT)
    footLine:SetWidth(FLY_INSIDE)
    local typeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typeText:SetPoint("TOPLEFT", frame, "TOPLEFT", HEAD_TEXT_X, -10)
    typeText:SetWidth(HEAD_TEXT_WIDTH)
    typeText:SetJustifyH("LEFT")
    -- "Collected", or in its place the pending sentence (TC-39), which wraps
    local collectedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    collectedText:SetPoint("TOPLEFT", typeText, "BOTTOMLEFT", 0, -4)
    collectedText:SetJustifyH("LEFT")
    local collectedCheck = frame:CreateTexture(nil, "OVERLAY")
    collectedCheck:SetSize(12, 12)
    collectedCheck:SetPoint("LEFT", collectedText, "RIGHT", 2, 0)
    collectedCheck:SetTexture(CHECK_TEXTURE)
    -- UIPanelCloseButton: Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:148
    local close = templated("Button", frame, "UIPanelCloseButton")
    if not close then
        close = CreateFrame("Button", nil, frame)
        if GameFontNormal then close:SetNormalFontObject(GameFontNormal) end
        close:SetText("x")
    end
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", State.CloseList)

    -- the summary line, under the type (and "Collected"), right of the model
    -- SpinnerTemplate: Blizzard_SharedXML/Spinner.xml:3
    local spinner = templated("Frame", frame, "SpinnerTemplate")
    if spinner then spinner:SetSize(16, 16) end
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetJustifyH("LEFT")
    -- body: a text, the rows
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetWidth(FLY_INSIDE)
    text:SetJustifyH("LEFT")
    -- offset: the rows scrolled past; shown: the rows that fit
    local offset, count, shown = 0, 0, FLY_ROWS
    local rows = {}
    local stripeArt, highlightArt = hasAtlas(ROW_STRIPE_ATLAS), hasAtlas(ROW_HIGHLIGHT_ATLAS)
    local scroll
    for i = 1, FLY_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(FLY_INSIDE, FLY_ROW)
        -- the stripe on alternate rows
        if i % 2 == 1 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            if stripeArt then setAtlas(stripe, ROW_STRIPE_ATLAS) else stripe:SetColorTexture(unpack(ROW_STRIPE)) end
        end
        -- the highlight while the pointer is over the row; the row passes
        -- the wheel on to the flyout's scrolling
        row.highlight = row:CreateTexture(nil, "BORDER")
        row.highlight:SetAllPoints()
        if highlightArt then setAtlas(row.highlight, ROW_HIGHLIGHT_ATLAS) else row.highlight:SetColorTexture(unpack(ROW_HOVER)) end
        row.highlight:SetBlendMode("ADD")
        row.highlight:Hide()
        row:EnableMouse(true)
        row:SetScript("OnEnter", function() row.highlight:Show() end)
        row:SetScript("OnLeave", function() row.highlight:Hide() end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) scroll(delta) end)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
        row.name:SetWidth(FLY_INSIDE - 12)
        row.name:SetJustifyH("LEFT")
        row.forSale = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.forSale:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -22)
        -- "Buy" on a found row (spec 2.6): the state opens the buy dialog;
        -- the price sits beside it (layout B, 6.2)
        row.buy = newButton(row, "Buy", BUY_WIDTH, BUY_HEIGHT, function() State.BuyRow(offset + i) end)
        row.buy:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -18)
        row.buy:Hide()
        row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        rows[i] = row
    end
    -- when the rows scroll: a thin track with the scroll position on it
    -- (layout B, board 6.1), and a fade over the last row while more follow
    local track = frame:CreateTexture(nil, "ARTWORK")
    track:SetWidth(2)
    track:SetColorTexture(unpack(FLY_TRACK))
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(6)
    thumb:SetColorTexture(unpack(FLY_EDGE))
    local fade = frame:CreateTexture(nil, "OVERLAY")
    fade:SetSize(FLY_INSIDE, FADE_HEIGHT)
    gradient(fade, FLY_FILL, { FLY_FILL[1], FLY_FILL[2], FLY_FILL[3], 0 }, { 0, 0, 0, 0 })

    -- foot
    local ageText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ageText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, FLY_FOOT + 2)
    local again = newButton(frame, "", 90, 20, State.CheckAgain)
    again:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 5)

    -- Beside the tile at index of the grid, left when it fits inside the
    -- panel there, else right, never past the grid's bottom; the notch on
    -- the tile's middle.
    local function place(index, height)
        local _, _, x, y = cell(index)
        x, y = GRID_X + x, GRID_Y + y
        local right = x - FLY_GAP - FLY_WIDTH < 0
        local top = math.max(GRID_Y, math.min(y - FLY_ABOVE, GRID_BOTTOM - height))
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", panel, "TOPLEFT", right and x + TILE_WIDTH + FLY_GAP or x - FLY_GAP - FLY_WIDTH, -top)
        frame:SetHeight(height)
        for _, part in ipairs(notch) do
            part:ClearAllPoints()
            part:SetPoint("CENTER", frame, right and "TOPLEFT" or "TOPRIGHT", 0, -(y + TILE_HEIGHT / 2 - top))
        end
    end

    local shownID, current, currentIndex
    local function drawList(list, index)
        current, currentIndex = list, index
        if list.appearance.id ~= shownID then offset, shownID = 0, list.appearance.id end
        -- the head's texts first: the pending sentence's height sizes the head
        typeText:SetText(list.typeText)
        local marked = list.collected or list.pendingText ~= nil
        collectedText:SetShown(marked)
        if list.collected then
            collectedText:SetWidth(0)
            collectedText:SetText("Collected")
            -- GREEN_FONT_COLOR (visual pass, board 8)
            collectedText:SetTextColor(0.1, 1, 0.1)
        elseif marked then
            collectedText:SetWidth(HEAD_TEXT_WIDTH)
            collectedText:SetText(list.pendingText)
            collectedText:SetTextColor(1, 1, 1)
        end
        local head = FLY_HEAD
        if list.pendingText and not list.collected then
            local lines = collectedText.GetStringHeight and collectedText:GetStringHeight()
            if type(lines) ~= "number" or lines <= 0 then lines = HEAD_LINES_MAX * HEAD_LINE end
            head = head + math.max(0, lines - HEAD_LINE)
        end
        local height
        shown, height = flyoutSize(list, head)
        count = #list.rows
        offset = math.max(0, math.min(offset, count - shown))
        place(index, height)
        show(frame, "weaponModel", model, list.appearance, list.weapon, function()
            return newWeaponModel(frame, 10, -8, HEAD_MODEL_WIDTH, HEAD_MODEL_HEIGHT)
        end)
        if modelEdge then setAtlas(modelEdge, list.collected and EDGE_COLLECTED_ATLAS or EDGE_ATLAS) end
        headLine:ClearAllPoints()
        headLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(head - 1))
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -head)
        collectedCheck:SetShown(list.collected)
        local checking = list.state == "checking"
        if spinner then spinner:SetShown(checking) end
        local above = marked and collectedText or typeText
        local indent = (checking and spinner) and 20 or 0
        if spinner then
            spinner:ClearAllPoints()
            spinner:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2)
        end
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", above, "BOTTOMLEFT", indent, -3)
        title:SetWidth(HEAD_TEXT_WIDTH - indent)
        title:SetText(list.title or "")
        text:SetText(list.text or "")
        local rowsTop = head + (list.text and FLY_TEXT or 0)
        for i, row in ipairs(rows) do
            local shownRow = i <= shown and list.rows[offset + i]
            row:SetShown(shownRow and true or false)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(rowsTop + (i - 1) * FLY_ROW))
            if shownRow then
                local buy = shownRow.buy
                row.buy:SetShown(buy ~= nil)
                if buy then row.buy:SetEnabled(buy.enabled) end
                row.price:ClearAllPoints()
                if buy then
                    row.price:SetPoint("RIGHT", row.buy, "LEFT", -TOOLS_GAP, 0)
                else
                    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -22)
                end
                setName(row.name, shownRow.name, shownRow.quality)
                row.forSale:SetText(checking and "-" or shownRow.forSale or "")
                row.price:SetText(shownRow.money and moneyMarkup(shownRow.money) or "")
            end
        end
        local scrolls = count > shown
        thumb:SetShown(scrolls)
        track:SetShown(scrolls)
        fade:SetShown(scrolls and offset + shown < count)
        if scrolls then
            local length = shown * FLY_ROW
            thumb:SetHeight(length * shown / count)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(rowsTop + length * offset / count))
            track:ClearAllPoints()
            track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -rowsTop)
            track:SetHeight(length)
            fade:ClearAllPoints()
            fade:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 10, -(rowsTop + length))
        end
        ageText:SetText(list.foot.age or "")
        note:SetText(list.foot.note or "")
        again:SetText(list.foot.button or "")
        again:SetShown(list.foot.button ~= nil)
        again:SetEnabled(list.foot.enabled)
    end
    -- the wheel over the flyout scrolls its rows, not the pages
    function scroll(delta)
        local was = offset
        offset = math.max(0, math.min(offset - delta, count - shown))
        if offset ~= was and current then drawList(current, currentIndex) end
    end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) scroll(delta) end)
    local sinceDraw = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        sinceDraw = sinceDraw + (elapsed or 0)
        if sinceDraw >= AGE_REDRAW and current then
            sinceDraw = 0
            drawList(State.View().list or current, currentIndex)
        end
    end)
    -- the click event is listened to only while the flyout is shown
    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        takeKeyboard(self)
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        setKeyboard(self, false)
    end)
    frame:SetScript("OnKeyDown", function(self, key)
        local escape = key == "ESCAPE" and not (TC.Buy and TC.Buy.IsOpen())
        if canPropagate(self) then self:SetPropagateKeyboardInput(not escape) end
        if escape then State.CloseList() end
    end)
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(self, event, button)
        if event == "PLAYER_REGEN_DISABLED" then return setKeyboard(self, false) end
        if button ~= "LeftButton" then return end
        if self:IsVisible() and not self:IsMouseOver() and not overTile() and not (TC.Buy and TC.Buy.IsOpen()) then
            State.CloseList()
        end
    end)
    takeKeyboard(frame)
    frame:Hide() -- built shown; the caller shows it, which registers the click event
    frame.draw = drawList
    return frame
end

-- A dropdown from Blizzard's menu templates (Blizzard_Menu/Mainline/
-- MenuTemplates.xml:3-39 and :66-117; Classic/MenuTemplates.xml has the same
-- names), made from Lua as Blizzard_Menu/11_0_0_MenuImplementationGuide.lua:107
-- shows, in the width of the button it replaces (and its height, unless none is
-- given: then the template's own). The client's own menu
-- opens on a press and is filled by fill(root) each time it opens
-- (DropdownButton.lua:100-131, 237-264). Nil when the client lacks the
-- template or the menu API (SetupMenu, CloseMenu, the text setter), so the
-- caller keeps its own button and menu. That this client gives addons
-- these templates is inferred from its auction house and Collections using
-- them (Blizzard_AuctionHouseSearchBar.xml:19, SellFrame.xml:126,
-- Blizzard_Wardrobe.xml:405-438), unverified in game.
local function menuDropdown(parent, template, width, height, setText, fill)
    local ok, button = pcall(CreateFrame, "DropdownButton", nil, parent, template)
    if not (ok and button) then return nil end
    if not (button.SetupMenu and button.CloseMenu and button[setText] and button.Text) then
        button:Hide()
        return nil
    end
    -- as Collections sets its Filter (Blizzard_Wardrobe.xml:405-412)
    button.resizeToText = false
    if height then button:SetSize(width, height) else button:SetWidth(width) end
    if not pcall(button.SetupMenu, button, function(_, root) fill(root) end) then
        button:Hide()
        return nil
    end
    button.close = function() button:CloseMenu() end
    return button
end

-- The menu of a button without Blizzard's menu: a list under the button's
-- side corner. fill(items) lists { text, action, enabled, line }: line puts
-- a line above the entry; a chosen entry hides the menu and runs action.
local function listMenu(panel, button, width, side)
    local menu = CreateFrame("Frame", nil, panel)
    menu:SetFrameStrata("DIALOG")
    local background = menu:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    menu:SetPoint("TOP" .. side, button, "BOTTOM" .. side, 0, -2)
    menu:Hide()
    local entries, lines = {}, {}
    function menu.fill(items)
        local y = -4
        for i, item in ipairs(items) do
            local line = lines[i]
            if item.line then
                if not line then
                    line = menu:CreateTexture(nil, "ARTWORK")
                    line:SetSize(width - 16, 1)
                    line:SetColorTexture(unpack(BORDER))
                    lines[i] = line
                end
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y - 4)
                line:Show()
                y = y - 8
            elseif line then
                line:Hide()
            end
            local entry = entries[i]
            if not entry then
                entry = CreateFrame("Button", nil, menu)
                entry:SetSize(width - 8, 20)
                if GameFontHighlightSmall then entry:SetNormalFontObject(GameFontHighlightSmall) end
                entry:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                entry:SetScript("OnClick", function(self)
                    menu:Hide()
                    self.action()
                end)
                entries[i] = entry
            end
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
            entry:SetText(item.text)
            entry:SetEnabled(item.enabled ~= false)
            entry.action = item.action
            entry:Show()
            y = y - 20
        end
        for i = #items + 1, #entries do
            entries[i]:Hide()
            if lines[i] then lines[i]:Hide() end
        end
        menu:SetSize(width, 8 - y)
    end
    button.menu = menu
    button.close = function() menu:Hide() end
    return menu
end

-- The slot row: one round button per slot of TC.Slots, in its groups, with
-- Collections' art, its highlight and its gold ring on the chosen slot, and
-- the slot's name on hover. Built as Collections' template is, not from the
-- template, whose click handler drives Collections' own frame.
local function newSlotRow(panel)
    local buttons, x = {}, SLOTS_X
    for i, slot in ipairs(TC.Slots) do
        if i > 1 then x = x + (slot.group ~= TC.Slots[i - 1].group and GROUP_GAP or SLOT_GAP) end
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(SLOT_SIZE, SLOT_SIZE)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -SLOTS_Y)
        x = x + SLOT_SIZE
        local art = button:CreateTexture(nil, "ARTWORK")
        art:SetPoint("CENTER")
        setAtlas(art, SLOT_ART:format(slot.art), true)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetSize(SLOT_SIZE, SLOT_SIZE)
        highlight:SetPoint("CENTER", button, "CENTER", 0, 1)
        setAtlas(highlight, SLOT_HIGHLIGHT)
        highlight:SetBlendMode("ADD")
        button.ring = button:CreateTexture(nil, "OVERLAY")
        button.ring:SetPoint("CENTER")
        setAtlas(button.ring, SLOT_SELECTED, true)
        button.slot = slot.key
        button:SetScript("OnClick", function() State.SelectSlot(slot.key) end)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(slot.name)
        end)
        button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        buttons[i] = button
    end
    return buttons
end

-- A text in a class's colour (GetClassColor, Blizzard_SharedXML/ColorUtil.lua:66-73),
-- or plain without a class.
local function inClassColour(text, classFile)
    if not (classFile and GetClassColor) then return text end
    local _, _, _, colour = GetClassColor(classFile)
    return colour and ("|c" .. colour .. text .. "|r") or text
end

-- The weapon type dropdown: the entries the state answers, the first entry
-- ("All weapon types") with a line under it; choosing an entry calls
-- pick(value). Blizzard's dropdown, its menu built as Collections' weapon
-- menu is (radios, the chosen one marked, Blizzard_Wardrobe.lua:877-891);
-- its text is the state's, not the chosen radio's. Without it, a button that
-- opens a list under its right edge. It is hidden on armor slots.
local function newDropdown(panel, width, pick)
    local current
    local dropdown = menuDropdown(panel, "WowStyle1DropdownTemplate", width, nil, "OverrideText", function(root)
        for i, shown in ipairs(current and current.entries or {}) do
            root:CreateRadio(shown.name, function(entry) return entry ~= nil and entry.selected end,
                function(entry) if entry then pick(entry.value) end end, shown)
            if i == 1 then root:CreateDivider() end
        end
    end)
    if dropdown then
        function dropdown.draw(answer)
            current = answer
            dropdown:SetShown(answer ~= nil)
            if not answer then return dropdown:CloseMenu() end
            dropdown:OverrideText(answer.text)
        end
        return dropdown
    end
    local menu
    local button = newButton(panel, "", width, WEAPON_HEIGHT, function() menu:SetShown(not menu:IsShown()) end)
    menu = listMenu(panel, button, width, "RIGHT")
    function button.draw(answer)
        button:SetShown(answer ~= nil)
        if not answer then return menu:Hide() end
        button:SetText(answer.text)
        local items = {}
        for i, shown in ipairs(answer.entries) do
            items[i] = { text = shown.name, line = i == 2, action = function() pick(shown.value) end }
        end
        menu.fill(items)
    end
    return button
end

-- The funnel (layout B, 1.3, slice B): the Show choices (the Filter); For
-- sale only; the Source entries and the class as submenus; the sort's
-- three choices; Scan when shown; then "Reset filters" while Reset would
-- change something. Blizzard's filter dropdown
-- (WowStyle1FilterDropdownTemplate) drawn with the world map's filter art
-- when the client has it; its menu is filled from the view at each opening
-- (a button with radios under it is a submenu,
-- 11_0_0_MenuImplementationGuide.lua:24-32, 57-68; CreateCheckbox and
-- CreateTitle, MenuTemplates.lua:294-303, 369-382). A checkbox keeps the
-- menu open (MenuResponse.Refresh, Menu.lua:2353-2360), which asks its
-- selected state again: it reads the view drawn last, never the entry the
-- menu was built with. Without the template or its menu API, a button that
-- opens a list of the same entries, each checkbox marked by its text;
-- without the art, either reads "Filter". The reset mark at its top left
-- shows while Reset would change something.
local function newFunnel(panel)
    local current
    local function selected(entry) return entry ~= nil and entry.selected end
    local function pickShow(entry) if entry then State.SetFilter(entry.value) end end
    local function pickClass(entry) if entry then State.SelectClass(entry.value) end end
    local function pickSort(entry) if entry then State.SetSort(entry.value) end end
    local function forSaleOnly() return current ~= nil and current.forSaleOnly end
    local function toggleForSale() State.SetForSaleOnly(not forSaleOnly()) end
    local function scanWhenShown() return current ~= nil and current.scanWhenShown end
    local function toggleScan() State.SetScanWhenShown(not scanWhenShown()) end
    local function sourceTicked(key)
        for _, entry in ipairs(current and current.sources or {}) do
            if entry.value == key then return entry.selected end
        end
        return false
    end
    local function toggleSource(key) State.SetSource(key, not sourceTicked(key)) end
    local funnel = menuDropdown(panel, "WowStyle1FilterDropdownTemplate", FUNNEL_SIZE, FUNNEL_SIZE, "SetText",
        function(root)
            if not current then return end
            for _, entry in ipairs(current.filters) do root:CreateRadio(entry.name, selected, pickShow, entry) end
            root:CreateDivider()
            root:CreateCheckbox(FOR_SALE_TEXT, forSaleOnly, toggleForSale)
            local sources = root:CreateButton(SOURCE_TEXT)
            for _, entry in ipairs(current.sources) do sources:CreateCheckbox(entry.name, sourceTicked, toggleSource, entry.value) end
            local classes = current.classes
            local submenu = root:CreateButton(CLASS_TEXT:format(inClassColour(classes.text, classes.classFile)))
            for i, entry in ipairs(classes.entries) do
                submenu:CreateRadio(inClassColour(entry.name, entry.classFile), selected, pickClass, entry)
                if i == 1 then submenu:CreateDivider() end
            end
            root:CreateDivider()
            if root.CreateTitle then root:CreateTitle(SORT_TEXT) end
            for _, entry in ipairs(current.sorts) do root:CreateRadio(entry.name, selected, pickSort, entry) end
            root:CreateDivider()
            root:CreateCheckbox(SCAN_SHOWN_TEXT, scanWhenShown, toggleScan)
            if current.filtersChanged then
                root:CreateDivider()
                root:CreateButton(RESET_TEXT, State.ResetFilters)
            end
        end)
    local menu
    if not funnel then
        funnel = newButton(panel, "", FUNNEL_SIZE, FUNNEL_SIZE, function() menu:SetShown(not menu:IsShown()) end)
        menu = listMenu(panel, funnel, 170, "RIGHT")
    end
    funnel:SetPoint("TOPLEFT", panel, "TOPLEFT", FUNNEL_X, -FUNNEL_Y)
    -- the owner's art, else the world map's filter art, else the text
    local art = hasAtlas(FUNNEL_ATLAS) and FUNNEL_ATLAS or hasAtlas(FUNNEL_FALLBACK) and FUNNEL_FALLBACK or nil
    funnel:SetText(art and "" or FUNNEL_TEXT)
    if art then
        -- the template's dropdown art (MenuTemplates.xml:91) gives way to the funnel's
        if not menu and funnel.Background then funnel.Background:SetAlpha(0) end
        local icon = funnel:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetAtlas(art)
        funnel.icon = icon
        -- the settings button's forms, as DamageMeterSettingsDropdownButton.lua:
        -- 7-26 picks them (.xml:5-10), each where the client has its atlas
        -- (else the next plainer one): pressed with the pointer over it,
        -- hover, pressed (until the mouse is released, wherever), open while
        -- its menu is open, else normal. A Blizzard dropdown tells of its menu
        -- through OnMenuOpened and OnMenuClosed, which Blizzard's button
        -- overrides the same way; our own list menu through its shown state.
        if art == FUNNEL_ATLAS then
            local function form(atlas, instead) return hasAtlas(atlas) and atlas or instead end
            local hover, pressed = form(FUNNEL_HOVER, art), form(FUNNEL_PRESSED, art)
            local pressedHover, open = form(FUNNEL_PRESSED_HOVER, pressed), form(FUNNEL_OPEN, art)
            local over, down = false, false
            local function paint()
                local isOpen = funnel.IsMenuOpen and funnel:IsMenuOpen() or (menu ~= nil and menu:IsShown())
                icon:SetAtlas(down and over and pressedHover or over and hover or down and pressed or isOpen and open or art)
            end
            funnel:HookScript("OnEnter", function() over = true paint() end)
            funnel:HookScript("OnLeave", function() over = false paint() end)
            funnel:HookScript("OnMouseDown", function() down = true paint() end)
            funnel:HookScript("OnMouseUp", function() down = false paint() end)
            funnel:HookScript("OnShow", function() over, down = false, false paint() end)
            if menu then
                menu:HookScript("OnShow", paint)
                menu:HookScript("OnHide", paint)
            else
                for _, name in ipairs({ "OnMenuOpened", "OnMenuClosed" }) do
                    local base = funnel[name]
                    funnel[name] = function(self, ...)
                        if base then base(self, ...) end
                        paint()
                    end
                end
            end
        end
    end
    funnel:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(FUNNEL_TIP)
        GameTooltip:Show()
    end)
    funnel:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    local mark = CreateFrame("Button", nil, funnel)
    mark:SetSize(MARK_SIZE, MARK_SIZE)
    mark:SetPoint("CENTER", funnel, "TOPRIGHT", MARK_X, MARK_Y)
    local markArt = mark:CreateTexture(nil, "ARTWORK")
    markArt:SetAllPoints()
    if hasAtlas(RESET_ATLAS) then markArt:SetAtlas(RESET_ATLAS) else markArt:SetColorTexture(0.7, 0.1, 0.05, 1) end
    mark:SetScript("OnClick", State.ResetFilters)
    tooltip(mark, RESET_TEXT)
    function funnel.draw(view)
        current = view
        mark:SetShown(view.filtersChanged)
        -- the button itself looks active while a choice differs from the start
        if funnel.LockHighlight then
            if view.filtersChanged then funnel:LockHighlight() else funnel:UnlockHighlight() end
        end
        if not menu then return end
        local function mark(on) return on and TICKED or UNTICKED end
        local items = {}
        for _, entry in ipairs(view.filters) do
            items[#items + 1] = { text = entry.name, action = function() State.SetFilter(entry.value) end }
        end
        items[#items + 1] = { text = mark(view.forSaleOnly) .. FOR_SALE_TEXT, line = true, action = toggleForSale }
        for _, entry in ipairs(view.sources) do
            items[#items + 1] = { text = mark(entry.selected) .. SOURCE_TEXT .. ": " .. entry.name,
                action = function() State.SetSource(entry.value, not entry.selected) end }
        end
        for i, entry in ipairs(view.classes.entries) do
            items[#items + 1] = { text = inClassColour(entry.name, entry.classFile), line = i <= 2,
                action = function() State.SelectClass(entry.value) end }
        end
        for i, entry in ipairs(view.sorts) do
            items[#items + 1] = { text = SORT_TEXT .. ": " .. entry.name, line = i == 1,
                action = function() State.SetSort(entry.value) end }
        end
        items[#items + 1] = { text = mark(view.scanWhenShown) .. SCAN_SHOWN_TEXT, line = true, action = toggleScan }
        if view.filtersChanged then items[#items + 1] = { text = RESET_TEXT, line = true, action = State.ResetFilters } end
        menu.fill(items)
    end
    return funnel
end

-- The Search box (spec 2.2, 2.3): Blizzard's SearchBoxTemplate
-- (Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:209-257), whose
-- Escape and Enter only clear the focus (EditBox_ClearFocus,
-- InputBoxTemplates.lua:9-11), so Escape does not close the auction window;
-- that the client sends Escape to a focused edit box first is read from
-- that template, not run in game. Without the template, a bare edit box
-- with the same handlers and its own placeholder. Every text change goes to
-- the state, which ignores the text it has.
local SEARCH_WIDTH, SEARCH_HEIGHT, SEARCH_TEXT = 108, 20, "Search"
local function newSearchBox(panel)
    local box = templated("EditBox", panel, "SearchBoxTemplate")
    local placeholder
    if box and type(box.Instructions) == "table" then
        box.Instructions:SetText(SEARCH_TEXT)
    else
        box = box or CreateFrame("EditBox", nil, panel)
        if box.SetAutoFocus then box:SetAutoFocus(false) end
        if GameFontHighlightSmall and box.SetFontObject then box:SetFontObject(GameFontHighlightSmall) end
        box:SetScript("OnEscapePressed", box.ClearFocus)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        placeholder:SetPoint("LEFT", box, "LEFT", 4, 0)
        placeholder:SetText(SEARCH_TEXT)
    end
    box:SetSize(SEARCH_WIDTH, SEARCH_HEIGHT)
    box:SetScript("OnTextChanged", function(self)
        if placeholder == nil and SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        if placeholder then placeholder:SetShown(self:GetText() == "") end
        State.SetSearch(self:GetText() or "")
    end)
    -- the state's text, as Clear search or a new visit leaves it
    function box.draw(text)
        if box:GetText() ~= text then box:SetText(text) end
    end
    return box
end

-- Builds the browser inside the tab's panel, draws whenever the state's
-- answer changes, and answers the draw function.
local function buildBrowser(panel)
    local slotButtons = newSlotRow(panel)
    local search = newSearchBox(panel)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", SEARCH_X, -SEARCH_Y)
    local funnel = newFunnel(panel)
    local weaponType = newDropdown(panel, WEAPON_WIDTH, State.SelectWeaponType)
    weaponType:SetPoint("LEFT", panel, "TOPLEFT", WEAPON_X, -WEAPON_CENTRE)

    -- the inset under the grid, the status line and paging; without the
    -- template the bare window background, as before
    local inset = templated("Frame", panel, "CollectionsBackgroundTemplate")
    if inset then
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -INSET_Y)
        inset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        for _, key in ipairs(INSET_CORNERS) do
            if type(inset[key]) == "table" and inset[key].Hide then inset[key]:Hide() end
        end
    end
    -- The inset sits at the panel's own frame level (useParentLevel,
    -- SharedUIPanelTemplates.xml:389), where a font string or texture of the
    -- panel itself has no order against it. So every text and texture of
    -- ours over it is on this plain frame above it, which takes no mouse.
    local content = CreateFrame("Frame", nil, panel)
    content:SetAllPoints(panel)
    content:SetFrameLevel(math.max(panel:GetFrameLevel(), inset and inset:GetFrameLevel() or 0) + 1)
    local count = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetPoint("TOPLEFT", panel, "TOPLEFT", COUNT_X, -COUNT_Y)

    local grid = CreateFrame("Frame", nil, panel)
    grid:SetPoint("TOPLEFT", panel, "TOPLEFT", GRID_X, -GRID_Y)
    grid:SetSize(COLUMNS * TILE_WIDTH + (COLUMNS - 1) * GAP_X, ROWS * TILE_HEIGHT + (ROWS - 1) * GAP_Y)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta) State.Wheel(delta) end)
    local function clickTile(tile)
        if tile.appearance then State.ClickTile(tile.appearance) end
    end
    -- The tile under the pointer: its hover glow and its tooltip (board 7),
    -- built from the state's lines on entering and on each draw, never per
    -- frame. hoverID: the appearance it showed on entering; a draw that finds
    -- another (a page turn) ends the hover. No tooltip while its flyout is open.
    local hovered, hoverID, tipShown, tipOwner
    -- hides the tooltip only while it is ours: another frame may own it by now
    local function hideTip()
        if tipShown and GameTooltip and not (GameTooltip.GetOwner and GameTooltip:GetOwner() ~= tipOwner) then
            if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(0, false) end
            GameTooltip:Hide()
        end
        tipShown = false
    end
    local function showTip(tile)
        if not GameTooltip or tile.isOpen then return hideTip() end
        tipOwner = tile.button
        GameTooltip:SetOwner(tile.button, "ANCHOR_RIGHT")
        -- the sentences wrap (AddLine's wrap, as GameTooltip_AddColoredLine
        -- passes it, SharedTooltipTemplates.lua:166-172) at no less than the
        -- minimum width, given back on hiding as the achievement frame does
        -- (Blizzard_AchievementUI.lua:638-640, 798-799)
        if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(TIP_MIN_WIDTH) end
        for _, line in ipairs(State.TileTooltip(tile.appearance)) do
            local c = line.color or TEXT_WHITE
            if line.right then
                local r = line.rightColor or c
                GameTooltip:AddDoubleLine(line.text, line.money and moneyMarkup(line.money) or line.right,
                    c[1], c[2], c[3], r[1], r[2], r[3])
            else
                GameTooltip:AddLine(line.text, c[1], c[2], c[3], line.wrap)
            end
        end
        GameTooltip:Show()
        tipShown = true
    end
    local function endHover()
        if not hovered then return end
        hovered.hovered = false
        drawMarkers(hovered)
        hovered, hoverID = nil, nil
        hideTip()
    end
    local function enterTile(tile)
        if not tile.appearance then return end
        endHover()
        hovered, hoverID = tile, tile.appearance.id
        tile.hovered = true
        drawMarkers(tile)
        showTip(tile)
    end
    local function leaveTile(tile)
        if hovered == tile then endHover() end
    end
    local art = tileArt()
    local tiles = {}
    for i = 1, COLUMNS * ROWS do
        tiles[i] = newTile(grid, i, art, clickTile, State.Wheel, enterTile, leaveTile)
    end
    -- a click on a tile is the tile's own, not a click outside the flyout
    local function overTile()
        for _, tile in ipairs(tiles) do
            if tile:IsVisible() and tile.button:IsMouseOver() then return true end
        end
        return false
    end
    local flyout

    -- the empty state: a heading in GameFontNormalMed3 (FontStyles.xml:278),
    -- or GameFontNormalLarge as before without it, and the sentence in
    -- GameFontHighlight (visual pass, board 10)
    local emptyTitle = grid:CreateFontString(nil, "OVERLAY", GameFontNormalMed3 and "GameFontNormalMed3" or "GameFontNormalLarge")
    emptyTitle:SetPoint("TOP", grid, "TOP", 0, -120)
    local emptyText = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -8)
    local emptyAction
    local showAll = newButton(grid, "", 160, 22, function()
        if emptyAction then emptyAction() end
    end)
    showAll:SetPoint("TOP", emptyText, "BOTTOM", 0, -12)

    -- paging at the right of the status line: the wheel mark, the page text
    -- and the arrows; hidden with one page
    local paging = CreateFrame("Frame", nil, panel)
    paging:SetSize(200, 24)
    paging:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -GRID_X, -PAGING_Y)
    local previous = arrowButton(paging, "Prev", State.PreviousPage, PREVIOUS_TIP)
    local nextPage = arrowButton(paging, "Next", State.NextPage, NEXT_TIP)
    nextPage:SetPoint("RIGHT", paging, "RIGHT", 0, 0)
    previous:SetPoint("RIGHT", nextPage, "LEFT", -TOOLS_GAP, 0)
    -- Collections' page text font (CollectionsPageTextTemplate,
    -- Blizzard_Collections/Shared/Blizzard_CollectionTemplates.xml:193)
    local pageText = paging:CreateFontString(nil, "OVERLAY", GameFontWhite and "GameFontWhite" or "GameFontHighlight")
    pageText:SetPoint("RIGHT", previous, "LEFT", -TOOLS_GAP - 5, 0)
    pageText:SetJustifyH("RIGHT")
    -- one line, never wrapped (SimpleFontStringAPIDocumentation.lua:720)
    pageText:SetWordWrap(false)
    -- the widest form of the page text seen, whose width the text keeps
    local widestPage
    -- the wheel mark, the addon's art, with its own tooltip
    local wheelMark = CreateFrame("Frame", nil, paging)
    wheelMark:SetSize(WHEEL_WIDTH, WHEEL_HEIGHT)
    wheelMark:SetPoint("RIGHT", pageText, "LEFT", -7, 0)
    wheelMark:EnableMouse(true)
    tooltip(wheelMark, WHEEL_TIP)
    -- the page text shows the wheel mark's tooltip too (testpass F2): a font
    -- string takes no pointer, so a frame over it does
    local pageHover = CreateFrame("Frame", nil, paging)
    pageHover:SetPoint("TOPLEFT", pageText, "TOPLEFT", 0, 0)
    pageHover:SetPoint("BOTTOMRIGHT", pageText, "BOTTOMRIGHT", 0, 0)
    pageHover:EnableMouse(true)
    tooltip(pageHover, WHEEL_TIP)
    local wheelArt = wheelMark:CreateTexture(nil, "ARTWORK")
    wheelArt:SetAllPoints()
    wheelArt:SetTexture(MEDIA .. "wheel")

    -- the status line: one button, always first at the grid's left edge, its
    -- text after it, and a progress bar while a scan runs
    local status = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetHeight(24)
    status:SetJustifyH("LEFT")
    local statusAction
    local statusButton = newButton(panel, "", STATUS_BUTTON, 20, function()
        if statusAction then statusAction() end
    end)
    tooltip(statusButton, SCAN_TIP)
    statusButton:SetPoint("TOPLEFT", panel, "TOPLEFT", GRID_X, -STATUS_Y - 2)
    -- the scan glyph left of the button's text, the text moved right by
    -- half the glyph so the pair stays centred; without the atlas text only
    if hasAtlas(SCAN_ATLAS) then
        local glyph = statusButton:CreateTexture(nil, "OVERLAY")
        glyph:SetSize(SCAN_GLYPH, SCAN_GLYPH)
        setAtlas(glyph, SCAN_ATLAS)
        local label = statusButton.GetFontString and statusButton:GetFontString()
        if type(label) == "table" then
            label:ClearAllPoints()
            label:SetPoint("CENTER", statusButton, "CENTER", (SCAN_GLYPH + 2) / 2, 0)
            glyph:SetPoint("RIGHT", label, "LEFT", -2, 0)
        else
            glyph:SetPoint("LEFT", statusButton, "LEFT", 6, 0)
        end
        statusButton.glyph = glyph
    end
    -- the progress bar: the black back, the gold bar texture and the border
    local progress = content:CreateTexture(nil, "ARTWORK")
    progress:SetSize(PROGRESS_WIDTH, PROGRESS_HEIGHT)
    progress:SetPoint("LEFT", status, "RIGHT", TOOLS_GAP, 0)
    progress:SetColorTexture(unpack(PROGRESS_BACK))
    local progressFill = content:CreateTexture(nil, "ARTWORK", nil, 1)
    progressFill:SetHeight(PROGRESS_HEIGHT)
    progressFill:SetPoint("LEFT", progress, "LEFT", 0, 0)
    progressFill:SetTexture(PROGRESS_BAR)
    progressFill:SetVertexColor(unpack(PROGRESS_COLOR))
    -- left, right and centre of the border, as Blizzard_Wardrobe.xml:362-387
    local progressBorder = {}
    for i, part in ipairs({ { 0, 0.0625, "LEFT", -6 }, { 0.812, 0.8745, "RIGHT", 6 }, { 0.0625, 0.812 } }) do
        local texture = content:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(PROGRESS_BORDER)
        texture:SetTexCoord(part[1], part[2], 0, 0.75)
        if part[3] then
            texture:SetWidth(16)
            texture:SetPoint("TOP" .. part[3], progress, "TOP" .. part[3], part[4], 5)
            texture:SetPoint("BOTTOM" .. part[3], progress, "BOTTOM" .. part[3], part[4], -5)
        else
            texture:SetPoint("TOPLEFT", progressBorder[1], "TOPRIGHT")
            texture:SetPoint("BOTTOMRIGHT", progressBorder[2], "BOTTOMLEFT")
        end
        progressBorder[i] = texture
    end
    local statusFonts = { hint = GameFontDisableSmall, state = GameFontHighlightSmall }

    local function draw()
        local view = State.View()
        count:SetText(view.count)
        for i, button in ipairs(slotButtons) do button.ring:SetShown(view.slots[i].selected) end
        weaponType.draw(view.weaponTypes)
        funnel.draw(view)
        search.draw(view.search)
        local openIndex
        for i, tile in ipairs(tiles) do
            local shown = view.tiles[i]
            if shown then
                tile:Show()
                drawTile(tile, shown)
                if shown.open then openIndex = i end
            else
                tile.appearance = nil
                tile:Hide()
            end
        end
        if view.list and openIndex and not flyout then
            flyout = newFlyout(panel, grid:GetFrameLevel() + 10, overTile)
        end
        if flyout then
            flyout:SetShown(view.list ~= nil and openIndex ~= nil)
            if view.list and openIndex then flyout.draw(view.list, openIndex) end
        end
        local empty = view.empty
        emptyTitle:SetText(empty and empty.title or "")
        emptyText:SetText(empty and empty.text or "")
        showAll:SetText(empty and empty.button or "")
        showAll:SetShown(empty ~= nil and empty.button ~= nil)
        emptyAction = empty and empty.action
        -- the room of the page text is that of its widest form for the page
        -- count, so nothing left of it moves while the page changes
        if view.pageTextWidest ~= widestPage and pageText.GetStringWidth then
            widestPage = view.pageTextWidest
            pageText:SetText(widestPage)
            local width = pageText:GetStringWidth()
            if width and width > 0 then pageText:SetWidth(math.ceil(width) + PAGE_ROOM) end
        end
        pageText:SetText(view.pageText)
        previous:SetEnabled(view.previousEnabled)
        nextPage:SetEnabled(view.nextEnabled)
        paging:SetShown(view.paging)
        status:SetText(view.status)
        statusButton:SetText(view.statusButton or "")
        statusButton:SetShown(view.statusButton ~= nil)
        statusButton:SetEnabled(view.statusEnabled ~= false)
        statusAction = view.statusAction
        status:ClearAllPoints()
        status:SetPoint("TOPLEFT", panel, "TOPLEFT", view.statusButton and (GRID_X + STATUS_BUTTON + TOOLS_GAP) or GRID_X,
            -STATUS_Y)
        -- the hint in the advice font, a state in the state font
        local font = view.statusHint and statusFonts.hint or statusFonts.state
        if font and status.SetFontObject then status:SetFontObject(font) end
        progress:SetShown(view.progress ~= nil)
        for _, part in ipairs(progressBorder) do part:SetShown(view.progress ~= nil) end
        progressFill:SetShown((view.progress or 0) > 0)
        progressFill:SetWidth(math.max(1, PROGRESS_WIDTH * (view.progress or 0)))
        -- the hover ends when its tile shows another appearance or none (a
        -- page turn); its tooltip hides while its flyout is open and follows
        -- what the state answers otherwise
        if hovered then
            if not hovered:IsVisible() or not hovered.appearance or hovered.appearance.id ~= hoverID then
                endHover()
            else
                showTip(hovered)
            end
        end
    end
    State.SetListener(draw)
    -- the buy dialog belongs to the panel and hides with it
    TC.Buy.Attach(panel)

    -- Leaving the tab stops a running check or scan (A6).
    panel:SetScript("OnHide", function()
        endHover()
        funnel.close()
        weaponType.close()
        if search.ClearFocus then search:ClearFocus() end
        -- the bags are read only while the tab is shown (TC-39)
        panel:UnregisterEvent("BAG_UPDATE_DELAYED")
        State.Leave()
    end)
    return draw
end

-- Blizzard_AuctionHouseUI loads on demand, so AuctionHouseFrame exists only
-- once the auction house window has been opened. The library asserts that it
-- does and errors on a repeated id, hence one attempt, made when both the
-- library and the frame are there.
local opener = CreateFrame("Frame")
opener:RegisterEvent("AUCTION_HOUSE_SHOW")
opener:SetScript("OnEvent", function(self)
    -- LibStub(name, true) gives nil instead of an error for a missing library.
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if not (lib and lib.CreateTab and lib.DoesIDExist and AuctionHouseFrame) then return end
    self:UnregisterEvent("AUCTION_HOUSE_SHOW")
    if lib:DoesIDExist(TAB_ID) then return end

    -- The box Blizzard's own Auctions panel fills. The library shows the
    -- panel when the tab is selected and hides it when another tab is.
    local panel = CreateFrame("Frame", nil, AuctionHouseFrame)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 5, -42)
    panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 27)
    lib:CreateTab(TAB_ID, panel, TAB_TEXT, WINDOW_TITLE)

    -- The browser is built, and the collection read, only once the player
    -- selects the tab; the library shows the panel then. Collected is read
    -- again whenever the panel is shown and when the client reports a change
    -- to the collection; which event fires for that on Forever is unverified
    -- (spec section 3).
    local draw
    panel:SetScript("OnShow", function()
        local first = not draw
        if first then draw = buildBrowser(panel) end
        -- the bags' items, read now and on each BAG_UPDATE_DELAYED (once
        -- after a batch of bag changes, ContainerDocumentation.lua:673-677)
        -- while the tab is shown (TC-39)
        panel:RegisterEvent("BAG_UPDATE_DELAYED")
        State.SetBags(TC.Appearances.ReadBags())
        -- the first draw, also when there is no list to tell of
        if not State.Refresh() and first then draw() end
        -- with Scan when shown on, the slot is scanned unless it has a kept
        -- scan, and a scan stopped by leaving the tab runs again (A6)
        State.Enter()
    end)
    panel:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
    panel:RegisterEvent("AUCTION_HOUSE_CLOSED")
    -- An item variant's name arrives after the check (spec 4.1); the list
    -- shows it once it is there.
    panel:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
    -- Search with For sale only asks for every found variant's name, so the names
    -- can arrive by the hundred: they redraw once per frame.
    local keyWait = false
    panel:SetScript("OnEvent", function(self, event, itemID)
        if event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
            -- the state reads the keys of that item once more
            State.KeyInfoReceived(itemID)
            if not (draw and self:IsShown()) or keyWait then return end
            if not (C_Timer and C_Timer.After) then return draw() end
            keyWait = true
            C_Timer.After(0, function()
                keyWait = false
                if self:IsShown() then draw() end
            end)
        elseif event == "AUCTION_HOUSE_CLOSED" then
            -- Closing ends the visit. A panel left shown may get OnShow as
            -- the window opens again, before Blizzard puts the window on Buy
            -- and the library hides it (the client's order is unverified),
            -- so it is hidden here.
            self:Hide()
            State.Reset()
        elseif event == "BAG_UPDATE_DELAYED" then
            if self:IsShown() then State.SetBags(TC.Appearances.ReadBags()) end
        elseif self:IsShown() then
            State.Refresh()
        end
    end)
end)
