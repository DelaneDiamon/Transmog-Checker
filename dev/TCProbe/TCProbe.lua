-- TCProbe: records which transmog and auction APIs exist and return data on
-- this client. Results go to TCProbeDB, which the client writes to
-- WTF\Account\<account>\SavedVariables\TCProbe.lua on /reload or logout.

local MAX_ALT_SOURCES = 8
-- Auction recording: rows kept from the first page of a step, pages read per
-- item class (500 rows each), searches in the closing burst, seconds without
-- an answer before a step is given up, and event log entries kept.
local HEAD_ROWS = 15
local PAGE_CAP = 80
local SEARCH_BURST = 5
local STEP_TIMEOUT = 20
local LOG_MAX = 1500

local db

-- Calls ns[name](...) and returns its results as a list, or a table saying
-- why there are none. Every probe call goes through here so that one missing
-- or erroring function leaves the rest of the probe running.
local function call(ns, name, ...)
    local fn = ns and ns[name]
    if type(fn) ~= "function" then
        return { missing = true }
    end
    local results = { pcall(fn, ...) }
    if not results[1] then
        return { error = tostring(results[2]) }
    end
    table.remove(results, 1)
    return results
end

local function sortedFunctionNames(ns)
    if type(ns) ~= "table" then
        return false
    end
    local names = {}
    for key, value in pairs(ns) do
        if type(value) == "function" then
            names[#names + 1] = key
        end
    end
    table.sort(names)
    return names
end

local function probeClient()
    db.client = {
        build = { GetBuildInfo() },
        projectID = WOW_PROJECT_ID,
        recordedAt = date("%Y-%m-%d %H:%M:%S"),
    }
end

local function probeNamespaces()
    db.namespaces = {
        C_TransmogCollection = sortedFunctionNames(C_TransmogCollection),
        C_Transmog = sortedFunctionNames(C_Transmog),
        C_TransmogSets = sortedFunctionNames(C_TransmogSets),
        C_AuctionHouse = sortedFunctionNames(C_AuctionHouse),
        C_Item = sortedFunctionNames(C_Item),
    }
    db.globals = {
        GetItemInfo = type(GetItemInfo),
        GetItemInfoInstant = type(GetItemInfoInstant),
        QueryAuctionItems = type(QueryAuctionItems),
        DressUpItemLink = type(DressUpItemLink),
        WardrobeCollectionFrame = type(WardrobeCollectionFrame),
        TooltipDataProcessor = type(TooltipDataProcessor),
    }
    -- TransmogChecker hooks this script; newer clients removed it in favour
    -- of TooltipDataProcessor.
    db.tooltipHasOnTooltipSetItem = call(GameTooltip, "HasScript", GameTooltip, "OnTooltipSetItem")
end

-- Resolves one item to its appearance and the appearance's other sources:
-- the chain the AH browser needs for every auction row.
local function probeItem(item)
    local TC = C_TransmogCollection
    local record = { item = item }
    record.itemInfo = call(TC, "GetItemInfo", item)
    local appearanceID, sourceID = record.itemInfo[1], record.itemInfo[2]
    if not sourceID then
        return record
    end
    record.sourceInfo = call(TC, "GetSourceInfo", sourceID)
    record.hasSource = call(TC, "PlayerHasTransmogItemModifiedAppearance", sourceID)
    record.canCollect = call(TC, "PlayerCanCollectSource", sourceID)
    record.cameraID = call(TC, "GetAppearanceCameraID", appearanceID)
    record.allSources = call(TC, "GetAllAppearanceSources", appearanceID)
    local sourceIDs = record.allSources[1]
    if type(sourceIDs) == "table" then
        record.altSources = {}
        for i = 1, math.min(#sourceIDs, MAX_ALT_SOURCES) do
            record.altSources[i] = call(TC, "GetSourceInfo", sourceIDs[i])
        end
    end
    return record
end

local function probeEquipped()
    db.equipped = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            db.equipped[slot] = probeItem(link)
        end
    end
end

local function probeModel()
    local record = {}
    db.model = record
    local ok, model = pcall(CreateFrame, "DressUpModel")
    if not ok then
        record.createError = tostring(model)
        return
    end
    record.methods = {}
    for _, method in ipairs({
        "SetUnit", "Undress", "TryOn", "SetItemTransmogInfo", "SetItemAppearance",
        "SetUseTransmogSkin", "SetCamera", "FreezeAnimation", "SetPosition",
    }) do
        record.methods[method] = type(model[method])
    end
    record.setUnit = call(model, "SetUnit", model, "player")
    for slot = 1, 19 do
        local equipped = db.equipped and db.equipped[slot]
        local sourceID = equipped and equipped.itemInfo[2]
        if sourceID then
            record.tryOnSourceID = sourceID
            record.tryOn = call(model, "TryOn", model, sourceID)
            -- The first result may mean "data pending"; record the enum that
            -- names the codes and ask again once the model has had time to load.
            record.tryOnReasons = Enum and Enum.ItemTryOnReason
            C_Timer.After(5, function()
                record.tryOnLater = call(model, "TryOn", model, sourceID)
            end)
            break
        end
    end
end

-- The chest piece Blizzard's wardrobe dresses its own models with
-- (WARDROBE_MODEL_SETUP_GEAR in Blizzard_TransmogShared): a control that tells
-- a wrong model setup apart from a source the model refuses.
local SETUP_GEAR_CHEST = 78420

local variantFrames = {}

local function hideModelVariants()
    for _, model in ipairs(variantFrames) do
        model:Hide()
    end
end

-- What Blizzard's wardrobe does to a model before TryOn
-- (ItemModelBaseMixin:OnLoad and :Reload in Blizzard_TransmogShared).
local function setUpLikeWardrobe(model)
    return {
        unitReady = call(_G, "IsUnitModelReadyForUI", "player"),
        autoDress = call(model, "SetAutoDress", model, false),
        transmogSkin = call(model, "SetUseTransmogSkin", model, true),
        transmogChoices = call(model, "SetUseTransmogChoices", model, true),
        obeyHide = call(model, "SetObeyHideInTransmogFlag", model, true),
        setUnit = call(model, "SetUnit", model, "player", false),
    }
end

-- Frames a model the way Blizzard's wardrobe frames each tile
-- (WardrobeItemsCollectionMixin:UpdateItems in Blizzard_Collections).
local function applyAppearanceCamera(model, appearanceID)
    local cameraID = call(C_TransmogCollection, "GetAppearanceCameraID", appearanceID)
    return {
        cameraID = cameraID,
        apply = call(_G, "Model_ApplyUICamera", model, cameraID[1]),
    }
end

-- armor and weapon are { sourceID, appearanceID, link }; weapon may be nil.
-- Row 1 dresses the armor piece, row 2 shows the weapon.
local function modelVariants(armor, weapon)
    local variants = {
        { name = "tryOnSource", row = 1, unit = true, apply = function(model)
            return call(model, "TryOn", model, armor.sourceID)
        end },
        { name = "tryOnLink", row = 1, unit = true, apply = function(model)
            return call(model, "TryOn", model, armor.link)
        end },
        { name = "transmogInfo", row = 1, unit = true, apply = function(model)
            local info = call(ItemUtil, "CreateItemTransmogInfo", armor.sourceID, 0, 0)
            if type(info[1]) ~= "table" then
                return { noInfo = info }
            end
            return call(model, "SetItemTransmogInfo", model, info[1])
        end },
        { name = "setupGear", row = 1, unit = true, apply = function(model)
            return call(model, "TryOn", model, SETUP_GEAR_CHEST)
        end },
        { name = "itemAppearance", row = 1, unit = false, apply = function(model)
            return call(model, "SetItemAppearance", model, armor.appearanceID)
        end },
    }
    if weapon then
        variants[#variants + 1] = { name = "weaponTryOn", row = 2, unit = true, apply = function(model)
            return call(model, "TryOn", model, weapon.sourceID)
        end }
        -- Blizzard's weapon tiles: no unit, the appearance alone, framed by its
        -- UI camera, which is applied again once the model has loaded.
        variants[#variants + 1] = { name = "weaponAppearanceCam", row = 2, unit = false,
            apply = function(model)
                return {
                    autoDress = call(model, "SetAutoDress", model, false),
                    keepOnHide = call(model, "SetKeepModelOnHide", model, true),
                    camera = applyAppearanceCamera(model, weapon.appearanceID),
                    set = call(model, "SetItemAppearance", model, weapon.appearanceID),
                }
            end,
            onLoaded = function(model)
                return applyAppearanceCamera(model, weapon.appearanceID)
            end,
        }
        variants[#variants + 1] = { name = "weaponAppearance", row = 2, unit = false, apply = function(model)
            return call(model, "SetItemAppearance", model, weapon.appearanceID)
        end }
    end
    return variants
end

local function equippedItem(firstSlot, lastSlot)
    for slot = firstSlot, lastSlot do
        local equipped = db.equipped and db.equipped[slot]
        if equipped and equipped.itemInfo[2] then
            return {
                sourceID = equipped.itemInfo[2],
                appearanceID = equipped.itemInfo[1],
                link = equipped.item,
            }
        end
    end
end

-- Shows one labelled model frame per candidate way of showing an equipped
-- armor piece and an equipped weapon, so each call's return value can be set
-- against what the frame visibly shows.
local function showModelVariants()
    local armor = equippedItem(1, 15)
    if not armor then
        db.modelVisible = { noEquippedSource = true }
        return
    end
    local record = {
        armor = armor,
        weapon = equippedItem(16, 18),
        ranAt = date("%H:%M:%S"),
        variants = {},
    }
    db.modelVisible = record
    local columns = {}
    local variants = modelVariants(armor, record.weapon)
    for i, variant in ipairs(variants) do
        local model = variantFrames[i]
        if not model then
            local column = (columns[variant.row] or 0) + 1
            columns[variant.row] = column
            model = CreateFrame("DressUpModel", nil, UIParent)
            model:SetSize(130, 180)
            model:SetPoint("TOP", UIParent, "TOP", (column - 3) * 140, -120 - (variant.row - 1) * 210)
            local background = model:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(0, 0, 0, 0.8)
            local label = model:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("BOTTOM", model, "TOP", 0, 2)
            label:SetText(i .. " " .. variant.name)
            model:EnableMouse(true)
            model:SetScript("OnMouseDown", hideModelVariants)
            variantFrames[i] = model
        end
        model:Show()
        local result = { modelLoaded = 0 }
        record.variants[variant.name] = result
        result.loadedScript = call(model, "SetScript", model, "OnModelLoaded", function()
            result.modelLoaded = result.modelLoaded + 1
            if variant.onLoaded then
                result.onLoaded = variant.onLoaded(model)
            end
        end)
        if variant.unit then
            result.setup = setUpLikeWardrobe(model)
        end
        result.first = variant.apply(model)
        C_Timer.After(5, function()
            result.later = variant.apply(model)
        end)
    end
    print(("TCProbe: %d model frames are at the top of the screen. After 5 seconds note which numbers show the item, click a frame to hide them, then /reload."):format(#variants))
end

-- Records what each item tooltip hands to a post-call and what TransmogChecker
-- makes of it, so a silent tooltip can be told apart from a hook that never fires.
local function probeTooltipHook()
    local record = { calls = 0 }
    db.tooltip = record
    -- False here means /tc settings are written to a table the client never saves.
    record.tcConfigIsSavedTable = (TC ~= nil and TC.Config == TransmogCheckerDB)
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType) then
        record.noProcessor = true
        return
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        record.calls = record.calls + 1
        record.lastTooltip = call(tooltip, "GetName", tooltip)
        record.lastItem = call(tooltip, "GetItem", tooltip)
        local link = record.lastItem[2]
        if link and TC_ItemChecker then
            record.lastStatus = call(TC_ItemChecker, "GetTransmogStatus", TC_ItemChecker, link)
            record.config = TC and TC.Config
        end
    end)
end

local function preciseTime()
    return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local function round3(seconds)
    return math.floor(seconds * 1000 + 0.5) / 1000
end

local function sortBy(name, fallback, reverse)
    local orders = Enum and Enum.AuctionHouseSortOrder
    return { sortOrder = orders and orders[name] or fallback, reverseSort = reverse or false }
end

local function itemClass(name, fallback)
    return Enum and Enum.ItemClass and Enum.ItemClass[name] or fallback
end

-- The auction recording is a fixed sequence. The first three steps read one
-- page each with a different sort, to show whether the sort changes the order
-- of the rows. The last two page through a whole item class, to show how many
-- rows and appearances a full browse holds and how long it takes. A burst of
-- per-item searches follows, to show how fast those may be sent.
local auctionSteps = {
    { name = "armorPriceDesc", classID = itemClass("Armor", 4), pages = 1,
        sorts = { sortBy("Price", 0, true) } },
    { name = "armorPriceThenName", classID = itemClass("Armor", 4), pages = 1,
        sorts = { sortBy("Price", 0), sortBy("Name", 1) } },
    { name = "armorName", classID = itemClass("Armor", 4), pages = 1,
        sorts = { sortBy("Name", 1) } },
    { name = "armorPriceAsc", classID = itemClass("Armor", 4), pages = PAGE_CAP, searchKeys = true,
        sorts = { sortBy("Price", 0) } },
    { name = "weaponPriceAsc", classID = itemClass("Weapon", 2), pages = PAGE_CAP,
        sorts = { sortBy("Price", 0) } },
}

-- The recording in progress; nil when none is running.
local run

local function elapsed()
    return round3(preciseTime() - run.t0)
end

local function logAuctionEvent(event, detail)
    if not run then
        return
    end
    local record = run.record
    record.eventCounts[event] = (record.eventCounts[event] or 0) + 1
    if #record.log < LOG_MAX then
        record.log[#record.log + 1] = {
            t = elapsed(),
            event = event,
            step = run.step and run.step.name,
            detail = detail,
        }
    end
end

local function throttleReady()
    return call(C_AuctionHouse, "IsThrottledMessageSystemReady")[1] ~= false
end

-- Runs fn at once when the client accepts a throttled auction message, or
-- from the ticker as soon as it does. fn gets the seconds it waited.
local function whenReady(fn)
    run.lastActivity = preciseTime()
    if throttleReady() then
        fn(0)
    else
        run.waiting = { fn = fn, since = preciseTime() }
    end
end

local function itemName(itemKey)
    local info = call(C_AuctionHouse, "GetItemKeyInfo", itemKey)[1]
    if type(info) == "table" and info.itemName then
        return info.itemName
    end
    return call(C_Item, "GetItemNameByID", itemKey.itemID)[1]
end

local function fillMissingNames()
    for _, record in pairs(run.record.steps) do
        for _, row in ipairs(record.head or {}) do
            row.name = row.name or itemName(row.itemKey)
        end
    end
end

local function finishRun(reason)
    fillMissingNames()
    run.record.finished = reason
    run.record.tookSeconds = elapsed()
    run.ticker:Cancel()
    print(("TCProbe: auction recording ended (%s) after %d seconds. /reload now."):format(
        reason, math.floor(run.record.tookSeconds)))
    run = nil
end

local function startSearch(index)
    local itemKey = run.searchKeys and run.searchKeys[index]
    if not itemKey then
        return finishRun("finished")
    end
    local record = { itemKey = itemKey }
    run.record.searches[index] = record
    run.step = { name = "search" .. index }
    run.state = nil
    run.search = { index = index, record = record }
    whenReady(function(waited)
        record.waitedForThrottle = waited
        run.search.sentAt = preciseTime()
        record.send = call(C_AuctionHouse, "SendSearchQuery", itemKey, { sortBy("Buyout", 4) }, false)
        record.readyAfterSend = throttleReady()
    end)
end

local function onSearchResults(itemKey)
    local search = run and run.search
    if not search or not search.sentAt or type(itemKey) ~= "table"
        or itemKey.itemID ~= search.record.itemKey.itemID
        or itemKey.itemSuffix ~= search.record.itemKey.itemSuffix then
        return
    end
    local record = search.record
    record.tookSeconds = round3(preciseTime() - search.sentAt)
    record.count = call(C_AuctionHouse, "GetNumItemSearchResults", record.itemKey)
    record.full = call(C_AuctionHouse, "HasFullItemSearchResults", record.itemKey)
    record.readyAfterResults = throttleReady()
    run.search = nil
    startSearch(search.index + 1)
end

local function startStep(index)
    local step = auctionSteps[index]
    if not step then
        return startSearch(1)
    end
    local record = { pages = {} }
    run.record.steps[step.name] = record
    run.index = index
    run.step = step
    run.state = { record = record }
    local state = run.state
    whenReady(function(waited)
        record.waitedForThrottle = waited
        record.sentAt = elapsed()
        state.sentAt = preciseTime()
        record.send = call(C_AuctionHouse, "SendBrowseQuery", {
            searchString = "",
            sorts = step.sorts,
            filters = {},
            itemClassFilters = { { classID = step.classID } },
        })
    end)
end

local function finishStep(reason)
    local state = run.state
    local record = state.record
    record.done = reason
    record.stats = state.stats
    record.tookSeconds = state.sentAt and round3(preciseTime() - state.sentAt)
    print(("TCProbe: step %d of %d, %s: %s, %d rows."):format(
        run.index, #auctionSteps, run.step.name, reason, state.stats and state.stats.rows or 0))
    startStep(run.index + 1)
end

-- Counts rows, items and appearances, and how the rows are ordered:
-- priceDrops stays 0 when minPrice never falls from one row to the next,
-- priceRises stays 0 when it never climbs, and itemRuns equals items when
-- all rows of one item sit together.
local function tallyRows(state, rows)
    local stats = state.stats
    for _, row in ipairs(rows) do
        local itemID = row.itemKey.itemID
        local facts = state.items[itemID]
        local newItem = not facts
        if newItem then
            facts = {
                appearanceID = call(C_TransmogCollection, "GetItemInfo", itemID)[1],
                slot = call(C_Item, "GetItemInfoInstant", itemID)[4] or "unknown",
            }
            state.items[itemID] = facts
        end
        local slot = stats.bySlot[facts.slot]
        if not slot then
            slot = { rows = 0, items = 0, appearances = 0 }
            stats.bySlot[facts.slot] = slot
        end
        stats.rows = stats.rows + 1
        slot.rows = slot.rows + 1
        if newItem then
            stats.items = stats.items + 1
            slot.items = slot.items + 1
        end
        if not facts.appearanceID then
            stats.rowsWithoutAppearance = stats.rowsWithoutAppearance + 1
        elseif not state.appearances[facts.appearanceID] then
            state.appearances[facts.appearanceID] = true
            stats.appearances = stats.appearances + 1
            slot.appearances = slot.appearances + 1
        end
        if state.lastPrice and row.minPrice < state.lastPrice then
            stats.priceDrops = stats.priceDrops + 1
        elseif state.lastPrice and row.minPrice > state.lastPrice then
            stats.priceRises = stats.priceRises + 1
        end
        state.lastPrice = row.minPrice
        if itemID ~= state.lastItemID then
            stats.itemRuns = stats.itemRuns + 1
        end
        state.lastItemID = itemID
    end
end

local function headRows(state, rows)
    local head = {}
    for i = 1, math.min(#rows, HEAD_ROWS) do
        local row = rows[i]
        head[i] = {
            itemKey = row.itemKey,
            minPrice = row.minPrice,
            totalQuantity = row.totalQuantity,
            appearanceID = state.items[row.itemKey.itemID].appearanceID,
            name = itemName(row.itemKey),
        }
    end
    return head
end

-- The first rows of the step that asks for them, one per item, become the
-- keys of the search burst.
local function pickSearchKeys(rows)
    local keys, seen = {}, {}
    for _, row in ipairs(rows) do
        if #keys == SEARCH_BURST then
            break
        end
        if not seen[row.itemKey.itemID] then
            seen[row.itemKey.itemID] = true
            keys[#keys + 1] = row.itemKey
        end
    end
    return keys
end

-- added is the payload of AUCTION_HOUSE_BROWSE_RESULTS_ADDED; without it the
-- client has replaced the whole result list.
local function onBrowsePage(added)
    local state = run and run.state
    if not state or not state.sentAt or (added and not state.stats) then
        return
    end
    local record = state.record
    local rows = added
    if not rows then
        local results = call(C_AuctionHouse, "GetBrowseResults")
        rows = results[1]
        if type(rows) ~= "table" then
            record.browseResults = results
            return finishStep("noResults")
        end
        state.items, state.appearances, state.lastPrice, state.lastItemID = {}, {}, nil, nil
        state.stats = { rows = 0, items = 0, appearances = 0, rowsWithoutAppearance = 0,
            priceDrops = 0, priceRises = 0, itemRuns = 0, bySlot = {} }
    end
    tallyRows(state, rows)
    if not added then
        record.head = headRows(state, rows)
        if run.step.searchKeys then
            run.searchKeys = pickSearchKeys(rows)
        end
    end
    local full = call(C_AuctionHouse, "HasFullBrowseResults")[1]
    local page = {
        t = round3(preciseTime() - state.sentAt),
        added = added and true or false,
        rows = #rows,
        total = state.stats.rows,
        full = full,
        readyAfter = throttleReady(),
    }
    record.pages[#record.pages + 1] = page
    run.lastActivity = preciseTime()
    if full then
        return finishStep("full")
    end
    if #record.pages >= run.step.pages then
        return finishStep(run.step.pages == 1 and "firstPageOnly" or "pageCap")
    end
    if #record.pages % 10 == 0 then
        print(("TCProbe: %s, page %d, %d rows so far."):format(run.step.name, #record.pages, state.stats.rows))
    end
    whenReady(function(waited)
        page.waitedBeforeMore = waited
        page.more = call(C_AuctionHouse, "RequestMoreBrowseResults")
    end)
end

local function tickAuctionRun()
    if not run then
        return
    end
    local waiting = run.waiting
    if waiting and throttleReady() then
        run.waiting = nil
        run.lastActivity = preciseTime()
        waiting.fn(round3(preciseTime() - waiting.since))
    elseif preciseTime() - run.lastActivity > STEP_TIMEOUT then
        run.lastActivity = preciseTime()
        if waiting then
            finishRun("throttleNeverReady")
        elseif run.state then
            finishStep("timeout")
        elseif run.search then
            local search = run.search
            search.record.done = "timeout"
            run.search = nil
            startSearch(search.index + 1)
        end
    end
end

local function startAuctionRun(trigger)
    if run then
        run.ticker:Cancel()
    end
    db.auction = {
        trigger = trigger,
        startedAt = date("%H:%M:%S"),
        steps = {},
        searches = {},
        eventCounts = {},
        log = {},
    }
    run = { record = db.auction, t0 = preciseTime(), lastActivity = preciseTime() }
    run.ticker = C_Timer.NewTicker(0.25, tickAuctionRun)
    local thisRun = run
    -- Delayed so the event log shows any query Blizzard's or another addon's
    -- UI sends on open before the first step goes out.
    C_Timer.After(2, function()
        if run == thisRun then
            startStep(1)
        end
    end)
    print("TCProbe: auction recording started. Leave the auction window open and untouched until the 'recording ended' line.")
end

local function stopAuctionRun(reason)
    if not run then
        return
    end
    if run.state then
        run.state.record.done = reason
        run.state.record.stats = run.state.stats
    end
    finishRun(reason)
end

local function probeStatic()
    probeClient()
    probeNamespaces()
    probeEquipped()
    probeModel()
    local transmog = db.namespaces.C_TransmogCollection
    local auction = db.namespaces.C_AuctionHouse
    print(("TCProbe: C_TransmogCollection %s functions, C_AuctionHouse %s functions. Nothing runs by itself: /tcprobe ah records the auction house while its window is open, /tcprobe model shows the model frames."):format(
        transmog and #transmog or "missing", auction and #auction or "missing"))
end

local frame = CreateFrame("Frame")
db = {}

local events = {
    "PLAYER_LOGIN",
    "AUCTION_HOUSE_CLOSED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
}
local unregistered = {}
for _, event in ipairs(events) do
    if not pcall(frame.RegisterEvent, frame, event) then
        unregistered[#unregistered + 1] = event
    end
end

frame:SetScript("OnEvent", function(_, event, payload)
    if event == "PLAYER_LOGIN" then
        TCProbeDB = db
        db.unregisteredEvents = unregistered
        probeStatic()
        probeTooltipHook()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        logAuctionEvent(event)
        stopAuctionRun("auctionHouseClosed")
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        logAuctionEvent(event)
        onBrowsePage()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        logAuctionEvent(event, type(payload) == "table" and #payload or nil)
        if type(payload) == "table" then
            onBrowsePage(payload)
        end
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        logAuctionEvent(event)
        if run and run.state and run.state.sentAt then
            finishStep("browseFailure")
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        logAuctionEvent(event, type(payload) == "table" and payload.itemID or nil)
        onSearchResults(payload)
    else
        logAuctionEvent(event)
    end
end)

SLASH_TCPROBE1 = "/tcprobe"
SlashCmdList["TCPROBE"] = function(msg)
    if msg == "ah" then
        startAuctionRun("slash")
    elseif msg == "model" then
        showModelVariants()
    else
        probeStatic()
    end
end
