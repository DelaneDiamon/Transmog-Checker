-- The buy flow (spec 2.7, Assumption A8): a click on "Buy" in a found row
-- opens the addon's own dialog over the browser's panel and searches the
-- auction house for that one item variant through the query queue; the
-- dialog shows the buyout of the cheapest auction that has one and is not
-- the player's own, and its "Buy" button places that buyout. It hides the
-- search, the choice of the auction, the dialog frame, the outcome events
-- and the one auction call that cannot go through the queue: the buyout,
-- made only inside the OnClick handler of the dialog's "Buy" button.
-- Blizzard's own buy button ends in the same call, from its popup's Accept
-- click (Blizzard_AuctionHouseFrame.lua:10-12, 860-876). The dialog writes
-- nothing into Blizzard's popup tables and never touches AuctionHouseFrame.
TC = TC or {}
TC.Buy = {}

local Buy = TC.Buy
local L = TC.L

-- Spec Assumption A5: the client confirms within 5 seconds.
local LIMIT = 5
-- The client's ready state changes without telling (spec 4.5), and the
-- query queue tells nobody when it goes idle: while the dialog offers a
-- purchase, its Buy button is drawn again this often.
local POLL = 0.2
-- Enum.ItemBind.OnEquip (ItemConstantsDocumentation.lua:249-261).
local BIND_ON_EQUIP = Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
-- The two AUCTION_HOUSE_SHOW_ERROR codes that mean the auction is gone:
-- Enum.AuctionHouseError.ItemNotFound and .ItemNotAvailable
-- (AuctionHouseEnumsDocumentation.lua:29, 50). Fallback: their numbers 4
-- and 25 where the client lacks the enum.
local ERRORS = Enum and Enum.AuctionHouseError
local ITEM_NOT_FOUND = ERRORS and ERRORS.ItemNotFound or 4
local ITEM_NOT_AVAILABLE = ERRORS and ERRORS.ItemNotAvailable or 25
-- Coin atlases of this build's money frame (Blizzard_MoneyFrame/Shared/MoneyFrame.lua:347-354).
local COIN_ATLAS = { gold = "coin-gold", silver = "coin-silver", copper = "coin-copper" }
local function coinLetter(coin)
    return coin == "gold" and L.COIN_GOLD or coin == "silver" and L.COIN_SILVER or L.COIN_COPPER
end
-- The layout of Blizzard's AuctionHouseBuyDialogTemplate
-- (Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.xml): 420
-- wide (:52), the name 17 below the top (:56-60), buttons 120 x 22, 18 above
-- the bottom (:41-49) at CENTER -64 and 64 (:82-91), the dark overlay inset
-- 11 at alpha 0.8 (:96-108) with a 60 spinner (:109-114). Its mixin drives
-- commodity purchases, so the layout is copied, not inherited.
local BOX_WIDTH, TEXT_WIDTH, TOP, GAP, BUTTONS = 420, 360, 17, 7, 18 + 22 + 13

-- parent: the browser's panel (Attach). dialog: the frame, made on the
-- first Start. flow: the purchase the dialog is open for, from Start until
-- the dialog closes: { variant, state, auctionID, amount, allowed, limited,
-- ended, offers, refused, tried, bids }; state is "finding", "ready",
-- "buying", "gone" or "failed"; bids: the set of auction ids the dialog has
-- placed a buyout on, whose completion ends the flow whatever its state;
-- allowed: canBuy as of the last draw, the one thing the
-- Buy click reads; limited: the 5-second limit of the current offer's buyout
-- is armed; offers: how many auctions the dialog has offered, which tells
-- each buyout's limit from the next one's; refused: the client refused a
-- buyout of this dialog, tried: the amount it refused. buying: the flow
-- whose buyout was placed and whose outcome has not come; it outlives the
-- dialog, so the outcome or the 5-second limit still ends it and the check
-- runs.
local parent, dialog, flow, ticker, buying

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

-- Every call the flow needs, through feature detection. Without one of them
-- no row offers Buy.
function Buy.Available()
    return TC.AuctionQueue.CanSearch() and C_AuctionHouse.PlaceBid ~= nil and GetMoney ~= nil and C_Timer.After ~= nil
end

function Buy.IsOpen()
    return flow ~= nil
end

