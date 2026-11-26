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
-- The grid is always 8 columns of 3 rows; it never moves.
local COLUMNS, ROWS = 8, 3
local GRID_X, GRID_Y = 28, 80
local TILE_WIDTH, TILE_HEIGHT = 78, 104
local GAP_X, GAP_Y = 16, 24
local MODEL_HEIGHT, STRIP_HEIGHT = 82, 20
local CHECK_SIZE = 16
local BORDER = { 0.25, 0.25, 0.25, 1 }
local BORDER_COLLECTED = { 0.1, 0.8, 0.1, 1 }
local BORDER_OPEN = { 1, 0.82, 0, 1 }
-- The strip is darker while the tile is not checked.
local STRIP_EMPTY = { 0.04, 0.04, 0.04, 1 }
local STRIP_CHECKED = { 0.12, 0.12, 0.12, 1 }
-- The flyout (layout B, section 6): 232 wide, as high as its parts (head
-- 66, summary 18, rows of 40, foot 28) and at most 300; four rows show, more
-- scroll. It opens right of its tile in columns 1 to 5, left in 6 to 8, 8
-- from the tile, its top 28 above the tile's, moved up so it never passes
-- the grid's bottom (y 440). The notch stays on the tile's middle.
local FLY_WIDTH, FLY_MAX, FLY_GAP, FLY_ABOVE, GRID_BOTTOM, RIGHT_COLUMNS = 232, 300, 8, 28, 440, 5
local FLY_HEAD, FLY_SUMMARY, FLY_TEXT, FLY_ROW, FLY_NOTE, FLY_FOOT, FLY_ROWS = 66, 18, 30, 40, 14, 28, 4
local FLY_INSIDE = FLY_WIDTH - 20
local FLY_EDGE = { 0.54, 0.45, 0.30, 1 }
local FLY_FILL = { 0.04, 0.035, 0.03, 0.97 }
local NOTCH_SIZE = 12
local HEAD_MODEL_WIDTH, HEAD_MODEL_HEIGHT = 44, 58
-- A found row's Buy button.
local BUY_WIDTH, BUY_HEIGHT = 40, 18
-- Texture paths are inferred from mainline clients, not read for Forever.
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ARROW = "Interface\\Buttons\\UI-SpellbookIcon-%sPage-%s"
-- Coin atlases of this build's money frame (Blizzard_MoneyFrame/Shared/MoneyFrame.lua:347-354).
local COIN_ATLAS = { gold = "coin-gold", silver = "coin-silver", copper = "coin-copper" }
local COIN_LETTERS = { gold = "g", silver = "s", copper = "c" }
-- How often a shown item list redraws, so its age stays true.
local AGE_REDRAW = 15
-- The status line's progress bar (spec 2.8) and a placeholder's short bar.
local PROGRESS_WIDTH, PROGRESS_HEIGHT = 64, 7
local BAR_WIDTH, BAR_HEIGHT = 30, 4
local BAR_COLOR = { 0.3, 0.3, 0.3, 1 }
local PROGRESS_COLOR = { 1, 0.82, 0, 1 }
-- Parts of a line 6 apart.
local TOOLS_GAP = 6
-- The header row (layout B, 1.1): the catalogue and sweep toggles at x 60
-- and 94, 30 square, then the slot row, Search and the funnel. The toggles'
-- glyphs are the addon's own art (Media), drawn 16 square.
local TOGGLE_Y, TOGGLE_SIZE, GLYPH_SIZE = 4, 30, 16
local MEDIA = "Interface\\AddOns\\TransmogChecker\\Media\\"
-- The catalogue glyph is white art tinted, lit and dim (the page's colours).
local GLYPH_ON, GLYPH_OFF = { 1, 0.914, 0.659, 1 }, { 0.604, 0.569, 0.498, 1 }
local TOGGLES = {
    { mode = "All", x = 60, art = "catalogue", tint = true, title = "All appearances",
        text = "Every appearance of the slot. A click on a tile checks it." },
    { mode = "For sale", x = 94, art = "sweep", title = "For sale, cheapest first",
        text = "Scans this slot and shows what you have not collected, cheapest first." },
}
-- The slot row: round buttons of 31, 2 apart, 19 between groups
-- (Blizzard_Collections/Camelot/Blizzard_Wardrobe.lua:24-27), at x 136
-- (layout B). Collections' own art (WardrobeSlotButtonTemplate,
-- Blizzard_Collections/Mainline/Blizzard_Wardrobe.xml:99-130, and
-- CreateSlotButtons, Blizzard_Wardrobe.lua:460-503); that this client has
-- these atlases is read from source and unverified in game.
local SLOTS_X, SLOTS_Y, SLOT_SIZE, SLOT_GAP, GROUP_GAP = 136, 4, 31, 2, 19
local SLOT_ART, SLOT_SELECTED, SLOT_HIGHLIGHT = "transmog-nav-slot-%s", "transmog-nav-slot-selected", "bags-roundhighlight"
-- Search at x 642, y 9, 108 x 20; the funnel at x 757, y 4, 30 square, with
-- the world map's filter art (Blizzard_WorldMap/Mainline/
-- Blizzard_WorldMapTemplates.xml:7, 41) and the auction house's reset mark
-- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:869), a 14 square
-- at its top left, while a choice differs from the start (layout B, 1.3).
local SEARCH_X, SEARCH_Y = 642, 9
local FUNNEL_X, FUNNEL_Y, FUNNEL_SIZE, MARK_SIZE = 757, 4, 30, 14
local FUNNEL_ATLAS, RESET_ATLAS = "Map-Filter-Button", "auctionhouse-ui-filter-redx"
local FUNNEL_TEXT, FUNNEL_TIP = "Filter", "Filter: show and class"
local CLASS_TEXT, RESET_TEXT = "Class: %s", "Reset filters"
-- The band under the header: the count at x 28, y 50, and the weapon type
-- dropdown (Collections' width, Blizzard_Wardrobe.lua:568) at x 598, y 47.
local COUNT_X, COUNT_Y = 28, 50
local WEAPON_X, WEAPON_Y, WEAPON_WIDTH = 598, 47, 157
-- The status line at x 62, y 445 (x 28 holds a later step's button), and
-- paging at the right, 4 in, with the wheel mark before the page text
-- (layout B, section 8).
local STATUS_X, STATUS_Y, STATUS_BUTTON, OFFER_BUTTON = 62, 445, 90, 110
local PAGING_RIGHT, PAGING_Y, WHEEL_WIDTH, WHEEL_HEIGHT = 4, 445, 16, 16
local NEXT_TIP, PREVIOUS_TIP = "Next page", "Previous page"
local WHEEL_TIP, ARROW_HINT = "Mouse wheel over the tiles turns pages", "Mouse wheel over the tiles turns pages too."

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

-- The player's figure, drawn with the transmog skin and wearing only the
-- tile's piece, set up once as Blizzard's wardrobe does
-- (ItemModelBaseMixin:OnLoad, as the probe's tiles ran it in game).
local function newModel(parent, x, y, width, height)
    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    model:SetSize(width, height)
    model:SetAutoDress(false)
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

local function newTile(grid, index, onClick, onWheel)
    local tile = CreateFrame("Frame", nil, grid)
    tile.index = index
    tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
    local _, _, x, y = cell(index)
    tile:SetPoint("TOPLEFT", grid, "TOPLEFT", x, -y)
    tile.border = tile:CreateTexture(nil, "BACKGROUND")
    tile.border:SetAllPoints()
    local inside = tile:CreateTexture(nil, "BORDER")
    inside:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
    inside:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
    inside:SetColorTexture(0, 0, 0, 1)
    -- The price strip, always there; empty and darker while not checked.
    tile.strip = tile:CreateTexture(nil, "ARTWORK")
    tile.strip:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1 - MODEL_HEIGHT)
    tile.strip:SetSize(TILE_WIDTH - 2, STRIP_HEIGHT)
    tile.strip:SetColorTexture(unpack(STRIP_EMPTY))
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
    tile.button = above
    tile.check = above:CreateTexture(nil, "OVERLAY")
    tile.check:SetSize(CHECK_SIZE, CHECK_SIZE)
    tile.check:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -3, -3)
    tile.check:SetTexture(CHECK_TEXTURE)
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
    local border = shown.open and BORDER_OPEN or shown.collected and BORDER_COLLECTED or BORDER
    tile.border:SetColorTexture(unpack(border))
    tile.check:SetShown(shown.collected == true)
    tile.strip:SetColorTexture(unpack((shown.strip == "not checked" or shown.strip == "bar") and STRIP_EMPTY
        or STRIP_CHECKED))
    tile.price:SetText(shown.money and moneyMarkup(shown.money) or "")
    tile.notForSale:SetText(shown.strip == "not for sale" and shown.price or "")
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
local function flyoutSize(list)
    local fixed = FLY_HEAD + FLY_SUMMARY + FLY_FOOT + (list.text and FLY_TEXT or 0) + (list.foot.note and FLY_NOTE or 0)
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
    local typeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typeText:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -10)
    typeText:SetWidth(FLY_WIDTH - 62 - 28)
    typeText:SetJustifyH("LEFT")
    local collectedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    collectedText:SetPoint("TOPLEFT", typeText, "BOTTOMLEFT", 0, -4)
    collectedText:SetText("Collected")
    collectedText:SetTextColor(0.1, 0.8, 0.1)
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

    -- body: the summary line, a text, the rows
    -- SpinnerTemplate: Blizzard_SharedXML/Spinner.xml:3
    local spinner = templated("Frame", frame, "SpinnerTemplate")
    if spinner then
        spinner:SetSize(16, 16)
        spinner:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -FLY_HEAD + 1)
    end
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetWidth(FLY_INSIDE)
    title:SetJustifyH("LEFT")
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(FLY_HEAD + FLY_SUMMARY))
    text:SetWidth(FLY_INSIDE)
    text:SetJustifyH("LEFT")
    -- offset: the rows scrolled past; shown: the rows that fit
    local offset, count, shown = 0, 0, FLY_ROWS
    local rows = {}
    for i = 1, FLY_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(FLY_INSIDE, FLY_ROW)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, i % 2 == 1 and 0.045 or 0)
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
    -- the scroll position, when the rows scroll
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:SetColorTexture(unpack(FLY_EDGE))

    -- foot
    local ageText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ageText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, FLY_FOOT + 2)
    local again = newButton(frame, "", 90, 20, State.CheckAgain)
    again:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 5)

    -- Beside the tile at index of the grid, right in columns 1 to 5, left in
    -- 6 to 8, never past the grid's bottom; the notch on the tile's middle.
    local function place(index, height)
        local column, _, x, y = cell(index)
        x, y = GRID_X + x, GRID_Y + y
        local right = column < RIGHT_COLUMNS
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
        local height
        shown, height = flyoutSize(list)
        count = #list.rows
        offset = math.max(0, math.min(offset, count - shown))
        place(index, height)
        show(frame, "weaponModel", model, list.appearance, list.weapon, function()
            return newWeaponModel(frame, 10, -8, HEAD_MODEL_WIDTH, HEAD_MODEL_HEIGHT)
        end)
        typeText:SetText(list.typeText)
        collectedText:SetShown(list.collected)
        collectedCheck:SetShown(list.collected)
        local checking = list.state == "checking"
        if spinner then spinner:SetShown(checking) end
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", (checking and spinner) and 30 or 10, -FLY_HEAD - 2)
        title:SetText(list.title or "")
        text:SetText(list.text or "")
        local rowsTop = FLY_HEAD + FLY_SUMMARY + (list.text and FLY_TEXT or 0)
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
        thumb:SetShown(count > shown)
        if count > shown then
            local track = shown * FLY_ROW
            thumb:SetHeight(track * shown / count)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -(rowsTop + track * offset / count))
        end
        ageText:SetText(list.foot.age or "")
        note:SetText(list.foot.note or "")
        again:SetText(list.foot.button or "")
        again:SetShown(list.foot.button ~= nil)
        again:SetEnabled(list.foot.enabled)
    end
    -- the wheel over the flyout scrolls its rows, not the pages
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local was = offset
        offset = math.max(0, math.min(offset - delta, count - shown))
        if offset ~= was and current then drawList(current, currentIndex) end
    end)
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
-- shows, in the size box of the button it replaces. The client's own menu
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
    button:SetSize(width, height)
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

