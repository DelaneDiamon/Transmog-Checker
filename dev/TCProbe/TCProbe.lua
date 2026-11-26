-- TCProbe: records which transmog and auction APIs exist and return data on
-- this client. Results go to TCProbeDB, which the client writes to
-- WTF\Account\<account>\SavedVariables\TCProbe.lua on /reload or logout.

local MAX_ALT_SOURCES = 8
-- Auction recording: rows kept from the first page of a step, pages read per
-- browse (500 rows each), seconds without an answer before a step is given
-- up, and event log entries kept.
local HEAD_ROWS = 15
local PAGE_CAP = 80
local STEP_TIMEOUT = 20
local LOG_MAX = 1500
-- Searches: keys taken from each of the two kinds of baseline row, seconds a
-- search may go without AUCTION_HOUSE_THROTTLED_MESSAGE_SENT before it counts
-- as unsent, seconds to wait for the result of one that was sent (they came
-- within 0.3), seconds to wait for a key's info before sending again, and
-- seconds after which no further search is started.
local SEARCHES_PER_GROUP = 5
local SEND_GRACE = 1.5
local RESULT_WAIT = 5
local INFO_WAIT = 4
local SEARCH_BUDGET = 60
-- Collected rows kept as a sample, and items per armor type whose can-collect
-- calls are recorded in full.
local SAMPLE_ROWS = 10
local COLLECT_PER_TYPE = 2
-- The wider sample for the collection calls: items taken per armor type and
-- per other item type (shields, off-hands, each weapon type), appearances
-- asked about for every class, items and appearances handled per tick so no
-- frame carries the whole sample, examples kept per distinct outcome, and
-- seconds to wait for the sample's item data.
local SAMPLE_PER_ARMOR_TYPE = 25
local SAMPLE_PER_OTHER_TYPE = 6
local SAMPLE_CLASS_APPEARANCES = 60
local SAMPLE_ITEM_BATCH = 20
local SAMPLE_CLASS_BATCH = 10
local SAMPLE_EXAMPLES = 3
local SAMPLE_DATA_WAIT = 6
-- Tile prototype: Blizzard's wardrobe page is 6 by 3 models of 78 by 104
-- (WardrobeItemsCollectionMixin:OnLoad, WardrobeItemsModelTemplate). Page
-- records kept per session.
local TILE_COLUMNS, TILE_ROWS = 6, 3
local TILE_COUNT = TILE_COLUMNS * TILE_ROWS
local TILE_WIDTH, TILE_HEIGHT, TILE_GAP = 78, 104, 16
local TILE_PAGE_RECORDS = 60
-- Tab test: the library addons add auction house tabs with (Auctionator
-- brings it; the probe does not embed it), the id of the probe's tab, seconds
-- the auction frame's fields are watched after the tab is made, and moments
-- kept.
local TAB_LIBRARY = "LibAHTab-1-0"
local TAB_ID = "TCProbe"
local TAB_WATCH_SECONDS = 30
local TAB_MOMENTS = 100
local TAB_STEPS = "TCProbe: now 1. click the TCProbe tab, 2. click the Buy tab, 3. right-click a food or potion in your bags, 4. /reload."
-- Collect check: items the fixed list is topped up to from the wardrobe's
-- staff and feet categories, seconds to wait for the items' data, items
-- measured per tick, and distinct error texts kept.
local CHECK_TARGET = 270
local CHECK_DATA_WAIT = 7
local CHECK_BATCH = 50
local CHECK_ERRORS = 10
-- Find check: browses and searches it may send, browses per appearance,
-- seconds to wait for the items' data, seconds to wait for a browse's first
-- page, a key's info or a search's result, seconds after which it ends
-- whatever it is doing, variants and other items' names kept per browse, and
-- results read per search.
local FIND_BROWSES = 10
local FIND_SEARCHES = 6
local FIND_PER_APPEARANCE = 3
local FIND_DATA_WAIT = 2
local FIND_ANSWER_WAIT = 3
local FIND_TIME_LIMIT = 25
local FIND_VARIANTS = 20
local FIND_OTHER_NAMES = 5
local FIND_RESULTS_READ = 50

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

local function enum(name, key, fallback)
    local values = Enum and Enum[name]
    return values and values[key] or fallback
end

local function sortBy(name, fallback, reverse)
    return { sortOrder = enum("AuctionHouseSortOrder", name, fallback), reverseSort = reverse or false }
end

local ARMOR, WEAPON = enum("ItemClass", "Armor", 4), enum("ItemClass", "Weapon", 2)
local FEET = enum("InventoryType", "IndexFeetType", 8)
local TWO_HAND = enum("InventoryType", "Index2HweaponType", 17)

-- A browse sorted by Price alone came back in name order. This pair, which is
-- also what Blizzard's window sends, came back by price.
local PRICE_THEN_NAME = { sortBy("Price", 0), sortBy("Name", 1) }
-- BUYOUT is what the last recording sent with every search; Blizzard's window
-- sends the pair.
local BUYOUT = { sortBy("Buyout", 4) }
local BUYOUT_THEN_BID = { sortBy("Buyout", 4), sortBy("Bid", 3) }

-- One itemClassFilters entry per armor type: Blizzard's own slot categories
-- always name the armor type, and a category list holds many entries.
local ARMOR_TYPES = {}
local FEET_BY_ARMOR_TYPE = {}
for i, name in ipairs({ "Cloth", "Leather", "Mail", "Plate" }) do
    local subClassID = enum("ItemArmorSubclass", name, i)
    ARMOR_TYPES[subClassID] = name
    FEET_BY_ARMOR_TYPE[i] = { classID = ARMOR, subClassID = subClassID, inventoryType = FEET }
end

-- Blizzard's window sends a quality value for every quality it wants back,
-- so a filter goes out next to all seven.
local function withAllQualities(name, fallback)
    local filters = { enum("AuctionHouseFilter", name, fallback) }
    for i, quality in ipairs({ "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact" }) do
        filters[i + 1] = enum("AuctionHouseFilter", quality .. "Quality", i + 5)
    end
    return filters
end
local UNCOLLECTED_ONLY = withAllQualities("UncollectedOnly", 1)
local USABLE_ONLY = withAllQualities("UsableOnly", 2)

-- The two item keys whose searches the client never sent in the recording of
-- 2026-11-23. They are searched first, so a failure cannot be blamed on the
-- number of searches before them.
local UNSENT_LAST_RUN = {
    { itemID = 9938, itemSuffix = 14308, itemLevel = 48, battlePetSpeciesID = 0 },
    { itemID = 9944, itemSuffix = 14313, itemLevel = 53, battlePetSpeciesID = 0 },
}

-- The auction recording is a fixed sequence of browses, all sorted by price.
-- armorAll pages through all armor: it shows whether price order holds across
-- pages, and its rows per slot are the baseline for the filtered browses. The
-- feet and weapon steps each send one filter shape, to set against the
-- baseline's rows for that slot. armorAndWeapon reads one page, where a true
-- union of the two classes mixes them. Per-item searches follow, then the
-- collection calls on items picked from the baseline, and on a wider sample
-- of the items the two steps marked sample went through.
local auctionSteps = {
    { name = "armorAll", classFilters = { { classID = ARMOR } }, pages = PAGE_CAP, baseline = true, sample = true },
    { name = "feetNoArmorType", classFilters = { { classID = ARMOR, inventoryType = FEET } }, pages = PAGE_CAP },
    { name = "feetFourArmorTypes", classFilters = FEET_BY_ARMOR_TYPE, pages = PAGE_CAP, collected = true },
    { name = "feetUncollectedOnly", classFilters = FEET_BY_ARMOR_TYPE, filters = UNCOLLECTED_ONLY,
        pages = PAGE_CAP, collected = true },
    { name = "feetUsableOnly", classFilters = FEET_BY_ARMOR_TYPE, filters = USABLE_ONLY, pages = PAGE_CAP },
    { name = "armorAndWeapon", classFilters = { { classID = ARMOR }, { classID = WEAPON } }, pages = 1 },
    { name = "weaponAll", classFilters = { { classID = WEAPON } }, pages = PAGE_CAP, sample = true },
    { name = "weaponTwoHand", classFilters = { { classID = WEAPON, inventoryType = TWO_HAND } }, pages = PAGE_CAP },
}

-- The recording in progress; nil when none is running.
local run

local function elapsed()
    return round3(preciseTime() - run.t0)
end

-- countOnly leaves the event out of the log but still counts it.
local function logAuctionEvent(event, detail, countOnly)
    if not run then
        return
    end
    local record = run.record
    record.eventCounts[event] = (record.eventCounts[event] or 0) + 1
    if not countOnly and #record.log < LOG_MAX then
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

local function keyName(itemKey)
    return itemKey.itemID .. ":" .. (itemKey.itemSuffix or 0) .. ":" .. (itemKey.itemLevel or 0)
end

-- Asking for a key's info makes the client fetch it, so the run remembers
-- which keys it asked about: the searches compare those with the others.
local function itemName(itemKey)
    run.asked[keyName(itemKey)] = true
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

local finishFind

local function finishRun(reason)
    if run.find then
        return finishFind(reason)
    end
    fillMissingNames()
    run.record.finished = reason
    run.record.tookSeconds = elapsed()
    run.ticker:Cancel()
    print(("TCProbe: auction recording ended (%s) after %d seconds. /reload now."):format(
        reason, math.floor(run.record.tookSeconds)))
    run = nil
end

-- The last part of a run: what the collection calls say about armor the
-- character cannot wear, next to cloth it can. The items were picked from the
-- baseline and their data requested then, because these calls answer
-- false, false for an item the client has not loaded.
--
-- After those few items, in full, comes a wider sample in tallies: about 200
-- items across armor types, weapon types and prices. It is measured once as
-- the browse left it and once after its item data was asked for, a batch per
-- tick, and then 60 of its appearances are put to every class.

-- debugprofilestop counts milliseconds, much finer than the frame clock.
local function milliseconds()
    return call(_G, "debugprofilestop")[1] or preciseTime() * 1000
end

-- call, timed: per function name the number of calls, their total and the
-- worst single one, in milliseconds. The figures include this wrapper; the
-- entry for "type", a call that does nothing, shows how much that is.
local function timedCall(timings, ns, name, ...)
    local started = milliseconds()
    local result = call(ns, name, ...)
    local took = milliseconds() - started
    local timing = timings[name]
    if not timing then
        timing = { calls = 0, totalMs = 0, worstMs = 0 }
        timings[name] = timing
    end
    timing.calls = timing.calls + 1
    timing.totalMs = timing.totalMs + took
    timing.worstMs = math.max(timing.worstMs, took)
    return result
end