-- The cheapest auction to buy: the lowest buyoutAmount by comparing, not by
-- position, among the results with a buyout above 0 and an auction id that
-- are not the player's own nor of the player's account (spec 4.1; Blizzard's
-- own rule, Blizzard_AuctionHouseUtil.lua:613-616).
local function choose(rows)
    local best
    for _, row in ipairs(rows) do
        local amount = row.buyoutAmount
        if type(amount) == "number" and amount > 0 and type(row.auctionID) == "number" and row.containsOwnerItem ~= true
            and row.containsAccountItem ~= true and (not best or amount < best.buyoutAmount) then
            best = row
        end
    end
    return best
end

-- The dialog's Buy is on only when the search answered with an auction to
-- buy, the player has its buyout, the query queue is idle and the client
-- reports ready: whether a buyout takes a throttle slot is unverified
-- (spec 4.5).
local function canBuy(f)
    if not (f and f.state == "ready" and f.auctionID and f.amount) then return false end
    local money = GetMoney()
    return type(money) == "number" and money >= f.amount and TC.AuctionQueue.IsIdle()
        and C_AuctionHouse.IsThrottledMessageSystemReady() == true
end

-- An atlas this client has (TextureUtilsDocumentation.lua:75-88).
local function hasAtlas(atlas)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- The price as text, for a client without Blizzard's money display.
local function moneyMarkup(copper)
    local words = {}
    for i, part in ipairs(TC.BrowserState.MoneyParts(copper)) do
        local atlas = COIN_ATLAS[part.coin]
        local coin = CreateAtlasMarkup and hasAtlas(atlas) and CreateAtlasMarkup(atlas, 12, 12) or coinLetter(part.coin)
        words[i] = part.amount .. coin
    end
    return table.concat(words, " ")
end

