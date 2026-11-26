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

-- Spec Assumption A5: the client confirms within 5 seconds.
local LIMIT = 5
-- The client's ready state changes without telling (spec 4.5): while the
-- dialog offers a purchase, its Buy button is drawn again this often.
local POLL = 0.25
-- Enum.ItemBind.OnEquip (ItemConstantsDocumentation.lua:249-261).
local BIND_ON_EQUIP = Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
local TEXT_FINDING = "Finding the cheapest auction"
local TEXT_BUYING = "Buying"
local TEXT_GONE = "That auction is gone."
local TEXT_FAILED = "The purchase did not go through."
local TEXT_CHANGED = "The price changed since the check."
local TEXT_BIND = "This item binds when equipped. Its appearance is collected when you equip it or sell it to a vendor."
local TEXT_MONEY = "You do not have enough money."
-- Coin atlases of this build's money frame (Blizzard_MoneyFrame/Shared/MoneyFrame.lua:347-354).
local COIN_ATLAS = { gold = "coin-gold", silver = "coin-silver", copper = "coin-copper" }
local COIN_LETTERS = { gold = "g", silver = "s", copper = "c" }
local BOX_WIDTH, BOX_HEIGHT = 320, 170

-- parent: the browser's panel (Attach). dialog: the frame, made on the
-- first Start. flow: the purchase the dialog is open for, from Start until
-- the dialog closes: { variant, state, auctionID, amount, ended }; state is
-- "finding", "ready", "buying", "gone" or "failed". buying: the flow whose
-- buyout was placed and whose outcome has not come; it outlives the dialog,
-- so the outcome or the 5-second limit still ends it and the check runs.
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

local function moneyMarkup(copper)
    local words = {}
    for i, part in ipairs(TC.BrowserState.MoneyParts(copper)) do
        local coin = CreateAtlasMarkup and CreateAtlasMarkup(COIN_ATLAS[part.coin], 12, 12) or COIN_LETTERS[part.coin]
        words[i] = part.amount .. coin
    end
    return table.concat(words, " ")
end