-- An atlas the client has (C_Texture.GetAtlasInfo,
-- TextureUtilsDocumentation.lua:75-88).
local function hasAtlas(atlas)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- A catalogue or sweep toggle: Blizzard's SquareIconButtonTemplate (the
-- auction house's favourites button, Blizzard_AuctionHouseSearchBar.xml:11;
-- IconButtonTemplate.xml:40-57), or a bare button with its own icon, holding
-- the addon's glyph from Media. A texture file cannot be tested for, so the
-- tooltip names it. The selected one is lit (LockHighlight). It forwards the
-- click to the state.
local function newToggle(panel, toggle)
    local button = templated("Button", panel, "SquareIconButtonTemplate")
    if not (button and button.Icon) then
        button = button or CreateFrame("Button", nil, panel)
        button.Icon = button:CreateTexture(nil, "OVERLAY")
        button.Icon:SetPoint("CENTER")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    end
    button:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", toggle.x, -TOGGLE_Y)
    button.Icon:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    button.Icon:SetTexture(MEDIA .. toggle.art)
    button:SetScript("OnClick", function() State.SelectMode(toggle.mode) end)
    tooltip(button, toggle.title, toggle.text)
    button.mode = toggle.mode
    function button.draw(selected)
        if selected then button:LockHighlight() else button:UnlockHighlight() end
        if toggle.tint then button.Icon:SetVertexColor(unpack(selected and GLYPH_ON or GLYPH_OFF)) end
    end
    return button