-- A text's height for the layout; an estimate where the client gives none.
local function heightOf(text)
    local h = text.GetStringHeight and text:GetStringHeight()
    if type(h) == "number" and h > 0 then return h end
    local s = text:GetText() or ""
    return 14 * math.max(1, math.ceil(#s * 6 / TEXT_WIDTH))
end

-- Shows a text with a font colour, or hides it when there is nothing to say.
local function setLine(text, s, r, g, b)
    text:SetText(s or "")
    text:SetShown(s ~= nil)
    if s then text:SetTextColor(r or 1, g or 1, b or 1) end
end

-- Stacks the shown parts from the top, as the board draws them (7 apart),
-- sizes the box to them, and puts one centred button or the pair at the
-- bottom.
local function layout(d, single)
    local y = -TOP
    for _, part in ipairs(d.stack) do
        if part:IsShown() then
            part:ClearAllPoints()
            part:SetPoint("TOP", d.box, "TOP", 0, y)
            y = y - (part == d.price and 16 or heightOf(part)) - GAP
        end
    end
    d.box:SetHeight(-y + BUTTONS)
    d.closeButton:ClearAllPoints()
    d.closeButton:SetPoint("BOTTOM", d.box, "BOTTOM", single and 0 or 64, 18)
end

local function draw()
    local f = flow
    if not (f and dialog) then return end
    -- first, so a raise further down cannot leave it stale; a raise in
    -- canBuy itself leaves it false (R4)
    f.allowed = false
    f.allowed = canBuy(f)
    local d, variant = dialog, f.variant
    local r, g, b = 1, 1, 1
    if variant.name and type(variant.quality) == "number" and C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(variant.quality)
    end
    setLine(d.nameText, variant.name or "-", r, g, b)
    local lead, changed, hint, short
    local offer = f.state == "ready" or f.state == "buying"
    if f.state == "finding" then
        lead = f.refused and L.BUY_AGAIN or L.BUY_FINDING
    elseif offer then
        if f.refused then
            -- a new offer after a refused buyout: the line says why
            lead = f.amount == f.tried and L.BUY_SAME or L.BUY_CHEAPEST
        elseif f.amount ~= variant.minPrice then
            changed = L.BUY_CHANGED
        end
        if variant.bindType == BIND_ON_EQUIP then hint = L.BUY_BIND end
        local money = GetMoney()
        short = type(money) ~= "number" or money < f.amount
    elseif f.state == "gone" then
        lead = L.BUY_GONE
    else
        lead = L.BUY_FAILED
    end
    setLine(d.leadText, lead)
    -- the price of the auction the click buys, in full (spec 3); red when
    -- the player is short of it
    d.price:SetShown(offer)
    if offer then
        if d.moneyFrame then
            local font = short and PriceFontRed or PriceFontWhite
            if font then d.price:SetFontObject(font) end
            d.price:SetAmount(f.amount)
        else
            d.price:SetText(moneyMarkup(f.amount))
            if short then d.price:SetTextColor(1, 0.1, 0.1) else d.price:SetTextColor(1, 1, 1) end
        end
    end
    setLine(d.changedText, changed, 1, 0.82, 0)
    setLine(d.hintText, hint)
    -- the game's own text while the language is the client's (TC.ClientText), as the approved board asks
    setLine(d.moneyText, short and TC.ClientText("ERR_NOT_ENOUGH_MONEY", "BUY_NOT_ENOUGH_MONEY") or nil, 1, 0.1, 0.1)
    -- the small spinner beside "Finding", where the client has one
    if d.findSpinner then
        d.findSpinner:SetShown(f.state == "finding")
        if f.state == "finding" then
            local w = d.leadText:GetStringWidth()
            d.findSpinner:ClearAllPoints()
            d.findSpinner:SetPoint("RIGHT", d.leadText, "CENTER", -((type(w) == "number" and w or 0) / 2) - 4, 0)
        end
    end
    local over = f.state == "finding" or offer
    d.buyButton:SetShown(over)
    d.buyButton:SetEnabled(f.allowed)
    -- after the Buy click both buttons are off until the outcome, under the
    -- dark overlay and its spinner ("Buying" where there is no spinner)
    d.closeButton:SetText(over and L.CANCEL or L.CLOSE)
    d.closeButton:SetEnabled(f.state ~= "buying")
    d.overlay:SetShown(f.state == "buying")
    layout(d, not over)
end

-- Tells the state once how the purchase ended: "completed", "failed" (the
-- client's error or no answer to the buyout), "gone" (nothing to buy),
-- "not sent" (the search failed) or "cancelled" (closed before an outcome).
-- It is told once per dialog, when the flow ends, so the check that follows
-- never runs beside the dialog's own search or offer.
local function finish(f, outcome)
    if f.ended then return end
    f.ended = true
    xpcall(function() TC.BrowserState.BuyFinished(outcome, f.variant) end, report)
end

-- A buyout that had no answer in 5 seconds, or whose dialog was closed
-- before its refusal: it may still complete late, so nothing more is
-- offered.
local function fail(f)
    if buying == f then buying = nil end
    if flow == f then stopTicker() end
    f.state = "failed"
    xpcall(draw, report)
    finish(f, "failed")
end

-- One search for the dialog's item variant through the query queue (which
-- waits 1 s after the key's last send), answered with an offer of the
-- auction to buy, "gone" or "failed". After a refused buyout (refused) the
-- check of the appearance follows each end; after the first search a failed
-- one reads nothing more.
local search, tick
local function offer(f, best)
    f.state, f.auctionID, f.amount = "ready", best.auctionID, best.buyoutAmount
    -- a new offer is a new buyout, with its own 5-second limit
    f.offers, f.limited = (f.offers or 0) + 1, nil
    ticker = C_Timer.NewTicker(POLL, tick)
    xpcall(draw, report)
end
function search(f)
    TC.AuctionQueue.Search(f.variant.itemKey, {
        done = function(rows)
            if flow ~= f then return end
            local best = choose(rows)
            if not best then
                f.state = "gone"
                xpcall(draw, report)
                return finish(f, "gone")
            end
            offer(f, best)
        end,
        failed = function()
            if flow ~= f then return end
            f.state = "failed"
            xpcall(draw, report)
            finish(f, f.refused and "failed" or "not sent")
        end,
    })
end

-- The client refused the buyout of the open dialog (typically the auction
-- was just sold): the dialog stays open, looks again with one new search and
-- offers what it finds. That offer is bought only by a new click on Buy.
local function retry(f)
    buying = nil
    f.state, f.refused, f.tried, f.auctionID, f.amount = "finding", true, f.amount, nil, nil
    search(f)
    xpcall(draw, report)
end

-- Closes the dialog and buys nothing more: Cancel, Close, Escape, leaving
-- the tab and closing the auction window all end here. A search still in
-- flight is dropped with the queue; nothing else of the addon reads while
-- the dialog is open (TC.BrowserState refuses it). A buyout already placed
-- cannot be called back: its outcome or the 5-second limit still ends it
-- (settled here when a raise in PlaceBid kept the click from it), and the
-- state runs the check when the player is still on the tab. outcome: what
-- the state is told when no buyout is pending.
local settle
local function close(outcome)
    local f = flow
    if not f then return end
    flow = nil
    stopTicker()
    if f.state == "finding" then TC.AuctionQueue.CancelAll() end
    if dialog then dialog:Hide() end
    if f.state == "buying" then settle(f) else finish(f, outcome) end
end

-- Leaving the tab, closing the auction window or a new visit: nothing is
-- read after it.
function Buy.Close()
    close("cancelled")
end

-- The player's Cancel, Close or Escape: after a refused buyout the list and
-- the tile are stale, so the check runs (once; a flow that ended has told
-- the state already).
local function cancel()
    close(flow and flow.refused and "failed" or "cancelled")
end

-- What follows a placed buyout, once per offer: the 5-second limit, the poll
-- stopped and the dialog drawn as "Buying", each protected so a raise in one
-- skips neither the others nor the end of the flow. A limit that cannot be
-- armed ends the purchase as failed at once, so the pending bid never stays
-- set.
function settle(f)
    if f.limited then return end
    f.limited = true
    local bid = f.offers
    local armed = xpcall(function()
        -- no outcome within 5 seconds: the purchase did not go through
        C_Timer.After(LIMIT, function()
            if buying == f and f.offers == bid then fail(f) end
        end)
    end, report)
    if flow == f then xpcall(stopTicker, report) end
    if armed then
        xpcall(draw, report)
    else
        xpcall(function() fail(f) end, report)
    end
end

-- The poll while the dialog offers the auction. A flow found "buying" here
-- had its click stopped by a raise in PlaceBid before settle ran: it is
-- settled now, which also stops the poll.
function tick()
    local f = flow
    if f and f.state == "buying" then return settle(f) end
    draw()
end

-- The OnClick handler of the dialog's Buy button: the one place the addon
-- places a buyout. PlaceBid is the first call the handler makes: before it,
-- only Lua values are read and written (no API call, frame method, timer,
-- pcall or other module). On 2026-11-25 the client blocked it as a
-- protected call (ADDON_ACTION_BLOCKED, "UNKNOWN()") when this handler,
-- before calling it, armed the timer and redrew the dialog, which hid and
-- disabled the clicked button; with the purchase moved ahead of everything
-- the same day, a purchase from this dialog went through in game. The
-- likely cause is the protected Show / SetEnabled calls on the clicked
-- button, not calls before PlaceBid as such: that is inferred, not proven,
-- so the handler keeps every call after it. The conditions the click used to check
-- (money, the queue idle, the client ready) are f.allowed, kept current by
-- every draw: the poll, PLAYER_MONEY and the client's ready event; a
-- disabled button takes no click. The flow leaves "ready" before the call,
-- so a second click, a double click or a held key places nothing more. The
-- amount and the auction id are those of the chosen search result, the
-- price the dialog shows.
local function onBuyClick()
    local f = flow
    if not (f and f.allowed and f.state == "ready" and f.auctionID and f.amount) then return end
    f.state, f.allowed, buying = "buying", false, f
    f.bids[f.auctionID] = true
    C_AuctionHouse.PlaceBid(f.auctionID, f.amount)
    settle(f)
end

-- A button in Blizzard's panel style; the bare button still works without
-- the template.
local function newButton(box, text, onClick)
    local ok, button = pcall(CreateFrame, "Button", nil, box, "UIPanelButtonTemplate")
    if not ok then
        button = CreateFrame("Button", nil, box)
        if GameFontNormal then button:SetNormalFontObject(GameFontNormal) end
    end
    button:SetSize(120, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

-- A centred text line of the dialog; draw places it.
local function newText(content, font)
    local text = content:CreateFontString(nil, "OVERLAY", font)
    text:SetWidth(TEXT_WIDTH)
    text:SetJustifyH("CENTER")
    return text
end

-- A frame from a Blizzard template, or nil where the client lacks it.
local function fromTemplate(kind, frameParent, template)
    local ok, frame = pcall(CreateFrame, kind, nil, frameParent, template)
    return ok and frame or nil
end

-- Blizzard's spinner (Blizzard_SharedXML/Spinner.xml:3-24), only where its
-- two atlases exist.
local function newSpinner(frameParent, size)
    if not (hasAtlas("Spinner_Ring") and hasAtlas("Spinner_Sparks")) then return nil end
    local spinner = fromTemplate("Frame", frameParent, "SpinnerTemplate")
    if spinner then spinner:SetSize(size, size) end
    return spinner
end

-- SetPropagateKeyboardInput is restricted (SimpleFrameAPIDocumentation.lua:
-- 1426-1435): it is called only out of combat. A frame with the keyboard
-- keeps every key unless propagation is on (propagateKeyboardInput defaults
-- to false, UI.xsd:844), so in combat the dialog takes no keyboard at all:
-- Escape then goes to the game, which closes the auction window, which
-- closes the dialog and buys nothing.
local function inCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end
local function canPropagate(frame)
    return frame.SetPropagateKeyboardInput ~= nil and not inCombat()
end

-- EnableKeyboard is marked IsProtectedFunction (SimpleFrameAPIDocumentation.
-- lua:247-256); that it may be called in combat on this unprotected frame
-- is inferred, unverified in game.
local function setKeyboard(frame, on)
    if frame.EnableKeyboard then frame:EnableKeyboard(on) end
end

-- Shown out of combat, the dialog takes the keyboard with propagation on at
-- once, before any key arrives, so only Escape is ever kept; shown in
-- combat it takes none. The next show decides again.
local function takeKeyboard(frame)
    if canPropagate(frame) then
        frame:SetPropagateKeyboardInput(true)
        setKeyboard(frame, true)
    else
        setKeyboard(frame, false)
    end
end

-- The dialog takes the keys itself and touches none of Blizzard's Escape
-- handlers: Escape closes it as Cancel does and goes no further, so the
-- auction window stays open; while "Buying" Escape does nothing, so the
-- outcome still ends the purchase and the check runs. Every other key,
-- Enter too, is passed on and does nothing here. Unverified in game.
local function onKeyDown(frame, key)
    if canPropagate(frame) then
        frame:SetPropagateKeyboardInput(key ~= "ESCAPE")
    end
    if key == "ESCAPE" and flow and flow.state ~= "buying" then cancel() end
end

-- The dialog as the approved board draws it (appearance-browser-visual-pass
-- v2, board 11), Blizzard's buy dialog in layout: a click catcher over the
-- window below its title (Blizzard_AuctionHouseFrame.xml:174-179), so the
-- browser under it takes no click while it is open, and the box at the
-- window's centre, 50 above (:181-185). The catcher belongs to the panel and
-- hides with it. Each Blizzard part is made under pcall; without it the
-- dialog keeps its plain look: a dark box, the price as text, "Buying" in
-- place of the spinner.
local function newDialog(panel)
    local frame = CreateFrame("Frame", nil, panel)
    -- the panel spans the window from 42 below its top to 27 above its
    -- bottom (TC_BrowserPanel.lua): the catcher starts 22 below the top
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", -5, 20)
    frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 4, -27)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetScript("OnKeyDown", onKeyDown)
    frame:SetScript("OnShow", takeKeyboard)
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(BOX_WIDTH, 100)
    -- the catcher's centre is 11 below the window's
    box:SetPoint("CENTER", frame, "CENTER", 0, 61)
    box:EnableMouse(true)
    frame.box = box
    -- DialogBorderDarkTemplate (Blizzard_SharedXML/Shared/Dialog/
    -- DialogTemplates.xml:83-95) at the box's own level, as useParentLevel
    -- puts it (Blizzard_AuctionHouseBuyDialog.xml:54)
    frame.border = fromTemplate("Frame", box, "DialogBorderDarkTemplate")
    if frame.border then
        frame.border:SetAllPoints(box)
        frame.border:SetFrameLevel(box:GetFrameLevel())
    else
        local background = box:CreateTexture(nil, "BORDER")
        background:SetAllPoints()
        background:SetColorTexture(0.05, 0.05, 0.05, 0.97)
    end
    -- the texts above the border
    local content = CreateFrame("Frame", nil, box)
    content:SetAllPoints(box)
    frame.nameText = newText(content, "GameFontHighlightLarge")
    frame.leadText = newText(content, "GameFontHighlight")
    -- the price in Blizzard's money display with the auction house's coins,
    -- sized to fit (Blizzard_AuctionHouseBuyDialog.xml:71-80;
    -- Blizzard_MoneyFrame/Shared/MoneyFrame.lua:474-495, 557-572): the
    -- template's KeyValues are commented out (MoneyFrame.xml:35-50), so
    -- resizeToFit is set here; on this build the auction house coins are
    -- the plain ones (MoneyFrame.lua:347-354)
    frame.price = fromTemplate("Frame", content, "MoneyDisplayFrameTemplate")
    if frame.price then
        frame.moneyFrame = true
        frame.price:SetResizeToFit(true)
    else
        frame.price = newText(content, "GameFontHighlightLarge")
    end
    frame.changedText = newText(content, "GameFontNormal")
    frame.hintText = newText(content, "GameFontHighlightSmall")
    frame.moneyText = newText(content, "GameFontHighlight")
    frame.stack = { frame.nameText, frame.leadText, frame.price, frame.changedText, frame.hintText, frame.moneyText }
    frame.findSpinner = newSpinner(content, 16)
    frame.buyButton = newButton(box, L.BUY, onBuyClick)
    frame.buyButton:SetPoint("BOTTOM", box, "BOTTOM", -64, 18)
    frame.closeButton = newButton(box, L.CANCEL, cancel)
    -- the dark overlay over everything while buying, with the large spinner
    local overlay = CreateFrame("Frame", nil, box)
    overlay:SetPoint("TOPLEFT", box, "TOPLEFT", 11, -11)
    overlay:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -11, 11)
    overlay:SetFrameLevel(box:GetFrameLevel() + 10)
    overlay:EnableMouse(true)
    local dark = overlay:CreateTexture(nil, "OVERLAY")
    dark:SetAllPoints()
    dark:SetColorTexture(0, 0, 0, 0.8)
    frame.spinner = newSpinner(overlay, 60)
    if frame.spinner then
        frame.spinner:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    else
        local buyingText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        buyingText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
        buyingText:SetText(L.BUY_BUYING)
    end
    overlay:Hide()
    frame.overlay = overlay
    frame:Hide()
    frame:SetScript("OnHide", function(self)
        setKeyboard(self, false)
        Buy.Close()
    end)
    return frame
end

-- The browser's panel, which the dialog belongs to. Without it Start opens
-- nothing and sends nothing.
function Buy.Attach(panel)
    parent = panel
end

-- Opens the dialog for an item variant { itemKey, name, quality, minPrice,
-- bindType, ... } and runs one search for it. Answers whether it opened;
-- it does not while the dialog is open or a buyout's outcome is pending,
-- before Attach, or when a call is missing. The search is queued before the
-- first draw, and an error in that draw is only reported, so an open
-- dialog always has its search in flight.
function Buy.Start(variant)
    if flow or buying or not parent or not (variant and variant.itemKey) or not Buy.Available() then return false end
    dialog = dialog or newDialog(parent)
    local f = { variant = variant, state = "finding", bids = {} }
    flow = f
    search(f)
    dialog:Show()
    xpcall(draw, report)
    return true
end

-- The outcome of a buyout (AuctionHouseDocumentation.lua:1219-1227,
-- 1252-1260), handled as Blizzard's own buyout popup does
-- (Blizzard_AuctionHouseFrame.lua:14-24). AUCTION_HOUSE_SHOW_ERROR is one
-- event for every auction house error: only ItemNotFound and
-- ItemNotAvailable, while the dialog is open, look again (retry); any other
-- code, none or one that is not a number ends the buyout as failed. An
-- error with no buyout in flight, or after its 5 seconds, changes nothing.
-- The completion of any auction the dialog bid on ends it as completed
-- (completed); a completion of another auction is not ours.

-- f completed when it bid on id: while looking again or offering, the
-- search or offer is dropped; a later bid of f cannot be called back, and
-- its outcome then finds no flow; after the failure the dialog closes (the
-- check ran then). Answers whether f bid on id.
local function completed(f, id)
    if not (f and f.bids[id]) then return false end
    if buying == f then buying = nil end
    if flow == f then
        flow = nil
        stopTicker()
        if f.state == "finding" then TC.AuctionQueue.CancelAll() end
        if dialog then dialog:Hide() end
    end
    finish(f, "completed")
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
events:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
-- Combat starting: the dialog gives the keyboard up (see takeKeyboard).
events:RegisterEvent("PLAYER_REGEN_DISABLED")
-- The money and the client's ready state: the Buy button follows them at
-- once while the dialog offers the auction (the poll catches the rest).
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
events:SetScript("OnEvent", function(_, event, payload)
    if event == "AUCTION_HOUSE_CLOSED" then return Buy.Close() end
    if event == "PLAYER_MONEY" or event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if flow and flow.state == "ready" then xpcall(draw, report) end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        if dialog then setKeyboard(dialog, false) end
        return
    end
    if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        return completed(buying, payload) or completed(flow, payload)
    end
    local f = buying
    if not f then return end
    if flow == f and type(payload) == "number" and (payload == ITEM_NOT_FOUND or payload == ITEM_NOT_AVAILABLE) then
        retry(f)
    else
        fail(f)
    end
end)