local function draw()
    local f = flow
    if not (f and dialog) then return end
    local variant = f.variant
    dialog.nameText:SetText(variant.name or "-")
    local r, g, b = 1, 1, 1
    if variant.name and type(variant.quality) == "number" and C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(variant.quality)
    end
    dialog.nameText:SetTextColor(r or 1, g or 1, b or 1)
    local status, price, lines = "", "", {}
    local offer = f.state == "ready" or f.state == "buying"
    if f.state == "finding" then
        status = TEXT_FINDING
    elseif offer then
        -- the price of the auction the click buys, in full (spec 3)
        price = moneyMarkup(f.amount)
        if f.state == "buying" then status = TEXT_BUYING end
        if f.amount ~= variant.minPrice then lines[#lines + 1] = TEXT_CHANGED end
        if variant.bindType == BIND_ON_EQUIP then lines[#lines + 1] = TEXT_BIND end
        local money = GetMoney()
        if type(money) ~= "number" or money < f.amount then lines[#lines + 1] = TEXT_MONEY end
    elseif f.state == "gone" then
        status = TEXT_GONE
    else
        status = TEXT_FAILED
    end
    dialog.statusText:SetText(status)
    dialog.priceText:SetText(price)
    dialog.linesText:SetText(table.concat(lines, "\n"))
    dialog.buyButton:SetShown(offer)
    dialog.buyButton:SetEnabled(canBuy(f))
    -- after the Buy click both buttons are off until the outcome
    dialog.closeButton:SetText((f.state == "gone" or f.state == "failed") and "Close" or "Cancel")
    dialog.closeButton:SetEnabled(f.state ~= "buying")
end

-- Tells the state once how the purchase ended: "completed", "failed" (the
-- client's error or no answer to the buyout), "gone" (nothing to buy),
-- "not sent" (the search failed) or "cancelled" (closed before an outcome).
local function finish(f, outcome)
    if f.ended then return end
    f.ended = true
    xpcall(function() TC.BrowserState.BuyFinished(outcome, f.variant) end, report)
end

local function fail(f)
    if buying == f then buying = nil end
    if flow == f then stopTicker() end
    f.state = "failed"
    draw()
    finish(f, "failed")
end

-- Closes the dialog and buys nothing more: Cancel, Close, Escape, leaving
-- the tab and closing the auction window all end here. A search still in
-- flight is dropped with the queue; nothing else of the addon reads while
-- the dialog is open (TC.BrowserState refuses it). A buyout already placed
-- cannot be called back: its outcome or the 5-second limit still ends it,
-- and the state runs the check when the player is still on the tab.
function Buy.Close()
    local f = flow
    if not f then return end
    flow = nil
    stopTicker()
    if f.state == "finding" then TC.AuctionQueue.CancelAll() end
    if dialog then dialog:Hide() end
    if f.state ~= "buying" then finish(f, "cancelled") end
end

-- The OnClick handler of the dialog's Buy button: the one place the addon
-- places a buyout. PlaceBid is restricted and on retail needs a real click
-- (spec 4.5, inferred for Forever), so it is called here, inside the click,
-- with no timer, queue or event in between. The flow leaves "ready" before
-- the call, so a second click, a double click or a held key places nothing
-- more. The amount and the auction id are those of the chosen search
-- result, the price the dialog shows. The 5-second limit is armed before
-- anything that can raise and the draw runs protected, so an error in it
-- neither stops the call nor leaves the outcome pending forever.
local function onBuyClick()
    local f = flow
    if not canBuy(f) then return end
    f.state, buying = "buying", f
    stopTicker()
    -- no outcome within 5 seconds: the purchase did not go through
    C_Timer.After(LIMIT, function()
        if buying == f then fail(f) end
    end)
    xpcall(draw, report)
    C_AuctionHouse.PlaceBid(f.auctionID, f.amount)
end

-- A button in Blizzard's panel style; the bare button still works without
-- the template.
local function newButton(box, text, onClick)
    local ok, button = pcall(CreateFrame, "Button", nil, box, "UIPanelButtonTemplate")
    if not ok then
        button = CreateFrame("Button", nil, box)
        if GameFontNormal then button:SetNormalFontObject(GameFontNormal) end
    end
    button:SetSize(90, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function newText(box, font, anchor, y)
    local text = box:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOP", anchor, anchor == box and "TOP" or "BOTTOM", 0, y)
    text:SetWidth(BOX_WIDTH - 24)
    text:SetJustifyH("CENTER")
    return text
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
    if key == "ESCAPE" and flow and flow.state ~= "buying" then Buy.Close() end
end

-- The dialog covers the whole panel, so the browser under it takes no click
-- while it is open, and hides with the panel.
local function newDialog(panel)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetAllPoints(panel)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetScript("OnKeyDown", onKeyDown)
    frame:SetScript("OnShow", takeKeyboard)
    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.6)
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(BOX_WIDTH, BOX_HEIGHT)
    box:SetPoint("CENTER", frame, "CENTER", 0, 0)
    box:EnableMouse(true)
    local background = box:CreateTexture(nil, "BORDER")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.05, 0.97)
    frame.nameText = newText(box, "GameFontNormal", box, -16)
    frame.statusText = newText(box, "GameFontHighlight", frame.nameText, -10)
    frame.priceText = newText(box, "GameFontHighlight", frame.statusText, -6)
    frame.linesText = newText(box, "GameFontHighlightSmall", frame.priceText, -8)
    frame.buyButton = newButton(box, "Buy", onBuyClick)
    frame.buyButton:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -4, 12)
    frame.closeButton = newButton(box, "Cancel", Buy.Close)
    frame.closeButton:SetPoint("BOTTOMLEFT", box, "BOTTOM", 4, 12)
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
    local f = { variant = variant, state = "finding" }
    flow = f
    TC.AuctionQueue.Search(variant.itemKey, {
        done = function(rows)
            if flow ~= f then return end
            local best = choose(rows)
            if not best then
                f.state = "gone"
                draw()
                return finish(f, "gone")
            end
            f.state, f.auctionID, f.amount = "ready", best.auctionID, best.buyoutAmount
            ticker = C_Timer.NewTicker(POLL, draw)
            draw()
        end,
        failed = function()
            if flow ~= f then return end
            f.state = "failed"
            draw()
            finish(f, "not sent")
        end,
    })
    dialog:Show()
    xpcall(draw, report)
    return true
end

-- The outcome of a buyout (AuctionHouseDocumentation.lua:1219-1227,
-- 1252-1260), handled as Blizzard's own buyout popup does
-- (Blizzard_AuctionHouseFrame.lua:14-24): the completion of our auction id,
-- or any error. A completion of another auction is not ours.
local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
events:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
-- Combat starting: the dialog gives the keyboard up (see takeKeyboard).
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, payload)
    if event == "AUCTION_HOUSE_CLOSED" then return Buy.Close() end
    if event == "PLAYER_REGEN_DISABLED" then
        if dialog then setKeyboard(dialog, false) end
        return
    end
    local f = buying
    if not f then return end
    if event == "AUCTION_HOUSE_SHOW_ERROR" then
        fail(f)
    elseif payload == f.auctionID then
        buying = nil
        if flow == f then
            flow = nil
            if dialog then dialog:Hide() end
        end
        finish(f, "completed")
    end
end)