end

-- An atlas on a texture, when the client has SetAtlas (read from source).
local function setAtlas(texture, atlas, useAtlasSize)
    if texture.SetAtlas then texture:SetAtlas(atlas, useAtlasSize) end
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
    local dropdown = menuDropdown(panel, "WowStyle1DropdownTemplate", width, 22, "OverrideText", function(root)
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
    local button = newButton(panel, "", width, 22, function() menu:SetShown(not menu:IsShown()) end)
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

-- The funnel (layout B, 1.3): the Show choices (the Filter), then the class
-- as a submenu, then "Reset filters" while a choice differs from the start.
-- In For sale Show is fixed and greyed; the class still works. Blizzard's
-- filter dropdown (WowStyle1FilterDropdownTemplate) drawn with the world
-- map's filter art when the client has it; its menu is filled from the
-- view at each opening (a button with radios under it is a submenu,
-- 11_0_0_MenuImplementationGuide.lua:24-32; SetEnabled, Menu.lua:830).
-- Without the template or its menu API, a button that opens a list of the
-- same entries; without the art, either reads "Filter". The reset mark at
-- its top left shows while a choice differs from the start.
local function newFunnel(panel)
    local current
    local function selected(entry) return entry ~= nil and entry.selected end
    local function pickShow(entry) if entry then State.SetFilter(entry.value) end end
    local function pickClass(entry) if entry then State.SelectClass(entry.value) end end
    local funnel = menuDropdown(panel, "WowStyle1FilterDropdownTemplate", FUNNEL_SIZE, FUNNEL_SIZE, "SetText",
        function(root)
            if not current then return end
            for _, entry in ipairs(current.filters) do
                local radio = root:CreateRadio(entry.name, selected, pickShow, entry)
                if current.filterFixed and radio and radio.SetEnabled then radio:SetEnabled(false) end
            end
            root:CreateDivider()
            local classes = current.classes
            local submenu = root:CreateButton(CLASS_TEXT:format(inClassColour(classes.text, classes.classFile)))
            for i, entry in ipairs(classes.entries) do
                submenu:CreateRadio(inClassColour(entry.name, entry.classFile), selected, pickClass, entry)
                if i == 1 then submenu:CreateDivider() end
            end
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
    local art = hasAtlas(FUNNEL_ATLAS)
    funnel:SetText(art and "" or FUNNEL_TEXT)
    if art then
        -- the template's dropdown art (MenuTemplates.xml:91) gives way to the funnel's
        if not menu and funnel.Background then funnel.Background:SetAlpha(0) end
        local icon = funnel:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetAtlas(FUNNEL_ATLAS)
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
    mark:SetPoint("CENTER", funnel, "TOPLEFT", 1, 1)
    local markArt = mark:CreateTexture(nil, "ARTWORK")
    markArt:SetAllPoints()
    if hasAtlas(RESET_ATLAS) then markArt:SetAtlas(RESET_ATLAS) else markArt:SetColorTexture(0.7, 0.1, 0.05, 1) end
    mark:SetScript("OnClick", State.ResetFilters)
    tooltip(mark, RESET_TEXT)
    function funnel.draw(view)
        current = view
        mark:SetShown(view.filtersChanged)
        if not menu then return end
        local items = {}
        for _, entry in ipairs(view.filters) do
            items[#items + 1] = { text = entry.name, enabled = not view.filterFixed,
                action = function() State.SetFilter(entry.value) end }
        end
        for i, entry in ipairs(view.classes.entries) do
            items[#items + 1] = { text = inClassColour(entry.name, entry.classFile), line = i <= 2,
                action = function() State.SelectClass(entry.value) end }
        end
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
    local toggles = {}
    for i, toggle in ipairs(TOGGLES) do toggles[i] = newToggle(panel, toggle) end
    local slotButtons = newSlotRow(panel)
    local search = newSearchBox(panel)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", SEARCH_X, -SEARCH_Y)
    local funnel = newFunnel(panel)
    local count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetPoint("TOPLEFT", panel, "TOPLEFT", COUNT_X, -COUNT_Y)
    local weaponType = newDropdown(panel, WEAPON_WIDTH, State.SelectWeaponType)
    weaponType:SetPoint("TOPLEFT", panel, "TOPLEFT", WEAPON_X, -WEAPON_Y)

    local grid = CreateFrame("Frame", nil, panel)
    grid:SetPoint("TOPLEFT", panel, "TOPLEFT", GRID_X, -GRID_Y)
    grid:SetSize(COLUMNS * TILE_WIDTH + (COLUMNS - 1) * GAP_X, ROWS * TILE_HEIGHT + (ROWS - 1) * GAP_Y)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta) State.Wheel(delta) end)
    local function clickTile(tile)
        if tile.appearance then State.ClickTile(tile.appearance) end
    end
    local tiles = {}
    for i = 1, COLUMNS * ROWS do
        tiles[i] = newTile(grid, i, clickTile, State.Wheel)
    end
    -- a click on a tile is the tile's own, not a click outside the flyout
    local function overTile()
        for _, tile in ipairs(tiles) do
            if tile:IsVisible() and tile.button:IsMouseOver() then return true end
        end
        return false
    end
    local flyout

    local emptyTitle = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
    paging:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAGING_RIGHT, -PAGING_Y)
    local previous = arrowButton(paging, "Prev", State.PreviousPage, PREVIOUS_TIP)
    local nextPage = arrowButton(paging, "Next", State.NextPage, NEXT_TIP)
    nextPage:SetPoint("RIGHT", paging, "RIGHT", 0, 0)
    previous:SetPoint("RIGHT", nextPage, "LEFT", -TOOLS_GAP, 0)
    local pageText = paging:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pageText:SetPoint("RIGHT", previous, "LEFT", -TOOLS_GAP - 5, 0)
    -- the wheel mark, the addon's art; the same art added on top makes it glow
    local wheelMark = CreateFrame("Frame", nil, paging)
    wheelMark:SetSize(WHEEL_WIDTH, WHEEL_HEIGHT)
    wheelMark:SetPoint("RIGHT", pageText, "LEFT", -7, 0)
    wheelMark:EnableMouse(true)
    tooltip(wheelMark, WHEEL_TIP)
    local wheelArt = wheelMark:CreateTexture(nil, "ARTWORK")
    wheelArt:SetAllPoints()
    wheelArt:SetTexture(MEDIA .. "wheel")
    local wheelGlow = wheelMark:CreateTexture(nil, "OVERLAY")
    wheelGlow:SetAllPoints()
    wheelGlow:SetTexture(MEDIA .. "wheel")
    wheelGlow:SetBlendMode("ADD")

    -- the status line: its text and one button, the button first when it
    -- leads ("Price this slot"), and a progress bar while a scan runs
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetHeight(24)
    status:SetJustifyH("LEFT")
    local statusAction
    local statusButton = newButton(panel, "", STATUS_BUTTON, 20, function()
        if statusAction then statusAction() end
    end)
    local progress = panel:CreateTexture(nil, "ARTWORK")
    progress:SetSize(PROGRESS_WIDTH, PROGRESS_HEIGHT)
    progress:SetPoint("LEFT", status, "RIGHT", TOOLS_GAP, 0)
    progress:SetColorTexture(unpack(STRIP_CHECKED))
    local progressFill = panel:CreateTexture(nil, "OVERLAY")
    progressFill:SetHeight(PROGRESS_HEIGHT)
    progressFill:SetPoint("LEFT", progress, "LEFT", 0, 0)
    progressFill:SetColorTexture(unpack(PROGRESS_COLOR))

    local function draw()
        local view = State.View()
        count:SetText(view.count)
        for _, toggle in ipairs(toggles) do toggle.draw(view.mode == toggle.mode) end
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
        pageText:SetText(view.pageText)
        previous:SetEnabled(view.previousEnabled)
        nextPage:SetEnabled(view.nextEnabled)
        paging:SetShown(view.paging)
        wheelGlow:SetShown(view.wheelGlow)
        status:SetText(view.status)
        statusButton:SetText(view.statusButton or "")
        statusButton:SetShown(view.statusButton ~= nil)
        statusButton:SetWidth(view.statusButtonLeads and OFFER_BUTTON or STATUS_BUTTON)
        statusAction = view.statusAction
        status:ClearAllPoints()
        statusButton:ClearAllPoints()
        if view.statusButtonLeads then
            statusButton:SetPoint("TOPLEFT", panel, "TOPLEFT", STATUS_X, -STATUS_Y - 2)
            status:SetPoint("LEFT", statusButton, "RIGHT", TOOLS_GAP, 0)
        else
            status:SetPoint("TOPLEFT", panel, "TOPLEFT", STATUS_X, -STATUS_Y)
            statusButton:SetPoint("LEFT", status, "RIGHT", TOOLS_GAP, 0)
        end
        progress:SetShown(view.progress ~= nil)
        progressFill:SetShown((view.progress or 0) > 0)
        progressFill:SetWidth(math.max(1, PROGRESS_WIDTH * (view.progress or 0)))
    end
    State.SetListener(draw)
    -- the buy dialog belongs to the panel and hides with it
    TC.Buy.Attach(panel)

    -- Leaving the tab stops a running check or scan (A6).
    panel:SetScript("OnHide", function()
        funnel.close()
        weaponType.close()
        if search.ClearFocus then search:ClearFocus() end
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
        -- the first draw, also when there is no list to tell of
        if not State.Refresh() and first then draw() end
        -- in For sale, a scan stopped by leaving the tab runs again (A6)
        State.Enter()
    end)
    panel:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
    panel:RegisterEvent("AUCTION_HOUSE_CLOSED")
    -- An item variant's name arrives after the check (spec 4.1); the list
    -- shows it once it is there.
    panel:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
    -- Search in For sale asks for every found variant's name, so the names
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
        elseif self:IsShown() then
            State.Refresh()
        end
    end)
end)