-- Counts one outcome and keeps the first few items that showed it.
local function countOutcome(tally, outcome, item)
    tally.counts[outcome] = (tally.counts[outcome] or 0) + 1
    local examples = tally.examples[outcome]
    if not examples then
        examples = {}
        tally.examples[outcome] = examples
    end
    if #examples < SAMPLE_EXAMPLES then
        examples[#examples + 1] = { itemID = item.itemID, sourceID = item.sourceID, appearanceID = item.appearanceID }
    end
end

local function countIn(tallies, key, outcome)
    local tally = tallies[key]
    if not tally then
        tally = {}
        tallies[key] = tally
    end
    tally[outcome] = (tally[outcome] or 0) + 1
end

-- From every item type the two sample steps saw, items spaced evenly through
-- its candidates. Those are in price order, so cheap and dear items, and with
-- them the qualities, all get in.
local function pickSample()
    local items, byType, typeNames = {}, {}, {}
    for typeName in pairs(run.candidates) do
        typeNames[#typeNames + 1] = typeName
    end
    table.sort(typeNames)
    for _, typeName in ipairs(typeNames) do
        local candidates = run.candidates[typeName]
        local take = math.min(#candidates, candidates.armorType and SAMPLE_PER_ARMOR_TYPE or SAMPLE_PER_OTHER_TYPE)
        for i = 1, take do
            items[#items + 1] = candidates[math.floor((i - 0.5) * #candidates / take) + 1]
        end
        byType[typeName] = take
    end
    return items, byType
end

-- The sample's appearances that every class is asked about: spaced evenly
-- through the sample, each appearance once.
local function pickClassItems(items)
    local picked, seen = {}, {}
    local stride = math.max(1, #items / SAMPLE_CLASS_APPEARANCES)
    local position = 1
    while math.floor(position) <= #items and #picked < SAMPLE_CLASS_APPEARANCES do
        local item = items[math.floor(position)]
        if not seen[item.appearanceID] then
            seen[item.appearanceID] = true
            picked[#picked + 1] = item
        end
        position = position + stride
    end
    return picked
end

-- The class IDs Blizzard's wardrobe offers in its class dropdown, with the
-- class's file name ("WARLOCK") as the label. Without that list every ID up
-- to 20 is tried, since the IDs have gaps; without any answer the nine IDs of
-- this build's class table are used.
local function classList()
    local ids = call(C_SpecializationInfo, "GetAllClassIDs")[1]
    if type(ids) ~= "table" then
        ids = {}
        for classID = 1, 20 do
            ids[classID] = classID
        end
    end
    local classes = {}
    for _, classID in ipairs(ids) do
        local file = call(_G, "GetClassInfo", classID)[2]
        if file then
            classes[#classes + 1] = { id = classID, file = file }
        end
    end
    if #classes == 0 then
        for i, classID in ipairs({ 1, 2, 3, 4, 5, 7, 8, 9, 11 }) do
            classes[i] = { id = classID, file = "class" .. classID }
        end
    end
    return classes
end

-- One item of the sample, in the pass "before" or "after" its data was asked
-- for. Collected is worked out two ways, to see whether the single call can
-- stand in for the loop; the two can-collect calls are tallied by item type
-- and quality.
local function measureItem(item, pass)
    local TC = C_TransmogCollection
    local sample = run.record.canCollect.sample
    local timings = sample.timings
    local cached = call(C_Item, "IsItemDataCachedByID", item.itemID)[1]
    timedCall(timings, _G, "type", 0)

    local byLoop = false
    local sources = timedCall(timings, TC, "GetAllAppearanceSources", item.appearanceID)[1]
    for _, sourceID in ipairs(type(sources) == "table" and sources or {}) do
        if timedCall(timings, TC, "PlayerHasTransmogItemModifiedAppearance", sourceID)[1] == true then
            byLoop = true
            break
        end
    end
    local info = timedCall(timings, TC, "GetAppearanceInfoBySource", item.sourceID)
    local byInfo = "nothing"
    if type(info[1]) == "table" then
        byInfo = info[1].appearanceIsCollected
    elseif info.error or info.missing then
        byInfo = "error"
    end
    local collected = sample.collected[pass]
    local verdict = (byInfo == "nothing" and "infoNothing") or (byInfo == "error" and "infoError")
        or (byInfo == byLoop and "agree") or "disagree"
    collected[verdict] = (collected[verdict] or 0) + 1
    countOutcome(collected, ("cached=%s loop=%s info=%s"):format(
        tostring(cached), tostring(byLoop), tostring(byInfo)), item)

    local account = timedCall(timings, TC, "AccountCanCollectSource", item.sourceID)
    local player = timedCall(timings, TC, "PlayerCanCollectSource", item.sourceID)
    local outcome = ("account=%s,%s player=%s,%s"):format(
        tostring(account[1]), tostring(account[2]), tostring(player[1]), tostring(player[2]))
    local quality = call(C_Item, "GetItemQualityByID", item.itemID)[1]
    local canCollect = sample.canCollect[pass]
    countOutcome(canCollect, outcome, item)
    countIn(canCollect.byType, item.type, outcome)
    countIn(canCollect.byQuality, quality == nil and "unknown" or quality, outcome)
end

-- One appearance put to every class: which classes get sources back. Tallied
-- per item type, so the armor types and weapon types each class may use can
-- be read off.
local function measureClasses(item)
    local sample = run.record.canCollect.sample
    local use = sample.classUse
    local valid = {}
    use.appearances = use.appearances + 1
    countIn(use.byType, item.type, "appearances")
    for _, class in ipairs(sample.classes) do
        local sources = timedCall(sample.timings, C_TransmogCollection, "GetValidAppearanceSourcesForClass",
            item.appearanceID, class.id)[1]
        if type(sources) ~= "table" then
            countIn(use.byType, item.type, "noAnswer")
        elseif #sources > 0 then
            countIn(use.byType, item.type, class.file)
            valid[#valid + 1] = class.file
        end
    end
    countOutcome(use, item.type .. ": " .. (valid[1] and table.concat(valid, " ") or "no class"), item)
end

local function startCanCollect()
    run.search, run.state = nil, nil
    run.step = { name = "canCollect" }
    local items, byType = pickSample()
    local function tally(more)
        more = more or {}
        more.counts, more.examples = {}, {}
        return more
    end
    run.record.canCollect = {
        playerClass = call(_G, "UnitClass", "player"),
        items = {},
        sample = {
            items = #items,
            byType = byType,
            classes = classList(),
            collected = { before = tally(), after = tally() },
            canCollect = {
                before = tally({ byType = {}, byQuality = {} }),
                after = tally({ byType = {}, byQuality = {} }),
            },
            classUse = tally({ appearances = 0, byType = {} }),
            timings = {},
        },
    }
    run.collect = { started = preciseTime(), since = preciseTime(), phase = "before", index = 1,
        items = items, classItems = pickClassItems(items) }
    run.lastActivity = preciseTime()
end

local function tickCanCollect(now)
    local TC = C_TransmogCollection
    local collect = run.collect
    local record = run.record.canCollect
    local sample = record.sample
    run.lastActivity = now
    if collect.phase == "before" or collect.phase == "after" then
        local last = math.min(collect.index + SAMPLE_ITEM_BATCH - 1, #collect.items)
        for i = collect.index, last do
            local item = collect.items[i]
            measureItem(item, collect.phase)
            if collect.phase == "before" then
                -- asked for only now, so this pass saw the item as the browse left it
                call(C_Item, "RequestLoadItemDataByID", item.itemID)
            end
        end
        collect.index = last + 1
        if last == #collect.items then
            collect.phase = collect.phase == "before" and "load" or "classes"
            collect.index, collect.since = 1, now
        end
    elseif collect.phase == "load" then
        local uncached = 0
        for _, items in ipairs({ collect.items, run.collectItems }) do
            for _, item in ipairs(items) do
                if call(C_Item, "IsItemDataCachedByID", item.itemID)[1] == false then
                    uncached = uncached + 1
                end
            end
        end
        if uncached > 0 and now - collect.since <= SAMPLE_DATA_WAIT then
            return
        end
        sample.waitedForData = round3(now - collect.since)
        sample.uncachedAfterWait = uncached
        record.waitedForData = round3(now - collect.started)
        for i, item in ipairs(run.collectItems) do
            item.name = call(C_Item, "GetItemNameByID", item.itemID)[1]
            item.cached = call(C_Item, "IsItemDataCachedByID", item.itemID)
            item.accountCanCollect = call(TC, "AccountCanCollectSource", item.sourceID)
            item.playerCanCollect = call(TC, "PlayerCanCollectSource", item.sourceID)
            item.hasSource = call(TC, "PlayerHasTransmogItemModifiedAppearance", item.sourceID)
            item.sourceInfo = call(TC, "GetSourceInfo", item.sourceID)
            item.appearanceInfo = call(TC, "GetAppearanceInfoBySource", item.sourceID)
            record.items[i] = item
        end
        collect.phase = "after"
    else
        local last = math.min(collect.index + SAMPLE_CLASS_BATCH - 1, #collect.classItems)
        for i = collect.index, last do
            measureClasses(collect.classItems[i])
        end
        collect.index = last + 1
        if last == #collect.classItems then
            for _, timing in pairs(sample.timings) do
                timing.totalMs, timing.worstMs = round3(timing.totalMs), round3(timing.worstMs)
            end
            print(("TCProbe: collection calls recorded for %d items in full, %d sampled items and %d appearances by class."):format(
                #record.items, sample.items, sample.classUse.appearances))
            finishRun("finished")
        end
    end
end

local function keyInfoLoaded(itemKey)
    return type(call(C_AuctionHouse, "GetItemKeyInfo", itemKey)[1]) == "table"
end

-- One attempt at a search. The first repeats the last recording's call; a
-- later one names the remedy it follows.
local function sendSearch(search, remedy)
    local attempt = { remedy = remedy }
    local attempts = search.record.attempts
    attempts[#attempts + 1] = attempt
    search.attempt = attempt
    whenReady(function(waited)
        local itemKey = search.record.itemKey
        attempt.waitedForThrottle = waited
        attempt.keyInfo = keyInfoLoaded(itemKey)
        attempt.itemCached = call(C_Item, "IsItemDataCachedByID", itemKey.itemID)[1]
        attempt.hasResultsBefore = call(C_AuctionHouse, "HasSearchResults", itemKey)[1]
        search.sentAt = preciseTime()
        attempt.send = call(C_AuctionHouse, "SendSearchQuery", itemKey,
            remedy == "twoSorts" and BUYOUT_THEN_BID or BUYOUT, false)
        attempt.readyAfterSend = throttleReady()
    end)
end

local startSearch

local function endSearch(done)
    local search = run.search
    search.record.done = done
    run.search = nil
    startSearch(search.index + 1)
end

function startSearch(index)
    local list = run.searchList
    if index > #list and not run.repeatAdded then
        -- One more: a key the client already holds results for. Blizzard's
        -- window never sends a search for such a key; it asks for a refresh.
        run.repeatAdded = true
        for i, record in ipairs(run.record.searches) do
            if record.done == "result" then
                list[#list + 1] = { itemKey = record.itemKey, group = "repeatOfSearch" .. i }
                break
            end
        end
    end
    local record = list[index]
    if not record or preciseTime() - run.searchesSince > SEARCH_BUDGET then
        run.record.searchesLeftOut = record and #list - index + 1 or 0
        local atOnce, later, never = 0, 0, 0
        for _, search in ipairs(run.record.searches) do
            if search.done ~= "result" then
                never = never + 1
            elseif #search.attempts == 1 then
                atOnce = atOnce + 1
            else
                later = later + 1
            end
        end
        print(("TCProbe: %d searches: %d answered at once, %d after another attempt, %d never."):format(
            #run.record.searches, atOnce, later, never))
        return startCanCollect()
    end
    record.attempts = {}
    run.record.searches[index] = record
    run.step = { name = "search" .. index }
    run.state = nil
    run.search = { index = index, record = record }
    sendSearch(run.search)
end

-- A search is unsent when no AUCTION_HOUSE_THROTTLED_MESSAGE_SENT follows the
-- call. Blizzard's window only searches a key whose info it already shows, so
-- the first remedy is to get that info and send again; the second is to send
-- Blizzard's two sorts.
local function tickSearch(now)
    local search = run.search
    local record, attempt = search.record, search.attempt
    if search.infoSince then
        local loaded = keyInfoLoaded(record.itemKey)
        if loaded or now - search.infoSince > INFO_WAIT then
            record.infoWait.seconds = round3(now - search.infoSince)
            record.infoWait.arrived = loaded
            search.infoSince = nil
            sendSearch(search, "afterKeyInfo")
        end
    elseif search.sentAt and not attempt.messageSent and now - search.sentAt > SEND_GRACE then
        attempt.unsent = true
        attempt.hasResultsAfter = call(C_AuctionHouse, "HasSearchResults", record.itemKey)[1]
        search.sentAt = nil
        if not attempt.remedy and not attempt.keyInfo then
            record.infoWait = { requestLoad = call(C_Item, "RequestLoadItemDataByID", record.itemKey.itemID) }
            search.infoSince = now
        elseif attempt.remedy ~= "twoSorts" then
            sendSearch(search, "twoSorts")
        else
            endSearch("unsent")
        end
    elseif search.sentAt and now - search.sentAt > RESULT_WAIT then
        endSearch("sentWithoutResult")
    end
end

local function onMessageSent()
    local search = run and run.search
    if search and search.sentAt and not search.attempt.messageSent then
        search.attempt.messageSent = round3(preciseTime() - search.sentAt)
    end
end

local function onSearchResults(itemKey)
    local search = run and run.search
    if not search or not search.sentAt or type(itemKey) ~= "table"
        or itemKey.itemID ~= search.record.itemKey.itemID
        or itemKey.itemSuffix ~= search.record.itemKey.itemSuffix then
        return
    end
    local attempt = search.attempt
    attempt.tookSeconds = round3(preciseTime() - search.sentAt)
    attempt.count = call(C_AuctionHouse, "GetNumItemSearchResults", search.record.itemKey)
    attempt.full = call(C_AuctionHouse, "HasFullItemSearchResults", search.record.itemKey)
    attempt.hasResultsAfter = call(C_AuctionHouse, "HasSearchResults", search.record.itemKey)[1]
    attempt.readyAfterResults = throttleReady()
    endSearch("result")
end

-- Search order: the two keys that went unsent last time, then rows of the
-- baseline's first page, taking turns between a row the probe never asked
-- item key info for (from the end of the page) and one it did (the head
-- rows), so that neither kind sits only early or only late.
local function startSearches()
    local list, taken = {}, {}
    for i, key in ipairs(UNSENT_LAST_RUN) do
        local found = run.unsentFound[i]
        list[i] = { itemKey = found and found.itemKey or key, group = "unsentLastRun",
            listed = found and true or false, minPrice = found and found.minPrice }
        taken[key.itemID] = true
    end
    local keys = run.pageOneKeys or {}
    local notAsked, asked = {}, {}
    for i = #keys, 1, -1 do
        local key = keys[i]
        if #notAsked < SEARCHES_PER_GROUP and not taken[key.itemID] and not run.asked[keyName(key)] then
            taken[key.itemID] = true
            notAsked[#notAsked + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        if #asked < SEARCHES_PER_GROUP and not taken[key.itemID] and run.asked[keyName(key)] then
            taken[key.itemID] = true
            asked[#asked + 1] = key
        end
    end
    for i = 1, SEARCHES_PER_GROUP do
        if notAsked[i] then
            list[#list + 1] = { itemKey = notAsked[i], group = "notAskedBefore" }
        end
        if asked[i] then
            list[#list + 1] = { itemKey = asked[i], group = "askedBefore" }
        end
    end
    run.searchList = list
    run.searchesSince = preciseTime()
    startSearch(1)
end

local function startStep(index)
    local step = auctionSteps[index]
    if not step then
        return startSearches()
    end
    local record = { pages = {}, classFilters = step.classFilters, filters = step.filters or {} }
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
            sorts = PRICE_THEN_NAME,
            filters = record.filters,
            itemClassFilters = step.classFilters,
        })
    end)
end

local function finishStep(reason)
    local state = run.state
    local record = state.record
    record.done = reason
    record.stats = state.stats
    record.tookSeconds = state.sentAt and round3(preciseTime() - state.sentAt)
    local rows = state.stats and state.stats.rows or 0
    print(("TCProbe: step %d of %d, %s: %s, %d rows."):format(
        run.index, #auctionSteps, run.step.name, reason, rows))
    if run.step.baseline and rows == 0 then
        -- every later part is measured against these rows or picks from them
        return finishRun("noBaseline")
    end
    startStep(run.index + 1)
end

-- Whether the character holds this item's own source, and whether it holds
-- any source of the same appearance: the two things "uncollected" could mean.
local function addCollected(facts)
    local TC = C_TransmogCollection
    if not facts.sourceID then
        return
    end
    facts.sourceCollected = call(TC, "PlayerHasTransmogItemModifiedAppearance", facts.sourceID)[1] == true
    facts.appearanceCollected = facts.sourceCollected
    local sources = call(TC, "GetAllAppearanceSources", facts.appearanceID)[1]
    if not facts.appearanceCollected and type(sources) == "table" then
        for _, sourceID in ipairs(sources) do
            if call(TC, "PlayerHasTransmogItemModifiedAppearance", sourceID)[1] == true then
                facts.appearanceCollected = true
                break
            end
        end
    end
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
            local instant = call(C_Item, "GetItemInfoInstant", itemID)
            local transmog = call(C_TransmogCollection, "GetItemInfo", itemID)
            facts = {
                appearanceID = transmog[1],
                sourceID = transmog[2],
                slot = instant[4] or "unknown",
                classID = instant[6] or "unknown",
                subClassID = instant[7] or "unknown",
            }
            if run.step.collected then
                addCollected(facts)
            end
            state.items[itemID] = facts
            if run.step.sample and facts.sourceID and not run.sampleSeen[itemID] then
                -- A candidate for the wider sample, filed under its item type
                -- ("Armor/Cloth", "Weapon/Staves") in the order the browse
                -- gave it, which is by price.
                run.sampleSeen[itemID] = true
                local typeName = tostring(instant[2]) .. "/" .. tostring(instant[3])
                local candidates = run.candidates[typeName]
                if not candidates then
                    candidates = { armorType = facts.classID == ARMOR and ARMOR_TYPES[facts.subClassID] ~= nil }
                    run.candidates[typeName] = candidates
                end
                candidates[#candidates + 1] = { itemID = itemID, type = typeName,
                    appearanceID = facts.appearanceID, sourceID = facts.sourceID }
            end
        end
        local slot = stats.bySlot[facts.slot]
        if not slot then
            slot = { rows = 0, items = 0, appearances = 0, bySubclass = {} }
            stats.bySlot[facts.slot] = slot
        end
        stats.rows = stats.rows + 1
        slot.rows = slot.rows + 1
        slot.bySubclass[facts.subClassID] = (slot.bySubclass[facts.subClassID] or 0) + 1
        stats.byClass[facts.classID] = (stats.byClass[facts.classID] or 0) + 1
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
        if facts.sourceCollected then
            stats.rowsSourceCollected = stats.rowsSourceCollected + 1
        end
        if facts.appearanceCollected then
            stats.rowsAppearanceCollected = stats.rowsAppearanceCollected + 1
            local sample = state.record.collectedSample
            if #sample < SAMPLE_ROWS then
                sample[#sample + 1] = { itemKey = row.itemKey, minPrice = row.minPrice,
                    appearanceID = facts.appearanceID, sourceID = facts.sourceID,
                    sourceCollected = facts.sourceCollected }
            end
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

-- What the later parts take from the baseline: the first page's keys for the
-- searches, the two keys that went unsent last time wherever they are listed,
-- and the cheapest few items of each armor type for the can-collect calls.
-- Cloaks are left out: they are cloth that every class wears.
local function noteBaselineRows(state, rows, firstPage)
    if firstPage then
        run.pageOneKeys = {}
        for i, row in ipairs(rows) do
            run.pageOneKeys[i] = row.itemKey
        end
    end
    for _, row in ipairs(rows) do
        local itemKey = row.itemKey
        for i, key in ipairs(UNSENT_LAST_RUN) do
            if not run.unsentFound[i] and itemKey.itemID == key.itemID and itemKey.itemSuffix == key.itemSuffix then
                run.unsentFound[i] = { itemKey = itemKey, minPrice = row.minPrice }
            end
        end
        local facts = state.items[itemKey.itemID]
        local armorType = facts.classID == ARMOR and ARMOR_TYPES[facts.subClassID]
        if armorType and facts.sourceID and not run.collectPicked[itemKey.itemID]
            and facts.slot ~= "INVTYPE_CLOAK" and (run.collectCount[armorType] or 0) < COLLECT_PER_TYPE then
            run.collectPicked[itemKey.itemID] = true
            run.collectCount[armorType] = (run.collectCount[armorType] or 0) + 1
            run.collectItems[#run.collectItems + 1] = {
                itemID = itemKey.itemID,
                armorType = armorType,
                slot = facts.slot,
                minPrice = row.minPrice,
                appearanceID = facts.appearanceID,
                sourceID = facts.sourceID,
                requestLoad = call(C_Item, "RequestLoadItemDataByID", itemKey.itemID),
            }
        end
    end
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
            priceDrops = 0, priceRises = 0, itemRuns = 0, bySlot = {}, byClass = {} }
        if run.step.collected then
            state.stats.rowsSourceCollected, state.stats.rowsAppearanceCollected = 0, 0
            record.collectedSample = {}
        end
    end
    local priceBefore, dropsBefore = state.lastPrice, state.stats.priceDrops
    tallyRows(state, rows)
    if run.step.baseline then
        noteBaselineRows(state, rows, not added)
    end
    if not added then
        record.head = headRows(state, rows)
    end
    local full = call(C_AuctionHouse, "HasFullBrowseResults")[1]
    local first, last = rows[1], rows[#rows]
    -- drops counts rows priced below the row before them, the first row
    -- against the last row of the page before; boundaryDrop is that one pair.
    local page = {
        t = round3(preciseTime() - state.sentAt),
        added = added and true or false,
        rows = #rows,
        total = state.stats.rows,
        full = full,
        readyAfter = throttleReady(),
        firstPrice = first and first.minPrice,
        lastPrice = last and last.minPrice,
        drops = state.stats.priceDrops - dropsBefore,
        boundaryDrop = (priceBefore and first and first.minPrice < priceBefore) or false,
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

-- The find check: whether one appearance can be turned into auction rows by
-- browsing for the names of its items. It runs on the auction run's ticker,
-- throttle and event log, with its own record and its own limits.
--
-- One item of each appearance, from the recordings of 2026-11-24, and what it
-- is there for. The appearance and its items are read from the client.
local FIND_ITEMS = {
    { itemID = 6537, why = "random-suffix green, world drop: three suffixes were listed" },
    { itemID = 2569, why = "crafted green; the appearance's other item binds on pickup" },
    { itemID = 1367, why = "grey world drop" },
    { itemID = 11287, why = "weapon; three crafted items that can be traded share the appearance" },
    { itemID = 9938, why = "random-suffix green, world drop: one auction was listed" },
    { itemID = 2535, why = "vendor weapon, unlikely to be listed; its other items bind on pickup or never loaded" },
}

-- The collect check recorded these as 1 and 2 for bind on pickup and on
-- equip; Quest is the name and value retail gives quest items, unverified.
local BIND_ON_PICKUP, BIND_QUEST = enum("ItemBind", "OnAcquire", 1), enum("ItemBind", "Quest", 4)

function finishFind(reason)
    local find, record = run.find, run.record
    for _, appearance in ipairs(record.appearances) do
        for _, browse in ipairs(appearance.browses) do
            for _, other in ipairs(browse.otherExamples or {}) do
                other.name = other.name or itemName(other.itemKey)
            end
        end
    end
    -- what was in flight when the check was stopped
    if find.browse and not find.browse.record.done then
        find.browse.record.done = reason
    end
    if find.search and not find.search.record.done then
        find.search.record.done = reason
    end
    record.resultFields = {}
    for field in pairs(find.resultFields) do
        record.resultFields[#record.resultFields + 1] = field
    end
    table.sort(record.resultFields)
    record.finished = reason
    record.tookSeconds = elapsed()
    run.ticker:Cancel()
    print(("TCProbe: find check ended (%s) after %d seconds, %d browses, %d searches. /reload now."):format(
        reason, math.floor(record.tookSeconds), record.browses, record.searches))
    run = nil
end

-- The searches: for each appearance that had a matching row, its cheapest
-- one. A search is sent only once the key's info is there; the client drops
-- it otherwise.
local function nextFindSearch()
    local find = run.find
    find.search = nil
    local appearance = table.remove(find.searchQueue, 1)
    if not appearance then
        return finishRun("finished")
    end
    local cheapest = find.cheapest[appearance]
    local record = { itemKey = cheapest.itemKey, minPrice = cheapest.minPrice }
    appearance.search = record
    find.search = { record = record, infoSince = preciseTime() }
    find.phase = "search"
    run.step = { name = "findSearch" .. (run.record.searches + 1) }
    run.lastActivity = preciseTime()
end

local function startFindSearches()
    local find = run.find
    find.searchQueue = {}
    for _, appearance in ipairs(run.record.appearances) do
        if find.cheapest[appearance] and #find.searchQueue < FIND_SEARCHES then
            find.searchQueue[#find.searchQueue + 1] = appearance
        end
    end
    nextFindSearch()
end

-- One browse for an item's name, sorted by price. Without a class filter the
-- query has no itemClassFilters field, which is what Blizzard's window sends
-- when no category is selected (AuctionHouseFrameMixin:SendBrowseQueryInternal).
-- Unverified: a browse with a name in searchString has never been recorded.
local function nextFindBrowse()
    local find = run.find
    find.browse = nil
    local entry = table.remove(find.queue, 1)
    if not entry then
        return startFindSearches()
    end
    local query = { searchString = entry.source.name, sorts = PRICE_THEN_NAME, filters = {},
        itemClassFilters = entry.classFilter }
    local record = { itemID = entry.source.itemID, query = query, classFilterVariation = entry.classFilter and true or nil }
    local browse = { entry = entry, record = record }
    entry.appearance.browses[#entry.appearance.browses + 1] = record
    find.browse = browse
    find.phase = "browse"
    run.step = { name = "findBrowse" .. (run.record.browses + 1) }
    whenReady(function(waited)
        record.waitedForThrottle = waited
        record.sentAt = elapsed()
        run.record.browses = run.record.browses + 1
        browse.sentAt = preciseTime()
        record.send = call(C_AuctionHouse, "SendBrowseQuery", query)
        record.readyAfterSend = throttleReady()
    end)
end

-- After the first browse that found its item, the same name goes out once
-- more with the item's class and subclass as the filter.
local function endFindBrowse(done)
    local find = run.find
    local browse = find.browse
    browse.record.done = done
    if not find.variationQueued and (browse.record.matching or 0) > 0 then
        find.variationQueued = true
        local instant = call(C_Item, "GetItemInfoInstant", browse.record.itemID)
        if instant[6] then
            table.insert(find.queue, 1, { appearance = browse.entry.appearance, source = browse.entry.source,
                classFilter = { { classID = instant[6], subClassID = instant[7] } } })
        end
    end
    nextFindBrowse()
end

-- The first page of a browse: rows of the wanted item against rows of other
-- items, the wanted item's variants, and whether the page is in price order.
local function tallyFindRows(browse, rows)
    local find, record = run.find, browse.record
    local appearance = browse.entry.appearance
    record.rows, record.matching, record.others, record.otherItems, record.variantCount = #rows, 0, 0, 0, 0
    record.priceDrops, record.priceRises, record.matchingPriceDrops = 0, 0, 0
    record.variants, record.otherExamples = {}, {}
    local seen, lastPrice, lastMatchingPrice = {}, nil, nil
    for _, row in ipairs(rows) do
        local key = row.itemKey
        if key.itemID == record.itemID then
            record.matching = record.matching + 1
            local variant = (key.itemSuffix or 0) .. ":" .. (key.itemLevel or 0)
            if not seen[variant] then
                seen[variant] = true
                record.variantCount = record.variantCount + 1
                if #record.variants < FIND_VARIANTS then
                    record.variants[#record.variants + 1] = { itemSuffix = key.itemSuffix, itemLevel = key.itemLevel,
                        minPrice = row.minPrice, totalQuantity = row.totalQuantity }
                end
            end
            if lastMatchingPrice and row.minPrice < lastMatchingPrice then
                record.matchingPriceDrops = record.matchingPriceDrops + 1
            end
            lastMatchingPrice = row.minPrice
            local cheapest = find.cheapest[appearance]
            if not cheapest or row.minPrice < cheapest.minPrice then
                find.cheapest[appearance] = { itemKey = key, minPrice = row.minPrice }
                -- asked now, so the key's info is there when its search is due
                itemName(key)
            end
        else
            record.others = record.others + 1
            if not seen[key.itemID] then
                seen[key.itemID] = true
                record.otherItems = record.otherItems + 1
                if #record.otherExamples < FIND_OTHER_NAMES then
                    record.otherExamples[#record.otherExamples + 1] = { itemKey = key, name = itemName(key) }
                end
            end
        end
        if lastPrice and row.minPrice < lastPrice then
            record.priceDrops = record.priceDrops + 1
        elseif lastPrice and row.minPrice > lastPrice then
            record.priceRises = record.priceRises + 1
        end
        lastPrice = row.minPrice
    end
end

-- Only the first page is read: full says whether the client holds more.
local function onFindPage()
    local browse = run and run.find and run.find.browse
    if not browse or not browse.sentAt or browse.record.done then
        return
    end
    local record = browse.record
    record.seconds = round3(preciseTime() - browse.sentAt)
    local results = call(C_AuctionHouse, "GetBrowseResults")
    if type(results[1]) ~= "table" then
        record.browseResults = results
        return endFindBrowse("noResults")
    end
    record.full = call(C_AuctionHouse, "HasFullBrowseResults")[1]
    tallyFindRows(browse, results[1])
    endFindBrowse("firstPage")
end

local function onFindFailure()
    local browse = run and run.find and run.find.browse
    if browse and browse.sentAt and not browse.record.done then
        endFindBrowse("browseFailure")
    end
end

local function onFindMessageSent()
    local find = run and run.find
    local sent = find and (find.browse or find.search)
    if sent and sent.sentAt and not sent.record.messageSent then
        sent.record.messageSent = round3(preciseTime() - sent.sentAt)
    end
end

-- The search's answer: how many auctions, and of the first few the one with
-- the lowest buyout, or the first when none has a buyout. The fields are
-- those of ItemSearchResultInfo in this build's API documentation; the
-- recordings never held one, so resultFields keeps every name the client gave.
local function onFindSearchResults(itemKey)
    local search = run and run.find and run.find.search
    if not search or not search.sentAt or search.record.done or type(itemKey) ~= "table"
        or itemKey.itemID ~= search.record.itemKey.itemID
        or itemKey.itemSuffix ~= search.record.itemKey.itemSuffix then
        return
    end
    local record = search.record
    local key = record.itemKey
    record.seconds = round3(preciseTime() - search.sentAt)
    record.results = call(C_AuctionHouse, "GetNumItemSearchResults", key)[1]
    record.full = call(C_AuctionHouse, "HasFullItemSearchResults", key)[1]
    local best, bestIndex
    for i = 1, math.min(type(record.results) == "number" and record.results or 0, FIND_RESULTS_READ) do
        local result = call(C_AuctionHouse, "GetItemSearchResultInfo", key, i)[1]
        if type(result) == "table" then
            for field in pairs(result) do
                run.find.resultFields[field] = true
            end
            if not best or (result.buyoutAmount and (not best.buyoutAmount or result.buyoutAmount < best.buyoutAmount)) then
                best, bestIndex = result, i
            end
        end
    end
    if best then
        record.cheapest = { index = bestIndex, buyoutAmount = best.buyoutAmount, bidAmount = best.bidAmount,
            minBid = best.minBid, quantity = best.quantity, timeLeft = best.timeLeft,
            timeLeftSeconds = best.timeLeftSeconds }
    end
    record.done = "result"
    nextFindSearch()
end

-- Once the items' data is in: what each source's item is, which items are
-- left out and why, and a browse for each of the others. One browse is held
-- back for the class filter variation. GetItemInfo's order is the one the
-- collect check recorded on this client: 1 name, 3 quality, 14 bind type.
-- AccountCanCollectSource is not asked: it says no for items that can be
-- collected.
local function planFind()
    local find = run.find
    local names = {}
    find.queue, find.cheapest = {}, {}
    for _, appearance in ipairs(run.record.appearances) do
        local planned = 0
        for _, source in ipairs(appearance.sources) do
            if source.itemID then
                local info = call(C_Item, "GetItemInfo", source.itemID)
                source.name = info[1] or call(C_Item, "GetItemNameByID", source.itemID)[1]
                source.quality, source.bindType = info[3], info[14]
            end
            source.nameLoaded = source.name ~= nil
            if not source.name then
                source.skipped = "nameNotLoaded"
            elseif source.bindType == BIND_ON_PICKUP then
                source.skipped = "bindOnPickup"
            elseif source.bindType == BIND_QUEST then
                source.skipped = "questItem"
            elseif names[source.name] then
                source.skipped = "nameAlreadyBrowsed"
            elseif planned >= FIND_PER_APPEARANCE then
                source.skipped = "appearanceBudget"
            elseif #find.queue >= FIND_BROWSES - 1 then
                source.skipped = "browseBudget"
            else
                source.skipped = false
                names[source.name] = true
                planned = planned + 1
                find.queue[#find.queue + 1] = { appearance = appearance, source = source }
            end
        end
    end
end

local function tickFind(now)
    local find = run.find
    if find.phase == "load" then
        local missing = 0
        for _, appearance in ipairs(run.record.appearances) do
            for _, source in ipairs(appearance.sources) do
                if source.itemID and call(C_Item, "IsItemDataCachedByID", source.itemID)[1] == false then
                    missing = missing + 1
                end
            end
        end
        if missing > 0 and now - find.since <= FIND_DATA_WAIT then
            return
        end
        run.record.waitedForData = round3(now - find.since)
        planFind()
        nextFindBrowse()
    elseif find.phase == "browse" then
        if find.browse.sentAt and now - find.browse.sentAt > FIND_ANSWER_WAIT then
            endFindBrowse("noAnswer")
        end
    else
        local search = find.search
        local record = search.record
        if search.infoSince then
            if keyInfoLoaded(record.itemKey) then
                record.keyInfoSeconds = round3(now - search.infoSince)
                search.infoSince = nil
                whenReady(function(waited)
                    record.waitedForThrottle = waited
                    run.record.searches = run.record.searches + 1
                    search.sentAt = preciseTime()
                    record.send = call(C_AuctionHouse, "SendSearchQuery", record.itemKey, BUYOUT, false)
                    record.readyAfterSend = throttleReady()
                end)
            elseif now - search.infoSince > FIND_ANSWER_WAIT then
                record.done = "noKeyInfo"
                nextFindSearch()
            end
        elseif search.sentAt and not record.messageSent and now - search.sentAt > SEND_GRACE then
            -- as in the auction run: no AUCTION_HOUSE_THROTTLED_MESSAGE_SENT, so the client dropped it
            record.done = "unsent"
            nextFindSearch()
        elseif search.sentAt and now - search.sentAt > FIND_ANSWER_WAIT then
            record.done = "sentWithoutResult"
            nextFindSearch()
        end
    end
end

local function tickAuctionRun()
    if not run then
        return
    end
    local now = preciseTime()
    if run.find and now - run.t0 > FIND_TIME_LIMIT then
        return finishRun("timeLimit")
    end
    local waiting = run.waiting
    if waiting and throttleReady() then
        run.waiting = nil
        run.lastActivity = now
        waiting.fn(round3(now - waiting.since))
    elseif now - run.lastActivity > STEP_TIMEOUT then
        run.lastActivity = now
        if waiting then
            finishRun("throttleNeverReady")
        elseif run.state then
            finishStep("timeout")
        elseif run.search then
            endSearch("timeout")
        end
    elseif waiting then
        return
    elseif run.search then
        tickSearch(now)
    elseif run.collect then
        tickCanCollect(now)
    elseif run.find then
        tickFind(now)
    end
end

local function startAuctionRun(trigger)
    if run then
        run.ticker:Cancel()
    end
    db.auction = {
        trigger = trigger,
        startedAt = date("%H:%M:%S"),
        filterGroups = call(C_AuctionHouse, "GetFilterGroups"),
        steps = {},
        searches = {},
        eventCounts = {},
        log = {},
    }
    run = { record = db.auction, t0 = preciseTime(), lastActivity = preciseTime(),
        asked = {}, unsentFound = {}, collectItems = {}, collectCount = {}, collectPicked = {},
        candidates = {}, sampleSeen = {} }
    run.ticker = C_Timer.NewTicker(0.25, tickAuctionRun)
    local thisRun = run
    -- Delayed so the event log shows any query Blizzard's or another addon's
    -- UI sends on open before the first step goes out.
    C_Timer.After(2, function()
        if run == thisRun then
            startStep(1)
        end
    end)
    print("TCProbe: auction recording started. It takes about 95 seconds, up to 165 if searches go unsent. Leave the auction window open and untouched until the 'recording ended' line.")
end

local function stopAuctionRun(reason)
    if not run then
        return
    end
    if run.state then
        run.state.record.done = reason
        run.state.record.stats = run.state.stats
    end
    if run.search then
        run.search.record.done = reason
    end
    finishRun(reason)
end

-- Starts the find check: reads each appearance's sources and asks for their
-- items' data; the browses follow from the ticker. Nothing is sent unless the
-- auction window is showing.
local function startFind()
    if run then
        print("TCProbe: a recording is running; wait for its 'ended' line.")
        return
    end
    if call(AuctionHouseFrame, "IsShown", AuctionHouseFrame)[1] ~= true then
        print("TCProbe: open the auction window first, then type /tcprobe find again.")
        return
    end
    local TC = C_TransmogCollection
    db.find = { startedAt = date("%H:%M:%S"), appearances = {}, browses = 0, searches = 0,
        eventCounts = {}, log = {} }
    for i, pick in ipairs(FIND_ITEMS) do
        local transmog = call(TC, "GetItemInfo", pick.itemID)
        local appearance = { itemID = pick.itemID, why = pick.why, appearanceID = transmog[1],
            sources = {}, browses = {} }
        local sourceIDs = transmog[1] and call(TC, "GetAllAppearanceSources", transmog[1])[1]
        if type(sourceIDs) == "table" then
            appearance.sourceCount = #sourceIDs
            for n = 1, math.min(#sourceIDs, MAX_ALT_SOURCES) do
                local info = call(TC, "GetSourceInfo", sourceIDs[n])[1]
                info = type(info) == "table" and info or {}
                appearance.sources[n] = { sourceID = sourceIDs[n], itemID = info.itemID, sourceType = info.sourceType }
            end
        else
            -- without a source list the item itself is still looked for
            appearance.noSourceList = true
            appearance.sources[1] = { sourceID = transmog[2], itemID = pick.itemID }
        end
        for _, source in ipairs(appearance.sources) do
            if source.itemID then
                call(C_Item, "RequestLoadItemDataByID", source.itemID)
            end
        end
        db.find.appearances[i] = appearance
    end
    run = { record = db.find, t0 = preciseTime(), lastActivity = preciseTime(), asked = {},
        step = { name = "findLoad" }, find = { phase = "load", since = preciseTime(), resultFields = {} } }
    run.ticker = C_Timer.NewTicker(0.25, tickAuctionRun)
    print(("TCProbe: find check started for %d appearances: at most %d browses and %d searches, about 15 seconds, %d at most. Leave the auction window open and untouched until the 'find check ended' line."):format(
        #FIND_ITEMS, FIND_BROWSES, FIND_SEARCHES, FIND_TIME_LIMIT))
end

-- The word after "/tcprobe tiles": { key in Enum.TransmogCollectionType, its
-- value on build 71037, inventory slot }. Entries without a slot are weapons;
-- their slot comes from GetCategoryInfo.
local tileSlots = {
    head = { "Head", 1, 1 }, shoulder = { "Shoulder", 2, 3 }, back = { "Back", 3, 15 },
    chest = { "Chest", 4, 5 }, shirt = { "Shirt", 5, 4 }, tabard = { "Tabard", 6, 19 },
    wrist = { "Wrist", 7, 9 }, hands = { "Hands", 8, 10 }, waist = { "Waist", 9, 6 },
    legs = { "Legs", 10, 7 }, feet = { "Feet", 11, 8 },
    wand = { "Wand", 12 }, axe = { "OneHAxe", 13 }, sword = { "OneHSword", 14 },
    mace = { "OneHMace", 15 }, dagger = { "Dagger", 16 }, fist = { "Fist", 17 },
    shield = { "Shield", 18 }, offhand = { "Holdable", 19 }, axe2h = { "TwoHAxe", 20 },
    sword2h = { "TwoHSword", 21 }, mace2h = { "TwoHMace", 22 }, staff = { "Staff", 23 },
    polearm = { "Polearm", 24 }, bow = { "Bow", 25 }, gun = { "Gun", 26 }, crossbow = { "Crossbow", 27 },
}

-- The tile prototype: its frames, made on the first command and used again
-- for every slot, variant and page, and what they show now.
local tiles = {}

local function noteError(record, what, result)
    if (result.error or result.missing) and #record.errors < 5 then
        record.errors[#record.errors + 1] = what .. ": " .. (result.error or "missing")
    end
    return result
end

-- A category's appearances as Blizzard's wardrobe lists them
-- (WardrobeItemsCollectionMixin:RefreshVisualsList and :FilterVisuals).
local function categoryVisuals(category, location)
    local result = call(C_TransmogCollection, "GetCategoryAppearances", category, location)
    local visuals, counts = {}, { collected = 0, uncollected = 0, hidden = 0 }
    if type(result[1]) ~= "table" then
        counts.noList = result
        return visuals, counts
    end
    for _, info in ipairs(result[1]) do
        if info.isHideVisual then
            counts.hidden = counts.hidden + 1
        else
            local key = info.isCollected and "collected" or "uncollected"
            counts[key] = counts[key] + 1
            visuals[#visuals + 1] = info.visualID
        end
    end
    return visuals, counts
end

-- The source Blizzard's wardrobe dresses a tile with
-- (WardrobeItemsCollectionMixin:GetAnAppearanceSourceFromVisual), or any
-- source of the appearance when the category gives none. The second result
-- says which of the two it was.
local function tileSource(visualID)
    local TC = C_TransmogCollection
    local sources = call(TC, "GetAppearanceSources", visualID, tiles.category, tiles.location)[1]
    if type(sources) == "table" and sources[1] then
        local sorted = call(CollectionWardrobeUtil, "SortSources", sources)[1]
        return (type(sorted) == "table" and sorted or sources)[1].sourceID, true
    end
    local all = call(TC, "GetAllAppearanceSources", visualID)[1]
    return type(all) == "table" and all[1] or nil, false
end

-- Nothing in Blizzard's code takes a UI camera off a model, so this is a
-- guess; customCamera in the page record says whether it worked.
local function removeCamera(model)
    call(model, "ClearModel", model)
    call(model, "SetPosition", model, 0, 0, 0)
    call(model, "SetFacing", model, 0)
    call(model, "SetPitch", model, 0)
    call(model, "SetRoll", model, 0)
    call(model, "RefreshCamera", model)
end

-- Armor: the player's figure wearing only the piece. Weapon: the item alone.
-- A model is set up once per slot and variant; paging only changes the piece,
-- as Blizzard's wardrobe does.
local function dressTile(model, index, visualID, record)
    local setup = tiles.slot .. "/" .. tiles.variant
    if model.tcSetup ~= setup then
        if model.tcCamera then
            removeCamera(model)
            model.tcCamera = nil
        end
        if tiles.weapon then
            noteError(record, "SetAutoDress", call(model, "SetAutoDress", model, false))
        else
            local result = setUpLikeWardrobe(model)
            noteError(record, "SetUnit", result.setUnit)
            if index == 1 then
                record.setup = result
            end
        end
        noteError(record, "SetKeepModelOnHide", call(model, "SetKeepModelOnHide", model, true))
        model.tcSetup = setup
    end
    if tiles.variant == "cam" then
        local camera = applyAppearanceCamera(model, visualID)
        noteError(record, "GetAppearanceCameraID", camera.cameraID)
        noteError(record, "Model_ApplyUICamera", camera.apply)
        record.cameras[index] = camera.cameraID[1] or false
        model.tcCamera = visualID
    end
    if tiles.weapon then
        noteError(record, "SetItemAppearance", call(model, "SetItemAppearance", model, visualID))
        return
    end
    local sourceID, fromCategory = tileSource(visualID)
    record.sources[index] = sourceID or false
    record.sourcesFromCategory = record.sourcesFromCategory + (fromCategory and 1 or 0)
    local result = sourceID and noteError(record, "TryOn", call(model, "TryOn", model, sourceID))
    record.tryOn[index] = result and result[1] or false
end

-- Blizzard's wardrobe waits on IsGeoReady before it treats a tile as drawn;
-- OnModelLoaded may not fire again for a model that only changes its piece.
local function watchGeometry()
    local record = tiles.record
    if not record or record.geoReadyAt or record.geoReadyTiles then
        return
    end
    local waited = preciseTime() - tiles.shownAt
    local ready = 0
    for i = 1, record.tiles do
        if call(tiles.models[i], "IsGeoReady", tiles.models[i])[1] == true then
            ready = ready + 1
        end
    end
    if ready == record.tiles then
        record.geoReadyAt = round3(waited)
    elseif waited > 3 then
        record.geoReadyTiles = ready
    end
end

local function showTilePage(page)
    local pages = math.max(1, math.ceil(#tiles.visuals / TILE_COUNT))
    page = math.min(math.max(page, 1), pages)
    local record = {
        slot = tiles.slot, variant = tiles.variant, page = page, at = date("%H:%M:%S"),
        fpsBefore = call(_G, "GetFramerate")[1],
        tiles = 0, tilesLoaded = 0, loadEvents = 0, sourcesFromCategory = 0,
        tryOn = {}, sources = {}, cameras = {}, errors = {},
    }
    local records = db.tiles.pages
    if #records < TILE_PAGE_RECORDS then
        records[#records + 1] = record
    end
    tiles.page, tiles.record, tiles.shownAt = page, record, preciseTime()
    for i, model in ipairs(tiles.models) do
        local visualID = tiles.visuals[(page - 1) * TILE_COUNT + i]
        if visualID then
            record.tiles = record.tiles + 1
            model:Show()
            dressTile(model, i, visualID, record)
        else
            model:Hide()
        end
    end
    record.dressSeconds = round3(preciseTime() - tiles.shownAt)
    record.customCamera = call(tiles.models[1], "HasCustomCamera", tiles.models[1])[1]
    tiles.title:SetText(("%s  |  %s  |  page %d of %d"):format(tiles.slot, tiles.variant, page, pages))
    tiles.status:SetText(("%d appearances, %d tiles loading..."):format(#tiles.visuals, record.tiles))
    C_Timer.After(1, function()
        if tiles.record ~= record then
            return
        end
        record.fpsAfter = call(_G, "GetFramerate")[1]
        tiles.status:SetText(("%d appearances. %d of %d tiles loaded, last after %s s; drawn after %s s; fps %.0f -> %.0f"):format(
            #tiles.visuals, record.tilesLoaded, record.tiles, tostring(record.lastLoadedAt),
            tostring(record.geoReadyAt), record.fpsBefore or 0, record.fpsAfter or 0))
    end)
end

local function tileButton(parent, text, width, onClick)
    local button = call(_G, "CreateFrame", "Button", nil, parent, "UIPanelButtonTemplate")[1]
    if type(button) ~= "table" then
        -- without the template a bare button still pages and closes
        button = CreateFrame("Button", nil, parent)
        button:SetNormalFontObject("GameFontNormalLarge")
    end
    button:SetSize(width, 26)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

-- Puts the wardrobe's "show uncollected" filter back to the value read before
-- the probe changed it, and records what the client then reports. Every way
-- out of the half second the filter is lifted for comes through here; it does
-- nothing when no lift is pending. early is a way out before the list was
-- read a second time: the short list is dropped, so the slot is read again.
local function restoreUncollectedFilter(early)
    local lift = tiles.lift
    if not lift then
        return
    end
    tiles.lift = nil
    lift.filter.restore = call(C_TransmogCollection, "SetUncollectedShown", lift.was)
    lift.filter.readBack = call(C_TransmogCollection, "GetUncollectedShown")
    if early then
        lift.filter.restoredEarly = true
        tiles.slot = nil
    end
end

local function createTileFrame()
    local margin, top = 20, 84
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(2 * margin + TILE_COLUMNS * TILE_WIDTH + (TILE_COLUMNS - 1) * TILE_GAP,
        top + TILE_ROWS * TILE_HEIGHT + (TILE_ROWS - 1) * TILE_GAP + margin)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    frame:SetScript("OnUpdate", watchGeometry)
    frame:SetScript("OnHide", function()
        restoreUncollectedFilter(true)
    end)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.1, 0.1, 0.12, 0.95)
    -- large, so slot, variant and page can be read off a screenshot
    tiles.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    tiles.title:SetPoint("TOPLEFT", margin, -14)
    tiles.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tiles.status:SetPoint("TOPLEFT", margin, -52)
    tiles.status:SetWidth(frame:GetWidth() - 2 * margin)
    tiles.status:SetJustifyH("LEFT")
    local close = tileButton(frame, "X", 30, function()
        frame:Hide()
    end)
    close:SetPoint("TOPRIGHT", -margin, -12)
    local forward = tileButton(frame, ">", 40, function()
        showTilePage(tiles.page + 1)
    end)
    forward:SetPoint("RIGHT", close, "LEFT", -12, 0)
    local back = tileButton(frame, "<", 40, function()
        showTilePage(tiles.page - 1)
    end)
    back:SetPoint("RIGHT", forward, "LEFT", -4, 0)
    tiles.models = {}
    for i = 1, TILE_COUNT do
        local model = CreateFrame("DressUpModel", nil, frame)
        local column, row = (i - 1) % TILE_COLUMNS, math.floor((i - 1) / TILE_COLUMNS)
        model:SetSize(TILE_WIDTH, TILE_HEIGHT)
        model:SetPoint("TOPLEFT", margin + column * (TILE_WIDTH + TILE_GAP), -top - row * (TILE_HEIGHT + TILE_GAP))
        local black = model:CreateTexture(nil, "BACKGROUND")
        black:SetAllPoints()
        black:SetColorTexture(0, 0, 0, 1)
        call(model, "SetScript", model, "OnModelLoaded", function()
            local record = tiles.record
            if not record then
                return
            end
            if model.tcLoadedFor ~= record then
                model.tcLoadedFor = record
                record.tilesLoaded = record.tilesLoaded + 1
            end
            record.loadEvents = record.loadEvents + 1
            record.lastLoadedAt = round3(preciseTime() - tiles.shownAt)
            -- Blizzard applies the camera again once the model is in
            -- (ItemModelBaseMixin:OnModelLoaded).
            if model.tcCamera then
                applyAppearanceCamera(model, model.tcCamera)
            end
        end)
        tiles.models[i] = model
    end
    tiles.frame = frame
end

-- A slot word's category, what the client says about it, and the location
-- its appearances are listed for.
local function slotCategory(word)
    local entry = tileSlots[word]
    local category = enum("TransmogCollectionType", entry[1], entry[2])
    local info = call(C_TransmogCollection, "GetCategoryInfo", category)
    -- the shape of TransmogLocationMixin:GetData; info is name, isWeapon,
    -- canHaveIllusions, canMainHand, canOffHand, canRanged
    local location = {
        slotID = entry[3] or (info[4] and 16) or (info[5] and 17) or (info[6] and 18) or 16,
        type = enum("TransmogType", "Appearance", 0),
        modification = enum("TransmogModification", "Main", 0),
    }
    return category, info, location
end

-- Reads the slot's appearances, then calls done.
local function loadTileSlot(word, done)
    local TC = C_TransmogCollection
    local category, info, location = slotCategory(word)
    -- collectedShown is only read. The probe writes one wardrobe filter, the
    -- one below, and leaves the source-type and class filters alone.
    local filter = { read = call(TC, "GetUncollectedShown"), wrote = false }
    local record = {
        category = category, categoryInfo = info, location = location,
        collectedShown = call(TC, "GetCollectedShown"),
        uncollectedFilter = filter,
    }
    db.tiles.slots[word] = record
    tiles.slot, tiles.weapon, tiles.category, tiles.location = word, not tileSlots[word][3], category, location
    tiles.visuals, record.asFound = categoryVisuals(category, location)
    local function finish()
        record.pageNotFilled = #tiles.visuals < TILE_COUNT
        done()
    end
    -- Forever's wardrobe keeps uncollected appearances out of this list
    -- (Camelot/Blizzard_Wardrobe.lua turns their filter off), and a page needs
    -- 18. Only when the client says the filter is off is it lifted, for half
    -- a second: the list is read at once and again at the end, in case the
    -- client rebuilds it late, and the filter is put back to what was read.
    -- With the filter already on, or no answer about it, nothing is written
    -- and the page shows what the list holds.
    if #tiles.visuals >= TILE_COUNT or filter.read[1] ~= false then
        return finish()
    end
    filter.write = call(TC, "SetUncollectedShown", true)
    if filter.write.error or filter.write.missing then
        return finish()
    end
    filter.wrote = true
    local lift = { was = filter.read[1], filter = filter }
    tiles.lift = lift
    local atOnce
    atOnce, record.withUncollected = categoryVisuals(category, location)
    C_Timer.After(0.5, function()
        if tiles.lift ~= lift then
            return
        end
        local later
        later, record.withUncollectedLater = categoryVisuals(category, location)
        restoreUncollectedFilter()
        for _, visuals in ipairs({ atOnce, later }) do
            if #visuals > #tiles.visuals then
                tiles.visuals = visuals
            end
        end
        finish()
    end)
end

-- Shows a page of 18 tiles for one slot: "cam" frames each tile with the
-- appearance's UI camera as Blizzard's wardrobe does, "full" leaves the
-- camera alone.
local function showTiles(arguments)
    local word, variant = arguments:match("^(%S*)%s*(%S*)")
    if variant == "" then
        variant = "cam"
    end
    if not tileSlots[word] or (variant ~= "cam" and variant ~= "full") then
        local words = {}
        for name in pairs(tileSlots) do
            words[#words + 1] = name
        end
        table.sort(words)
        print("TCProbe: /tcprobe tiles <slot> [cam|full]. Slots: " .. table.concat(words, " "))
        return
    end
    db.tiles = db.tiles or { slots = {}, pages = {} }
    if not tiles.frame then
        createTileFrame()
    end
    -- a command that arrives while the filter is lifted starts over
    restoreUncollectedFilter(true)
    tiles.variant = variant
    tiles.frame:Show()
    local function firstPage()
        showTilePage(1)
        print(("TCProbe: tiles for %s (%s), %d appearances. Page with the < and > buttons, take the screenshot, then close with X. Nothing is saved until /reload."):format(
            word, variant, #tiles.visuals))
    end
    if tiles.slot == word then
        return firstPage()
    end
    loadTileSlot(word, firstPage)
end

-- The tab test: whether its tab exists yet, when the test began, and the
-- state of the auction frame's fields at the last moment kept.
local tab = {}

-- Blizzard's bag clicks read AuctionHouseFrame.displayMode and its tab code
-- reads numTabs; a field an addon wrote makes that code run tainted. This
-- reads whether each is still secure and who tainted it if not, and whether
-- displayMode holds anything. With onlyChanges the moment is kept only when
-- it differs from the last one kept.
local function tabMoment(at, onlyChanges)
    local auctionFrame = AuctionHouseFrame
    local moment = {
        at = at,
        t = round3(preciseTime() - tab.since),
        displayMode = call(_G, "issecurevariable", auctionFrame, "displayMode"),
        numTabs = call(_G, "issecurevariable", auctionFrame, "numTabs"),
        displayModeIsNil = auctionFrame == nil or auctionFrame.displayMode == nil,
    }
    local state = table.concat({ tostring(moment.displayMode[1]), tostring(moment.displayMode[2]),
        tostring(moment.numTabs[1]), tostring(moment.numTabs[2]), tostring(moment.displayModeIsNil) }, " ")
    local moments = db.tab.moments
    if (onlyChanges and state == tab.state) or #moments >= TAB_MOMENTS then
        return
    end
    tab.state = state
    moments[#moments + 1] = moment
    return moment
end

-- Adds one tab to the auction window through LibAHTab, the way an addon's
-- appearance browser would, and records whether doing so and selecting it
-- leaves those fields secure. The probe calls no method of Blizzard's
-- auction frame: the library does what a tab needs, the probe only reads.
local function showTab()
    db.tab = db.tab or { library = TAB_LIBRARY, tabID = TAB_ID, calls = {}, moments = {} }
    local record = db.tab
    if tab.created then
        print("TCProbe: the tab is already there; no second one is made.")
        print(TAB_STEPS)
        return
    end
    -- LibStub(name, true) is LibStub:GetLibrary(name, true): the library and
    -- its version, or nothing when no addon has loaded it.
    local found = call(LibStub, "GetLibrary", LibStub, TAB_LIBRARY, true)
    local lib = found[1]
    record.calls.getLibrary = { found = type(lib) == "table", error = found.error, missing = found.missing }
    record.version = found[2]
    if type(lib) ~= "table" then
        record.stopped = "noLibrary"
        print("TCProbe: " .. TAB_LIBRARY .. " is not loaded. The tab test needs Auctionator enabled; nothing was created.")
        return
    end
    if not AuctionHouseFrame then
        record.stopped = "noAuctionFrame"
        print("TCProbe: open the auction window first, then type /tcprobe tab again.")
        return
    end
    record.calls.idExistsBefore = call(lib, "DoesIDExist", lib, TAB_ID)
    if record.calls.idExistsBefore[1] then
        record.stopped = "idTaken"
        print("TCProbe: a tab with the id " .. TAB_ID .. " exists already; nothing was created.")
        return
    end
    record.stopped = nil
    tab.since = preciseTime()
    tabMoment("beforeCreate")
    -- A plain child of the auction frame, in the box Blizzard's own Auctions
    -- panel fills; it writes no key on the auction frame.
    local panel = CreateFrame("Frame", nil, AuctionHouseFrame)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 5, -42)
    panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 27)
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.1, 0.1, 0.12, 0.95)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    record.calls.createTab = call(lib, "CreateTab", lib, TAB_ID, panel, "TCProbe", "TCProbe tab test")
    record.calls.idExistsAfter = call(lib, "DoesIDExist", lib, TAB_ID)
    if record.calls.createTab.error or record.calls.createTab.missing then
        panel:Hide()
        record.stopped = "createTabFailed"
        tabMoment("createFailed")
        print("TCProbe: the library did not create the tab (" .. tostring(record.calls.createTab.error or "no CreateTab")
            .. "). /reload to save this.")
        return
    end
    tab.created = true
    local button = call(lib, "GetButton", lib, TAB_ID)[1]
    record.calls.getButton = {
        found = type(button) == "table",
        name = call(button, "GetName", button)[1],
        width = call(button, "GetWidth", button)[1],
    }
    record.auctionFrameSize = call(AuctionHouseFrame, "GetSize", AuctionHouseFrame)
    record.panelSize = call(panel, "GetSize", panel)
    -- Set only now: CreateTab hides the panel once itself. The library shows
    -- the panel when the tab is clicked and hides it when another tab is.
    panel:SetScript("OnShow", function()
        local size = call(panel, "GetSize", panel)
        text:SetText(("TCProbe tab panel, %.0f x %.0f"):format(size[1] or 0, size[2] or 0))
        local moment = tabMoment("panelShown")
        if moment then
            moment.panelSize = size
        end
    end)
    panel:SetScript("OnHide", function()
        tabMoment("panelHidden")
    end)
    tabMoment("afterCreate")
    local seconds = 0
    tab.ticker = C_Timer.NewTicker(1, function()
        seconds = seconds + 1
        tabMoment("watch", true)
        if seconds >= TAB_WATCH_SECONDS then
            tab.ticker:Cancel()
        end
    end)
    print(("TCProbe: tab created through %s version %s."):format(TAB_LIBRARY, tostring(record.version)))
    print(TAB_STEPS)
end

-- The collect check: one row per item of everything that might decide
-- whether the character can collect the item's appearance, so that the rule
-- can be worked out from the saved file. It asks the auction house nothing
-- and writes no wardrobe filter, so it runs anywhere.
--
-- Every item id in the recording of 2026-11-24: 128 from its auction part
-- (the steps' first rows, the searches, the eight items recorded in full and
-- the sample's examples), 17 from the equipped items, the other sources of
-- their appearances and the last tooltip.
local CHECK_ITEMS = {
    1367, 1411, 1413, 1415, 1416, 1418, 1419, 1421, 1427, 1429, 1431, 1495, 1503, 1720, 1731, 1739,
    1747, 1755, 1764, 1774, 1799, 1805, 1926, 2084, 2138, 2302, 2419, 2510, 2525, 2530, 2535, 2569,
    2570, 2578, 2580, 2635, 2642, 2644, 2650, 2765, 2773, 2774, 2853, 2901, 2959, 2967, 2971, 2991,
    3284, 3289, 3307, 3370, 3414, 3644, 3779, 3803, 3809, 3835, 4307, 4308, 4309, 4344, 4362, 4565,
    4566, 4672, 4680, 4718, 5216, 5379, 5405, 5956, 6059, 6125, 6137, 6214, 6256, 6378, 6518, 6537,
    6539, 7005, 7026, 7351, 7357, 7919, 8156, 8181, 8182, 8224, 8261, 9444, 9486, 9490, 9743, 9751,
    9780, 9884, 9938, 9944, 10045, 10069, 10208, 10280, 10376, 10624, 11191, 11287, 11288, 12989,
    13038, 13136, 14110, 14114, 14160, 14174, 14304, 14364, 14826, 14827, 14914, 14937, 15114, 15230,
    15286, 15301, 15490, 15507, 15537, 15648, 15903, 15978, 16059, 213354, 247789, 250487, 250602,
    250605, 253885, 277002, 277006, 277017, 277060, 281268, 281274,
}

-- The fields kept from GetSourceInfo and from GetAppearanceInfoBySource. In
-- the recording useError and useErrorType are there for some sources only,
-- and meetsTransmogPlayerCondition is a field of the appearance's table.
local CHECK_SOURCE_FIELDS = { "isCollected", "useError", "useErrorType", "isValidSourceForPlayer",
    "playerCanCollect", "meetsTransmogPlayerCondition", "sourceType", "categoryID", "quality",
    "canDisplayOnPlayer" }
local CHECK_APPEARANCE_FIELDS = { "meetsTransmogPlayerCondition", "appearanceMeetsNonLevelRequirements",
    "appearanceHasAnyNonLevelRequirements" }

-- One name per cell of a row. account1 and account2 are the two values of
-- AccountCanCollectSource, player1 and player2 those of
-- PlayerCanCollectSource; in the recording the first was false exactly for
-- the items without data. sourceInfo and appearanceInfo say what the call
-- gave: "table", "nil", "error", "missing", or "notAsked" for an item without
-- a source. validSourcesForClass is the number of sources in the table
-- GetValidAppearanceSourcesForClass gave for the character's class, or one of
-- those words.
local CHECK_COLUMNS = { "itemID", "sourceID", "appearanceID", "origin", "nameLoaded", "cached",
    "quality", "requiredLevel", "itemLevel", "bindType", "classID", "subClassID", "equipLoc",
    "account1", "account2", "player1", "player2", "sourceInfo" }
for _, field in ipairs(CHECK_SOURCE_FIELDS) do
    CHECK_COLUMNS[#CHECK_COLUMNS + 1] = "source." .. field
end
CHECK_COLUMNS[#CHECK_COLUMNS + 1] = "appearanceInfo"
for _, field in ipairs(CHECK_APPEARANCE_FIELDS) do
    CHECK_COLUMNS[#CHECK_COLUMNS + 1] = "appearance." .. field
end
CHECK_COLUMNS[#CHECK_COLUMNS + 1] = "validSourcesForClass"

-- The check in progress; nil when none is running.
local check

-- Appends cells to a row. A value the client did not give is stored as
-- "nil", so that every row has a cell for every column.
local function addCells(row, ...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        row[#row + 1] = value == nil and "nil" or value
    end
end

-- A collection call about a source or an appearance, or a note that the item
-- has none to ask about. The first few distinct error texts are kept.
local function askCollection(name, id, ...)
    if not id then
        return { notAsked = true }
    end
    local result = call(C_TransmogCollection, name, id, ...)
    local text = result.error and name .. ": " .. result.error
    local errors = check.record.errors
    if text and not check.errorSeen[text] and #errors < CHECK_ERRORS then
        check.errorSeen[text] = true
        errors[#errors + 1] = text
    end
    return result
end

-- What a call gave, in a word: it tells a call that returned nil from one
-- that raised an error.
local function gave(result)
    return (result.notAsked and "notAsked") or (result.missing and "missing")
        or (result.error and "error") or type(result[1])
end

local function checkRow(item)
    local record = check.record
    local itemID = item.itemID
    if not item.sourceID then
        local transmog = call(C_TransmogCollection, "GetItemInfo", itemID)
        item.appearanceID, item.sourceID = transmog[1], transmog[2]
    end
    local sourceID, appearanceID = item.sourceID, item.appearanceID
    local name = call(C_Item, "GetItemNameByID", itemID)[1]
    if name == nil then
        check.notLoaded = check.notLoaded + 1
    end
    local instant = call(C_Item, "GetItemInfoInstant", itemID)
    -- Unverified: the recording lists C_Item.GetItemInfo among this client's
    -- functions, but its results were never recorded. Taken from the retail
    -- order: 4 item level, 5 required level, 14 bind type. The first full
    -- answer is kept whole as itemInfoSample, to check that order against;
    -- no answer leaves the three cells "nil".
    local info = call(C_Item, "GetItemInfo", itemID)
    if info[1] ~= nil and not record.itemInfoSample then
        record.itemInfoSample = info
    end
    local account = askCollection("AccountCanCollectSource", sourceID)
    local player = askCollection("PlayerCanCollectSource", sourceID)
    local sourceInfo = askCollection("GetSourceInfo", sourceID)
    local appearanceInfo = askCollection("GetAppearanceInfoBySource", sourceID)
    local classID = record.player.class[3]
    local valid = askCollection("GetValidAppearanceSourcesForClass", classID and appearanceID, classID)

    local row = {}
    addCells(row, itemID, sourceID, appearanceID, item.origin, name ~= nil,
        call(C_Item, "IsItemDataCachedByID", itemID)[1],
        call(C_Item, "GetItemQualityByID", itemID)[1], info[5], info[4], info[14],
        instant[6], instant[7], instant[4],
        account[1], account[2], player[1], player[2], gave(sourceInfo))
    local source = type(sourceInfo[1]) == "table" and sourceInfo[1] or {}
    for _, field in ipairs(CHECK_SOURCE_FIELDS) do
        addCells(row, source[field])
    end
    for field in pairs(source) do
        check.sourceFields[field] = true
    end
    addCells(row, gave(appearanceInfo))
    local appearance = type(appearanceInfo[1]) == "table" and appearanceInfo[1] or {}
    for _, field in ipairs(CHECK_APPEARANCE_FIELDS) do
        addCells(row, appearance[field])
    end
    addCells(row, type(valid[1]) == "table" and #valid[1] or gave(valid))
    return row
end

-- Tops the list up from one wardrobe category, read as the client lists it:
-- appearances spaced evenly through the list and one source of each, taking
-- turns through the appearance's sources. GetSourceInfo gave an itemID for
-- every source in the recording. Unverified: the recording has no weapon
-- category, and GetCategoryInfo gave nothing for feet, so a weapon's slot is
-- the fallback 16; a category without a list adds nothing.
local function addCategoryItems(items, seen, word, wanted)
    local TC = C_TransmogCollection
    local category, _, location = slotCategory(word)
    local visuals, counts = categoryVisuals(category, location)
    local tally = { category = category, listed = counts, wanted = wanted,
        added = 0, noSource = 0, noItem = 0, alreadyListed = 0 }
    local take = math.min(#visuals, wanted)
    for i = 1, take do
        local visualID = visuals[math.floor((i - 0.5) * #visuals / take) + 1]
        local all = call(TC, "GetAllAppearanceSources", visualID)[1]
        local sourceID = type(all) == "table" and all[(i - 1) % math.max(#all, 1) + 1]
        if not sourceID then
            -- as the tiles do: the first of the category's own sources
            local sources = call(TC, "GetAppearanceSources", visualID, category, location)[1]
            sourceID = type(sources) == "table" and sources[1] and sources[1].sourceID
        end
        local info = sourceID and call(TC, "GetSourceInfo", sourceID)[1]
        local itemID = type(info) == "table" and info.itemID
        if not sourceID then
            tally.noSource = tally.noSource + 1
        elseif not itemID then
            tally.noItem = tally.noItem + 1
        elseif seen[itemID] then
            tally.alreadyListed = tally.alreadyListed + 1
        else
            seen[itemID] = true
            tally.added = tally.added + 1
            items[#items + 1] = { itemID = itemID, sourceID = sourceID, appearanceID = visualID, origin = word }
        end
    end
    return tally
end

-- Waits until the client holds every item's data or the wait is used up,
-- then measures a batch of items per tick.
local function tickCollectCheck()
    local record = check.record
    if not check.index then
        local waited = preciseTime() - check.t0
        local missing = 0
        for _, item in ipairs(check.items) do
            if call(C_Item, "IsItemDataCachedByID", item.itemID)[1] == false then
                missing = missing + 1
            end
        end
        if missing > 0 and waited <= CHECK_DATA_WAIT then
            return
        end
        record.waitedForData = round3(waited)
        check.index = 1
    end
    local last = math.min(check.index + CHECK_BATCH - 1, #check.items)
    for i = check.index, last do
        record.rows[i] = checkRow(check.items[i])
    end
    check.index = last + 1
    if last < #check.items then
        return
    end
    record.sourceInfoFields = {}
    for field in pairs(check.sourceFields) do
        record.sourceInfoFields[#record.sourceInfoFields + 1] = field
    end
    table.sort(record.sourceInfoFields)
    record.notLoaded = check.notLoaded
    record.tookSeconds = round3(preciseTime() - check.t0)
    check.ticker:Cancel()
    check = nil
    print(("TCProbe: collect check ended after %d seconds, %d items, %d not loaded. /reload now."):format(
        math.floor(record.tookSeconds), #record.rows, record.notLoaded))
end

local function startCollectCheck()
    if check then
        print("TCProbe: the collect check is already running; wait for its 'collect check ended' line.")
        return
    end
    local items, seen = {}, {}
    for i, itemID in ipairs(CHECK_ITEMS) do
        items[i] = { itemID = itemID, origin = "fixed" }
        seen[itemID] = true
    end
    -- Unverified on this client: UnitLevel, UnitRace and UnitFactionGroup. A
    -- missing one is recorded as such.
    local record = {
        startedAt = date("%H:%M:%S"),
        player = {
            level = call(_G, "UnitLevel", "player"),
            class = call(_G, "UnitClass", "player"),
            race = call(_G, "UnitRace", "player"),
            faction = call(_G, "UnitFactionGroup", "player"),
        },
        fromFixedList = #items,
        columns = CHECK_COLUMNS,
        rows = {},
        errors = {},
    }
    record.fromStaff = addCategoryItems(items, seen, "staff", math.ceil((CHECK_TARGET - #items) / 2))
    record.fromFeet = addCategoryItems(items, seen, "feet", CHECK_TARGET - #items)
    db.collect = record
    for _, item in ipairs(items) do
        call(C_Item, "RequestLoadItemDataByID", item.itemID)
    end
    check = { record = record, items = items, t0 = preciseTime(), notLoaded = 0,
        errorSeen = {}, sourceFields = {} }
    check.ticker = C_Timer.NewTicker(0.1, tickCollectCheck)
    print(("TCProbe: collect check started for %d items: %d from the fixed list, %d staff and %d feet appearances from the wardrobe. It asks the auction house nothing and ends within about 8 seconds."):format(
        #items, record.fromFixedList, record.fromStaff.added, record.fromFeet.added))
end

-- /tcprobe classes and /tcprobe names. Neither reaches the auction house.
-- Open points 2 and 8 of the browser spec: can an addon list another
-- class's appearances by setting Collections' class filter, and how fast do
-- the item names of a whole slot arrive.
local CLASS_EVENTS = {
    "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_SEARCH_UPDATED",
    "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_CAMERA_UPDATE",
}
local NAMES_SECONDS = 15
local NAMES_SAMPLE_EVERY = 0.5
local NAMES_PER_FRAME = 20
local NAMES_NEVER_LISTED = 10
local FIRST_IDS = 10

-- A call's first answer, or its failure as text, so a recording shows it.
local function answer(result)
    if result.missing or result.error then
        return "(" .. (result.error or "missing") .. ")"
    end
    return result[1]
end

local function failureText(result)
    if result.missing then
        return "missing"
    end
    return result.error
end

-- A frame listening for events; an event the client does not know is
-- refused by RegisterEvent with an error, which is caught and recorded.
local function listen(events, onEvent)
    local listener = CreateFrame("Frame")
    local registered, refused = {}, {}
    for _, event in ipairs(events) do
        if pcall(listener.RegisterEvent, listener, event) then
            registered[#registered + 1] = event
        else
            refused[#refused + 1] = event
        end
    end
    pcall(listener.RegisterEvent, listener, "PLAYER_LOGOUT")
    listener:SetScript("OnEvent", onEvent)
    return listener, registered, refused
end

local function stopListening(listener)
    pcall(listener.UnregisterAllEvents, listener)
    pcall(listener.SetScript, listener, "OnEvent", nil)
end

-- The word after "/tcprobe classes" or "/tcprobe names": a slot of the tiles
-- table, feet when empty.
local function slotWord(arguments, command)
    local word = arguments:match("^(%S*)")
    if word == "" then
        word = "feet"
    end
    if not tileSlots[word] then
        print("TCProbe: /tcprobe " .. command .. " [slot], feet when no slot is given. See /tcprobe tiles for the slot words.")
        return nil
    end
    return word
end

-- A category's list as Collections shows it: counts over the entries and the
-- set of visualIDs of the entries that are not hidden visuals.
local function readList(category, location)
    local started = milliseconds()
    local result = call(C_TransmogCollection, "GetCategoryAppearances", category, location)
    local took = milliseconds() - started
    local read = { entries = 0, shown = 0, collected = 0, usable = 0, ms = round3(took), first10 = {} }
    local ids, order = {}, {}
    if type(result[1]) ~= "table" then
        read.noList = answer(result)
        return read, ids, order
    end
    for _, info in ipairs(result[1]) do
        read.entries = read.entries + 1
        if info.isCollected then
            read.collected = read.collected + 1
        end
        if info.isUsable then
            read.usable = read.usable + 1
        end
        if not info.isHideVisual then
            read.shown = read.shown + 1
            ids[info.visualID] = true
            order[#order + 1] = info.visualID
        end
    end
    for i = 1, math.min(FIRST_IDS, #order) do
        read.first10[i] = order[i]
    end
    return read, ids, order
end

local function sameSet(a, b)
    for id in pairs(a) do
        if not b[id] then
            return false
        end
    end
    for id in pairs(b) do
        if not a[id] then
            return false
        end
    end
    return true
end

local classRun

local function summariseClasses(run)
    local counted, union, unionSize = {}, {}, 0
    for _, ids in pairs(run.sets) do
        for id in pairs(ids) do
            if not union[id] then
                union[id] = 0
                unionSize = unionSize + 1
            end
            union[id] = union[id] + 1
        end
    end
    for _, n in pairs(union) do
        counted[n] = (counted[n] or 0) + 1
    end
    local inExactly = {}
    for n = 1, #run.list do
        inExactly[n] = counted[n] or 0
    end
    local own = { classID = run.playerClassID }
    local ownIds = run.sets[run.playerClassID]
    local ownRow = run.playerIndex and run.record.perClass[run.playerIndex]
    if ownIds and ownRow and ownRow.nextFrame then
        own.startCount = run.startRead.shown
        own.explicitCount = ownRow.nextFrame.shown
        own.sameCountAndIds = run.startRead.shown == ownRow.nextFrame.shown and sameSet(ownIds, run.startIds)
    else
        own.note = "the player's class has no recorded list"
    end
    run.record.summary = { unionSize = unionSize, inExactlyNClassLists = inExactly, ownClass = own }
    return unionSize
end

-- Ends the run on every path: puts the class filter back, reads it back,
-- stops listening, writes the summary.
local function finishClasses(reason)
    local run = classRun
    if not run then
        return
    end
    classRun = nil
    local record = run.record
    record.endedBecause = reason
    local TC = C_TransmogCollection
    local restore = { wanted = run.startFilter }
    if run.startFilter ~= nil then
        restore.error = failureText(call(TC, "SetClassFilter", run.startFilter))
        restore.readBack = answer(call(TC, "GetClassFilter"))
        restore.restored = restore.readBack == run.startFilter
    else
        restore.note = "the filter could not be read at the start, so none was put back"
        restore.restored = false
    end
    record.restore = restore
    local ok, unionSize = pcall(summariseClasses, run)
    if not ok then
        record.summaryError = tostring(unionSize)
        unionSize = 0
    end
    record.events.counts = run.eventCounts
    stopListening(run.listener)
    record.tookSeconds = round3(preciseTime() - run.t0)
    print(("TCProbe: classes ended (%s) after %.1f s: %d classes, union %d appearances, filter restored: %s."):format(
        reason, record.tookSeconds, #record.perClass, unionSize, restore.restored and "yes" or "no"))
    print("TCProbe: /reload now.")
end

-- Runs one step of the recording; an error in it ends the run, restored.
local function classStep(run, step)
    if run ~= classRun then
        return
    end
    local ok, err = pcall(step)
    if not ok then
        run.record.stepError = tostring(err)
        finishClasses("error")
    end
end

local function nextClass(run, index)
    classStep(run, function()
        local entry = run.list[index]
        if not entry then
            return finishClasses("done")
        end
        local row = { classID = entry.id, className = entry.name }
        run.record.perClass[index] = row
        local set = call(C_TransmogCollection, "SetClassFilter", entry.id)
        row.setRaised = set.error ~= nil or set.missing == true
        row.setError = failureText(set)
        row.filterAfterSet = answer(call(C_TransmogCollection, "GetClassFilter"))
        row.atOnce = readList(run.category, run.location)
        C_Timer.After(0, function()
            classStep(run, function()
                local later, ids = readList(run.category, run.location)
                row.nextFrame = later
                run.sets[entry.id] = ids
                if entry.id == run.playerClassID then
                    run.playerIndex = index
                end
                print(("TCProbe: %s (%d): %d at once, %d next frame, %.1f ms"):format(
                    tostring(entry.name), entry.id, row.atOnce.entries, later.entries, row.atOnce.ms))
                C_Timer.After(0, function()
                    nextClass(run, index + 1)
                end)
            end)
        end)
    end)
end

local function startClasses(arguments)
    if classRun then
        print("TCProbe: the classes check is already running; wait for its 'classes ended' line.")
        return
    end
    local word = slotWord(arguments, "classes")
    if not word then
        return
    end
    local TC = C_TransmogCollection
    local category, info, location = slotCategory(word)
    local player = call(_G, "UnitClass", "player")
    local record = {
        startedAt = date("%H:%M:%S"), slot = word, category = category, categoryInfo = info,
        location = location,
        player = { className = player[1], classID = player[3] },
        perClass = {}, events = {},
    }
    db.classes = record
    local journal = _G.CollectionsJournal
    record.collectionsShown = journal and answer(call(journal, "IsShown", journal)) or "no CollectionsJournal"
    local startFilter = answer(call(TC, "GetClassFilter"))
    record.startFilter = startFilter
    if type(startFilter) ~= "number" then
        startFilter = nil
    end
    local ids = call(C_SpecializationInfo, "GetAllClassIDs")[1]
    local list = {}
    if type(ids) == "table" then
        record.classListFrom = "C_SpecializationInfo.GetAllClassIDs"
    else
        ids = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 }
        record.classListFrom = "ids 1 to 13 that C_CreatureInfo.GetClassInfo answers"
    end
    for _, classID in ipairs(ids) do
        local classInfo = call(C_CreatureInfo, "GetClassInfo", classID)[1]
        if type(classInfo) == "table" then
            list[#list + 1] = { id = classID, name = classInfo.className }
        end
    end
    record.classes = list
    local run = { record = record, list = list, sets = {}, eventCounts = {}, startFilter = startFilter,
        category = category, location = location, playerClassID = player[3], t0 = preciseTime() }
    run.startRead, run.startIds = readList(category, location)
    record.startList = run.startRead
    classRun = run
    local registered, refused
    run.listener, registered, refused = listen(CLASS_EVENTS, function(_, event)
        if event == "PLAYER_LOGOUT" then
            return finishClasses("logout")
        end
        run.eventCounts[event] = (run.eventCounts[event] or 0) + 1
    end)
    record.events.registered, record.events.refused = registered, refused
    print(("TCProbe: classes started for %s: %d classes, filter now %s. It asks the auction house nothing and puts the filter back."):format(
        word, #list, tostring(startFilter)))
    classStep(run, function()
        nextClass(run, 1)
    end)
end

local namesRun

-- Ends the run on every path.
local function finishNames(reason)
    local run = namesRun
    if not run then
        return
    end
    namesRun = nil
    local record = run.record
    record.endedBecause = reason
    if run.ticker then
        pcall(run.ticker.Cancel, run.ticker)
    end
    stopListening(run.listener)
    local ok, err = pcall(function()
        local named, sourcesNamed, never = 0, 0, {}
        for _, itemID in ipairs(run.items) do
            if type(call(C_Item, "GetItemInfo", itemID)[1]) == "string" then
                named = named + 1
            else
                never[#never + 1] = itemID
            end
        end
        for _, sourceID in ipairs(run.sourceIDs) do
            local info = call(C_TransmogCollection, "GetSourceInfo", sourceID)[1]
            if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
                sourcesNamed = sourcesNamed + 1
            end
        end
        table.sort(never)
        record.sourcesNamedAtEnd = sourcesNamed
        record.itemsNamedAtEnd = named
        record.neverNamed = #never
        record.neverNamedFirst10 = {}
        for i = 1, math.min(NAMES_NEVER_LISTED, #never) do
            record.neverNamedFirst10[i] = never[i]
        end
    end)
    if not ok then
        record.endError = tostring(err)
    end
    record.tookSeconds = round3(preciseTime() - run.t0)
    print(("TCProbe: names ended after %.1f s: %d of %d items named, %d never loaded"):format(
        record.tookSeconds, record.itemsNamedAtEnd or 0, #run.items, record.neverNamed or 0))
    print("TCProbe: /reload now.")
end

local function sampleNames(run)
    local named = 0
    for _, itemID in ipairs(run.items) do
        if type(call(C_Item, "GetItemInfo", itemID)[1]) == "string" then
            named = named + 1
        end
    end
    local seconds = preciseTime() - run.t0
    run.record.samples[#run.record.samples + 1] = {
        seconds = round3(seconds), requested = run.requested,
        loadedOk = run.loadedOk, loadedFailed = run.loadedFailed, itemsNamed = named,
    }
    return seconds, named
end

local function namesStep(run, step)
    if run ~= namesRun then
        return
    end
    local ok, err = pcall(step)
    if not ok then
        run.record.stepError = tostring(err)
        finishNames("error")
    end
end

-- Asks for NAMES_PER_FRAME items, then again on the next frame.
local function requestNames(run)
    namesStep(run, function()
        local last = math.min(run.requested + NAMES_PER_FRAME, #run.toRequest)
        for i = run.requested + 1, last do
            call(C_Item, "RequestLoadItemDataByID", run.toRequest[i])
        end
        run.requested = last
        if last < #run.toRequest then
            C_Timer.After(0, function()
                requestNames(run)
            end)
        end
    end)
end

local function startNames(arguments)
    if namesRun then
        print("TCProbe: the names check is already running; wait for its 'names ended' line.")
        return
    end
    local word = slotWord(arguments, "names")
    if not word then
        return
    end
    local TC = C_TransmogCollection
    local category, _, location = slotCategory(word)
    local record = { startedAt = date("%H:%M:%S"), slot = word, category = category, samples = {},
        classFilter = answer(call(TC, "GetClassFilter")) }
    db.names = record
    local _, _, order = readList(category, location)
    local sourceIDs, items, seenItem = {}, {}, {}
    for _, visualID in ipairs(order) do
        local all = call(TC, "GetAllAppearanceSources", visualID)[1]
        if type(all) == "table" then
            for _, sourceID in ipairs(all) do
                sourceIDs[#sourceIDs + 1] = sourceID
            end
        end
    end
    record.appearances, record.sources = #order, #sourceIDs
    -- at once, before anything is requested
    local started = milliseconds()
    local answered, withName = 0, 0
    for _, sourceID in ipairs(sourceIDs) do
        local info = call(TC, "GetSourceInfo", sourceID)[1]
        if type(info) == "table" then
            answered = answered + 1
            if type(info.name) == "string" and info.name ~= "" then
                withName = withName + 1
            end
            if info.itemID and not seenItem[info.itemID] then
                seenItem[info.itemID] = true
                items[#items + 1] = info.itemID
            end
        end
    end
    local toRequest, namedAtOnce = {}, 0
    for _, itemID in ipairs(items) do
        local hasName = type(call(C_Item, "GetItemInfo", itemID)[1]) == "string"
        if hasName and call(C_Item, "IsItemDataCachedByID", itemID)[1] == true then
            namedAtOnce = namedAtOnce + 1
        end
        if not hasName then
            toRequest[#toRequest + 1] = itemID
        end
    end
    record.items = #items
    record.atOnce = { sourceInfoAnswered = answered, sourcesWithName = withName,
        itemsNamedAndCached = namedAtOnce, itemsWithoutName = #toRequest,
        passMs = round3(milliseconds() - started) }
    local run = { record = record, items = items, sourceIDs = sourceIDs, toRequest = toRequest,
        requested = 0, loadedOk = 0, loadedFailed = 0, t0 = preciseTime() }
    namesRun = run
    run.listener = listen({ "ITEM_DATA_LOAD_RESULT" }, function(_, event, _, success)
        if event == "PLAYER_LOGOUT" then
            return finishNames("logout")
        end
        if success then
            run.loadedOk = run.loadedOk + 1
        else
            run.loadedFailed = run.loadedFailed + 1
        end
    end)
    print(("TCProbe: names started for %s: %d appearances, %d sources, %d items, %d without a name, at most %d s."):format(
        word, record.appearances, record.sources, #items, #toRequest, NAMES_SECONDS))
    namesStep(run, function()
        requestNames(run)
        run.ticker = C_Timer.NewTicker(NAMES_SAMPLE_EVERY, function()
            namesStep(run, function()
                local seconds, named = sampleNames(run)
                if named >= #run.items then
                    finishNames("allNamed")
                elseif seconds >= NAMES_SECONDS - 0.2 then
                    finishNames("timeLimit")
                end
            end)
        end)
        if #toRequest == 0 then
            sampleNames(run)
            finishNames("allNamed")
        end
    end)
end

local function probeStatic()
    probeClient()
    probeNamespaces()
    probeEquipped()
    probeModel()
    local transmog = db.namespaces.C_TransmogCollection
    local auction = db.namespaces.C_AuctionHouse
    print(("TCProbe: C_TransmogCollection %s functions, C_AuctionHouse %s functions. Nothing runs by itself: /tcprobe ah records the auction house while its window is open, /tcprobe tiles <slot> [cam|full] shows a page of model tiles, /tcprobe tab adds a test tab to the open auction window, /tcprobe model shows the model frames, /tcprobe collect records what the collection calls say about some 270 items, anywhere, without the auction house, /tcprobe find looks six appearances up by item name while the auction window is open (at most 10 browses and 6 searches)."):format(
        transmog and #transmog or "missing", auction and #auction or "missing"))
end

local frame = CreateFrame("Frame")
db = {}

local events = {
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "AUCTION_HOUSE_CLOSED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_KEY_ITEM_INFO_RECEIVED",
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
        -- The last session's table is kept, without the one it kept itself,
        -- so a second reload does not lose a recording.
        if type(TCProbeDB) == "table" then
            TCProbeDB.previous = nil
            db.previous = TCProbeDB
        end
        TCProbeDB = db
        db.unregisteredEvents = unregistered
        probeStatic()
        probeTooltipHook()
    elseif event == "PLAYER_LOGOUT" then
        -- a /reload inside the half second the wardrobe filter is lifted for
        restoreUncollectedFilter(true)
        -- the state the tab test ends in, after the owner's clicks
        if tab.created then
            tabMoment("logout")
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        logAuctionEvent(event)
        stopAuctionRun("auctionHouseClosed")
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        logAuctionEvent(event)
        onBrowsePage()
        onFindPage()
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
        onFindFailure()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        logAuctionEvent(event, type(payload) == "table" and payload.itemID or nil)
        onSearchResults(payload)
        onFindSearchResults(payload)
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
        logAuctionEvent(event)
        onMessageSent()
        onFindMessageSent()
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        -- One may arrive for every row the auction window lists, so they are
        -- logged only during the searches, where their timing matters.
        logAuctionEvent(event, payload, not (run and run.search))
    else
        logAuctionEvent(event)
    end
end)

SLASH_TCPROBE1 = "/tcprobe"
SlashCmdList["TCPROBE"] = function(msg)
    local word, rest = msg:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if word == "ah" then
        startAuctionRun("slash")
    elseif word == "model" then
        showModelVariants()
    elseif word == "tiles" then
        showTiles(rest)
    elseif word == "tab" then
        showTab()
    elseif word == "collect" then
        startCollectCheck()
    elseif word == "classes" then
        startClasses(rest)
    elseif word == "names" then
        startNames(rest)
    elseif word == "find" then
        startFind()
    else
        probeStatic()
    end
end
