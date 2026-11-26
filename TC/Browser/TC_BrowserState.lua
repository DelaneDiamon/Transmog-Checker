-- The appearance browser's state: the view of one visit to the auction house
-- and every rule of what to draw. It creates no frame, so it runs outside the
-- game. The panel draws what View answers and is told through the listener
-- when that answer changed.
TC = TC or {}
TC.BrowserState = {}

local State = TC.BrowserState

-- Layout B: 8 columns of 3 rows, 24 tiles a page, whether a flyout is open
-- or not.
local PAGE_SIZE = 24
local ALL_WEAPON_TYPES = "All weapon types"
-- From 100 gold up a tile leaves the copper out (spec 2.5).
local TILE_COPPER_BELOW = 100 * 10000
local STATUS_ALL = "Click an appearance to check the auction house."
local STATUS_FAILED = "The auction house did not answer."
local SCAN_AGAIN = "Scan again"
local PRICE_SLOT = "Price this slot"
-- In All the Filter starts on "Not collected" (spec Assumption A1).
local START_FILTER = "Not collected"
-- Spec Assumption A10: the progress bar expects the page count of the slot's
-- last scan, or 5 for a first scan, and stays below 95 percent until the end.
local FIRST_SCAN_PAGES, MAX_PROGRESS = 5, 0.95

State.FILTERS = { "All", "Collected", "Not collected" }

local view, listener
-- The current slot's appearances under the class, read once per visit and
-- kept per slot in lists, and whether each is collected, read again on every
-- Refresh. No list (nil) means it could not be read yet; it is never an empty
-- slot. learnt: every class's weapon types (LearnWeaponTypes), learnt once
-- per visit on the first weapon slot, nil before; learning: that pass runs.
local list, lists, collected, learnt, learning
-- True while a Refresh runs: changing Collections' class filter to learn
-- the weapon types is inferred to fire TRANSMOG_COLLECTION_UPDATED at once,
-- which would start a Refresh inside this one.
local refreshing
-- The checks of the visit, by appearance id. kept: the newest result that
-- is found, not for sale or cannot be sold, which the tile carries (A7).
-- latest: the newest finished result of any outcome, which the item list
-- shows. checking: {} for a check that runs or waits to run.
-- waitingChecks: appearances whose check waits behind the running one,
-- active: the running one ({ appearance }). known: { items, all } per
-- appearance once a check or an item read learnt them, the tradeable items
-- and all items; reading: item reads in flight. variantNames: item variants'
-- names once the client gave them, by item key. noAnswer: appearances whose
-- last check ended as "could not check", which their tile says until the next
-- click or a result.
local kept, latest, checking, waitingChecks, active, known, reading, variantNames, noAnswer
-- The scans of the visit, by slot. scans: the kept result of the slot's last
-- finished scan ({ results, none, pages, at }). scan: the one scan that runs
-- ({ slot, results, pages, expected }), or nil. failures: { results } of a
-- slot whose last scan failed, with the tiles it had found. stoppedScan: the
-- slot whose scan was stopped by leaving the tab (A6).
local scans, scan, failures, stoppedScan
-- Item variant names (TC-32). keyState: by item key, "asked" once
-- GetItemKeyInfo was called for it, "ready" when its item's event arrived
-- (one more read is allowed), "done" after that read. keyOf: the keys asked,
-- by item id, for that event. keyQueue: the keys Search still has to ask
-- for, 20 per frame; keyTicking: a frame's tick is waiting.
local keyState, keyOf, keyQueue, keyTicking
-- Raised whenever the queue is dropped, so a waiting tick of the old one stops.
local keyGen = 0
-- Raised by Reset, so late item reads of an earlier visit change nothing.
local visit = 0
-- True from Leave until Enter: the tab is not shown, so nothing is asked.
local away = false
local KEYS_PER_FRAME = 20

-- The class dropdown's value for "All classes"; a class is its class id.
local ALL_CLASSES = "all"
local ALL_CLASSES_TEXT = "All classes"

-- For a developer, read with /dump TC.BrowserState.lastError: the text of
-- the last error from a failed list read, a failed check or a failed scan.
State.lastError = nil

-- Each visit starts on the first slot of the slot row, Head (spec 2.1, A4).
local START_SLOT = TC.Slots[1].key

local function startView()
    -- open: the appearance whose flyout is open, or nil; weaponType: the
    -- category the weapon type dropdown picks, nil for all weapon types;
    -- class: a class id or ALL_CLASSES, nil for the character's own class;
    -- search: the Search box's text
    return { mode = "All", slot = START_SLOT, filter = START_FILTER, page = 1, search = "" }
end
view = startView()

local function clearResults()
    kept, latest, checking, waitingChecks, active, known, reading, variantNames, noAnswer = {}, {}, {}, {}, nil, {}, {}, {}, {}
    scans, scan, failures, stoppedScan = {}, nil, {}, nil
    list, lists, collected, learnt, learning = nil, {}, {}, nil, false
    keyState, keyOf, keyQueue, keyTicking = {}, {}, {}, false
    keyGen = keyGen + 1
end
clearResults()

local function now()
    return GetTime and GetTime() or 0
end

-- The character's class: id, name and class file (UnitClass).
local function ownClass()
    if not UnitClass then return nil end
    local name, file, id = UnitClass("player")
    return id, name, file
end

-- The class the filter narrows to, as a class id, or nil for All classes.
local function chosenClass()
    if view.class == ALL_CLASSES then return nil end
    return view.class or (ownClass())
end

-- A class's name and class file (C_CreatureInfo.GetClassInfo,
-- CreatureInfoDocumentation.lua:11-24 and 127-135), or the character's own
-- from UnitClass.
local function classInfo(classID)
    local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
    if type(info) == "table" and info.className then return info.className, info.classFile end
    local id, name, file = ownClass()
    if id == classID then return name, file end
end

-- A weapon slot's weapon types for the class (nil: every class), once they
-- are learnt in this visit; nil before and on an armor slot.
local function weaponTypesOf(slot, class)
    if learnt == nil or not TC.Slots[slot].weapon then return nil end
    return TC.Appearances.WeaponTypes(slot, learnt, class)
end

local function keyText(key)
    return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
end

-- An item variant's own name: kept once the client gave it, else asked for.
-- A key is asked once per visit, plus one more read once the client's event
-- for its item arrived (KeyInfoReceived); not while the tab is not shown.
-- Whether an unknown key costs a server message is unverified, so each
-- call counts as one.
local function variantName(key)
    local text = keyText(key)
    if variantNames[text] then return variantNames[text] end
    local was = keyState[text]
    if away or was == "done" or was == "asked" then return nil end
    keyState[text] = was and "done" or "asked"
    if not was then
        keyOf[key.itemID] = keyOf[key.itemID] or {}
        table.insert(keyOf[key.itemID], key)
    end
    variantNames[text] = TC.Check.VariantName(key)
    return variantNames[text]
end

-- An error in the listener goes to the client's error handler, so a failed
-- draw stops no check.
local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

-- Inside batch, the listener is told once, at the end.
local holding, held = 0, false
local function notify()
    if holding > 0 then
        held = true
    elseif listener then
        xpcall(listener, report)
    end
end
local function batch(fn)
    holding = holding + 1
    local ok, err = pcall(fn)
    holding = holding - 1
    if holding == 0 and held then
        held = false
        notify()
    end
    if not ok then error(err, 0) end
end

-- The rows a running or failed scan has grouped so far for an appearance.
local function runResult(run, id)
    local group = run.found and run.found[id]
    return group and { outcome = "found", rows = group.rows, partial = true }
end

-- What the slot's scans say about an appearance: the kept scan's result,
-- else the running first scan's rows so far; nil when no scan says anything.
local function scanResult(id)
    local s = scans[view.slot]
    if s then return s.results[id] or s.none end
    if scan and scan.slot == view.slot then return runResult(scan, id) end
end

-- The result a tile carries: the newest read wins, a check or a scan (a
-- finished scan drops the check results of its slot).
local function tileResult(id)
    return kept[id] or scanResult(id)
end

-- For sale also keeps the tiles a failed first scan had found (spec 2.9),
-- though that scan is not kept.
local function forSaleResult(id)
    local failure = failures[view.slot]
    return tileResult(id) or (failure and runResult(failure, id))
end

-- The list narrowed to the weapon type and the class filter, on the client
-- (A3). An armor slot: the appearances the class can use. A weapon slot:
-- those of the chosen weapon type, else of the class's weapon types (TC-38),
-- each weapon type's in its own order, in the order of the weapon types, an
-- appearance once; an appearance of two weapon types shows under each.
local function typed()
    local class = chosenClass()
    local kinds = view.weaponType and { view.weaponType }
    if not kinds and class ~= nil and TC.Slots[view.slot].weapon then
        kinds = {}
        for i, weapon in ipairs(weaponTypesOf(view.slot, class) or {}) do kinds[i] = weapon.category end
    end
    if kinds == nil and class == nil then return list or {} end
    local out = {}
    if kinds == nil then
        for _, appearance in ipairs(list or {}) do
            if TC.Appearances.UsableBy(appearance, class) then out[#out + 1] = appearance end
        end
        return out
    end
    local seen = {}
    for _, kind in ipairs(kinds) do
        local own = {}
        for _, appearance in ipairs(list or {}) do
            if appearance.categories[kind] and not seen[appearance] then own[#own + 1] = appearance end
        end
        table.sort(own, function(a, b) return a.categories[kind] < b.categories[kind] end)
        for _, appearance in ipairs(own) do
            seen[appearance] = true
            out[#out + 1] = appearance
        end
    end
    return out
end

-- For sale (A3): the list narrowed to the appearances that are not collected
-- and are found for sale, lowest price first, equal prices by appearance id.
local function forSale()
    local out, price = {}, {}
    for _, appearance in ipairs(typed()) do
        local result = not collected[appearance.id] and forSaleResult(appearance.id)
        if result and result.rows[1] then
            out[#out + 1] = appearance
            price[appearance] = result.rows[1].minPrice
        end
    end
    table.sort(out, function(a, b)
        if price[a] ~= price[b] then return price[a] < price[b] end
        return a.id < b.id
    end)
    return out
end

-- Search (TC-32): an appearance stays when the name of one of its items
-- contains the text, whatever the case; in For sale also when the name of
-- an item variant the scan found does. A name the client has not loaded
-- does not match. It only reads what is known; names are asked for by
-- startSearch.
local function matches(appearance, text)
    for _, itemID in ipairs(TC.Appearances.ItemIDs(appearance)) do
        local name = TC.Appearances.ItemName(itemID)
        if name and name:lower():find(text, 1, true) then return true end
    end
    if view.mode ~= "For sale" then return false end
    local result = forSaleResult(appearance.id)
    for _, row in ipairs(result and result.rows or {}) do
        local name = variantNames[keyText(row.itemKey)]
        if name and name:lower():find(text, 1, true) then return true end
    end
    return false
end

-- The appearances the mode, the Filter and, unless ignoreSearch, the Search
-- keep, in the mode's order.
local function shown(ignoreSearch)
    local out
    if view.mode == "For sale" then
        out = forSale()
    else
        out = {}
        for _, appearance in ipairs(typed()) do
            local isCollected = collected[appearance.id]
            if view.filter == "All" or (view.filter == "Collected") == isCollected then
                out[#out + 1] = appearance
            end
        end
    end
    if ignoreSearch or view.search == "" then return out end
    local text, found = view.search:lower(), {}
    for _, appearance in ipairs(out) do
        if matches(appearance, text) then found[#found + 1] = appearance end
    end
    return found
end

local function pageCount(n)
    return math.ceil(n / PAGE_SIZE)
end

-- The page that holds the appearance, or nil when it is not shown.
local function pageHolding(id)
    for i, appearance in ipairs(shown()) do
        if appearance.id == id then return math.ceil(i / PAGE_SIZE) end
    end
end

-- The flyout closes when its tile is no longer on the page shown: a flyout
-- points at its tile (layout B). Answers whether it closed.
local function settle()
    if view.open and pageHolding(view.open.id) ~= view.page then
        view.open = nil
        return true
    end
    return false
end

local function clampPage()
    local page = math.max(1, math.min(view.page, pageCount(#shown())))
    local changed = page ~= view.page
    view.page = page
    return changed
end

-- Search's variant names (TC-32): the keys of the slot's scan rows that have
-- no name yet are asked for, the first KEYS_PER_FRAME at once and then that
-- many a frame, while the tab is shown. keyTick is the one that asks.
local scheduleKeys
local function keyTick()
    keyTicking = false
    local n, learnt = 0, false
    while keyQueue[1] and n < KEYS_PER_FRAME do
        local key = table.remove(keyQueue, 1)
        local was = keyState[keyText(key)]
        if was == nil or was == "ready" then
            n = n + 1
            if variantName(key) then learnt = true end
        end
    end
    if keyQueue[1] then scheduleKeys() end
    if learnt then
        settle()
        clampPage()
        notify()
    end
end

function scheduleKeys()
    if keyTicking or not keyQueue[1] or not (C_Timer and C_Timer.After) then return end
    keyTicking = true
    local mine, gen = visit, keyGen
    C_Timer.After(0, function()
        if mine == visit and gen == keyGen and not away then keyTick() end
    end)
end

-- Drops what is waiting to be asked, on leaving the tab, on a slot change
-- and when the visit ends.
local function dropKeys()
    keyQueue, keyTicking = {}, false
    keyGen = keyGen + 1
end

local function startKeys()
    if keyTicking or away or not list then return end
    local seen = {}
    for _, appearance in ipairs(list) do
        local result = not collected[appearance.id] and forSaleResult(appearance.id)
        for _, row in ipairs(result and result.rows or {}) do
            local text = keyText(row.itemKey)
            local was = keyState[text]
            if not seen[text] and not variantNames[text] and (was == nil or was == "ready") then
                seen[text] = true
                keyQueue[#keyQueue + 1] = row.itemKey
            end
        end
    end
    keyTick()
end

-- Search is in use on the slot: the names of its items (item data) and, in
-- For sale, of its scan's item variants are asked for (never the auction
-- house's rows).
local function startSearch()
    if view.search == "" or not list or away then return end
    local ids = {}
    for _, appearance in ipairs(list) do
        for _, itemID in ipairs(TC.Appearances.ItemIDs(appearance)) do ids[#ids + 1] = itemID end
    end
    TC.Appearances.LoadNames(ids)
    if view.mode == "For sale" then startKeys() end
end

-- "64 of 370 appearances" when the mode or the Filter narrows the list.
local function countText(n, total)
    local noun = total == 1 and "appearance" or "appearances"
    if n == total and view.mode == "All" then
        return ("%d %s"):format(total, noun)
    end
    return ("%d of %d %s"):format(n, total, noun)
end

function State.SetListener(fn)
    listener = fn
end

-- Starts learning every class's weapon types; a pass that ends on a later
-- frame refreshes.
local function learnWeaponTypes()
    learning = true
    local mine, now = visit, true
    TC.Appearances.LearnWeaponTypes(function(types)
        if mine ~= visit then return end
        learnt, learning = types, false
        if not now then State.Refresh() end
    end, function(text) State.lastError = text end)
    now = false
end

-- Reads the list if there is none and whether each appearance is collected;
-- answers whether anything changed. An empty or failed read keeps no list,
-- so the next Refresh reads again. A weapon slot waits for its weapon types.
local function read()
    local changed = false
    local slot = view.slot
    if TC.Slots[slot].weapon and learnt == nil then
        if not learning then learnWeaponTypes() end
        if learnt == nil then return changed end
        changed = true
    end
    if not list then
        local result = TC.Appearances.List(slot, nil, weaponTypesOf(slot))
        if type(result) ~= "table" or not result[1] then return changed end
        list, changed = result, true
        lists[slot] = result
    end
    for _, appearance in ipairs(list) do
        local isCollected = TC.Appearances.IsCollected(appearance)
        if collected[appearance.id] ~= isCollected then
            collected[appearance.id] = isCollected
            changed = true
        end
    end
    return changed
end

-- Called when the panel is shown and when the collection changes; collected
-- is never kept beyond that. An error from the appearance source is no list
-- yet and does not reach the player. Answers whether the listener was told.
function State.Refresh()
    if refreshing then return false end
    refreshing = true
    local ok, changed = pcall(read)
    refreshing = false
    if not ok then
        State.lastError = tostring(changed)
        changed = list ~= nil
        list, lists[view.slot] = nil, nil
    end
    changed = settle() or changed
    if clampPage() or changed then
        notify()
        return true
    end
    return false
end

-- While the buy dialog is open nothing that reads the auction house starts
-- from the browser: the dialog is closed first (TC_Buy).
local function dialogOpen()
    return TC.Buy ~= nil and TC.Buy.IsOpen()
end

-- Whether a check or a scan runs or waits to run.
local function readsRunning()
    return scan ~= nil or next(checking) ~= nil
end

-- Stops the running check and the waiting ones, and the running scan, with
-- everything in the queue; their results are not kept. left: the player left
-- the tab, so the scan's slot is scanned again on coming back (A6).
local function stopReads(left)
    TC.Check.CancelAll()
    TC.AuctionQueue.CancelAll()
    if scan and left then stoppedScan = scan.slot end
    scan = nil
    checking, waitingChecks, active = {}, {}, nil
end

-- Learns the appearance's items for the head of its list, when no check
-- did: item data only, nothing is read from the auction house.
local function learnItems(appearance)
    local id = appearance.id
    if known[id] or reading[id] then return end
    reading[id] = true
    local mine = visit
    local ok = pcall(TC.Check.Items, appearance, function(items, all)
        if mine ~= visit then return end
        reading[id], known[id] = nil, { items = items, all = all }
        notify()
    end)
    if not ok then reading[id] = nil end
end

-- A new visit: the start state, and nothing kept from the last one. The
-- queue is cancelled and late answers change nothing.
function State.Reset()
    local changed = next(lists) ~= nil or view.mode ~= "All" or view.slot ~= START_SLOT or view.filter ~= START_FILTER
        or view.page ~= 1 or view.open ~= nil or next(latest) ~= nil or next(checking) ~= nil or next(scans) ~= nil
        or scan ~= nil or next(failures) ~= nil or view.search ~= "" or view.class ~= nil
    if TC.Buy then TC.Buy.Close() end
    stopReads()
    TC.Appearances.StopWeaponTypes()
    visit = visit + 1
    view = startView()
    clearResults()
    TC.Appearances.ResetLoads()
    if changed then notify() end
end

-- The player left the tab (A6): the running scan and the running and
-- waiting checks stop and their results are discarded; finished results and
-- the view stay.
function State.Leave()
    -- leaving the tab closes the buy dialog and buys nothing
    if TC.Buy then TC.Buy.Close() end
    -- nothing is asked while the tab is not shown (TC-32)
    away = true
    dropKeys()
    TC.Appearances.StopLoads()
    -- a weapon type pass puts the class filter back at once and runs again
    -- on the next need
    TC.Appearances.StopWeaponTypes()
    learning = false
    if not next(checking) and not scan then return end
    batch(function()
        stopReads(true)
        notify()
    end)
end

-- Starts a scan of the current slot. Its result replaces the slot's kept
-- scan and the check results of the slot's appearances; a failed one is not
-- kept.
local function startScan()
    local slot = view.slot
    local run = { slot = slot, pages = 0,
        expected = scans[slot] and scans[slot].pages or FIRST_SCAN_PAGES }
    scan, failures[slot] = run, nil
    local function onProgress(found, pages)
        if scan ~= run then return end
        run.pages, run.found = pages, found
        settle()
        notify()
    end
    local function onDone(result, reason)
        if scan ~= run then return end
        scan = nil
        if result then
            local at = now()
            local s = { results = {}, pages = result.pages, at = at,
                none = { outcome = "not for sale", rows = {}, at = at, scanned = true } }
            for id, group in pairs(result.appearances) do
                s.results[id] = { outcome = "found", rows = group.rows, at = at, scanned = true }
            end
            scans[slot] = s
            for id, r in pairs(kept) do if r.slot == slot then kept[id] = nil end end
            for id, r in pairs(latest) do if r.slot == slot then latest[id] = nil end end
        else
            failures[slot] = { found = run.found }
            State.lastError = tostring(reason)
        end
        settle()
        clampPage()
        if result and slot == view.slot then startSearch() end
        notify()
    end
    local ok, err = pcall(TC.Scan.Run, slot, onProgress, onDone, weaponTypesOf(slot))
    if not ok then onDone(nil, err) end
end

-- Scans the current slot unless a scan of it runs. One scan runs at a time:
-- a scan of another slot is stopped first, with the checks and the queue,
-- and is not kept, so its slot counts as not scanned.
local function scanSlot()
    if scan and scan.slot == view.slot then return end
    if scan then stopReads() end
    startScan()
end

-- All or For sale (the catalogue and sweep toggles): page 1, no flyout. For
-- sale scans the slot at once unless it was scanned in this visit or a scan
-- of it runs; All reads nothing.
function State.SelectMode(mode)
    if mode == view.mode or dialogOpen() then return end
    batch(function()
        view.mode, view.page, view.open = mode, 1, nil
        if mode == "For sale" and not scans[view.slot] then scanSlot() end
        startSearch()
        notify()
    end)
end

-- A click on a slot of the slot row: page 1, no item list, the weapon type
-- back on all weapon types; the mode and the Filter stay. In All nothing is
-- read from the auction house. In For sale the slot is scanned at once
-- unless it was scanned in this visit; then its kept result shows. A scan of
-- the slot left keeps running and is kept under that slot, unless this
-- slot needs a scan (scanSlot). The name loading of the slot left stops;
-- a search text that is not empty counts as a use of Search on the new slot.
function State.SelectSlot(slot)
    if slot == view.slot or not TC.Slots[slot] or dialogOpen() then return end
    batch(function()
        TC.Appearances.StopLoads()
        dropKeys()
        view.slot, view.weaponType, view.page, view.open = slot, nil, 1, nil
        list = lists[slot]
        State.Refresh()
        if view.mode == "For sale" and not scans[slot] then scanSlot() end
        startSearch()
        notify()
    end)
end

-- The weapon type dropdown: a category of the slot's weapon types, or nil
-- for all weapon types. It narrows on the client, reads nothing and goes to
-- page 1.
function State.SelectWeaponType(category)
    if not TC.Slots[view.slot].weapon or category == view.weaponType then return end
    view.weaponType, view.page = category, 1
    settle()
    notify()
end

-- The weapon type goes back to all weapon types when the chosen class has
-- not got it (TC-38).
local function fitWeaponType()
    if view.weaponType == nil then return end
    for _, weapon in ipairs(weaponTypesOf(view.slot, chosenClass()) or {}) do
        if weapon.category == view.weaponType then return end
    end
    view.weaponType = nil
end

-- The funnel's class choice: a class id, or ALL_CLASSES. It narrows on the client
-- in both modes (A3), keeps the slot, the mode, the Filter, the weapon type
-- when the class has it, and the search, goes to page 1 and reads nothing.
function State.SelectClass(value)
    local was = view.class == ALL_CLASSES and ALL_CLASSES or chosenClass()
    if value == nil or value == was then return end
    view.class, view.page = value, 1
    fitWeaponType()
    settle()
    notify()
end

-- The Search box's text. Typing narrows on the client and goes to page 1.
-- Its use asks the client for the names of the slot's items it has not
-- loaded (item data only, never the auction house's rows) and, in For sale,
-- of the item variants the scan found; each only once (startSearch). They
-- narrow further as they arrive.
function State.SetSearch(text)
    text = text or ""
    if text == view.search then return end
    view.search, view.page = text, 1
    startSearch()
    settle()
    notify()
end

-- ITEM_KEY_ITEM_INFO_RECEIVED(itemID): the keys asked for that item may be
-- read once more.
function State.KeyInfoReceived(itemID)
    local keys = keyOf[itemID]
    if not keys then return end
    local searching = not away and view.mode == "For sale" and view.search ~= ""
    for _, key in ipairs(keys) do
        if keyState[keyText(key)] == "asked" then
            keyState[keyText(key)] = "ready"
            if searching then keyQueue[#keyQueue + 1] = key end
        end
    end
    if searching then scheduleKeys() end
end

-- Names that arrive tell the listener once per frame, not once per name.
local nameWait = false
TC.Appearances.SetNameListener(function()
    if nameWait then return end
    nameWait = true
    local mine = visit
    local function tell()
        nameWait = false
        if mine ~= visit then return end
        settle()
        clampPage()
        notify()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, tell) else tell() end
end)

-- "Scan again": a new scan of the current slot, in either mode. The old
-- result stays on screen until the new one ends.
function State.ScanAgain()
    if (scan and scan.slot == view.slot) or dialogOpen() then return end
    batch(function()
        scanSlot()
        notify()
    end)
end

-- The player came back to the tab: in For sale a scan of this slot stopped
-- by leaving runs again (A6).
function State.Enter()
    away = false
    if not stoppedScan then return end
    local stopped = stoppedScan
    stoppedScan = nil
    if view.mode ~= "For sale" or stopped ~= view.slot or scan then return end
    batch(function()
        startScan()
        notify()
    end)
end

-- The funnel's Show choice (the Filter). In For sale it is fixed on Not
-- collected (D3); the player's choice for All stays.
function State.SetFilter(filter)
    if view.mode == "For sale" or filter == view.filter then return end
    view.filter, view.page = filter, 1
    settle()
    notify()
end

-- Whether the funnel's choices are the start's: Show on Not collected and the
-- character's own class.
local function filtersAtStart()
    -- in the sweep view Show is fixed, so only the class counts
    return (view.mode == "For sale" or view.filter == START_FILTER) and (view.class == nil or view.class == (ownClass()))
end

-- "Reset filters": Show and the class back to the start, page 1; reads nothing.
function State.ResetFilters()
    if filtersAtStart() then return end
    view.filter, view.class, view.page = START_FILTER, nil, 1
    fitWeaponType()
    settle()
    notify()
end

-- Starts the next waiting check when none runs. One check runs at a time,
-- so a second click waits behind the first, which keeps its place.
local function runNext()
    if active then return end
    local appearance = table.remove(waitingChecks, 1)
    if not appearance then return end
    local run = { appearance = appearance }
    active = run
    local id = appearance.id
    local function onItems(items, all)
        if active ~= run then return end
        known[id] = { items = items, all = all }
        notify()
    end
    local function onDone(result)
        if active ~= run then return end
        result.at, result.slot = now(), appearance.slot
        latest[id] = result
        if result.outcome ~= "could not check" then kept[id] = result else noAnswer[id] = true end
        if result.error then State.lastError = result.error end
        checking[id], active = nil, nil
        settle()
        clampPage()
        -- the next check starts whatever the listener does
        runNext()
        notify()
    end
    local ok, err = pcall(TC.Check.Run, appearance, onDone, onItems)
    if not ok then
        onDone({ outcome = "could not check", rows = {}, items = {}, total = 0, leftOut = 0, queryFailed = true,
            error = tostring(err) })
    end
end

local function startCheck(appearance)
    checking[appearance.id], noAnswer[appearance.id] = {}, nil
    waitingChecks[#waitingChecks + 1] = appearance
    runNext()
end

local function closeList()
    if not view.open then return end
    view.open = nil
    notify()
end

-- A click on a tile checks or opens, two different clicks. The open tile's
-- click closes its flyout. A tile with a kept result (a check or a scan)
-- opens its flyout, moving an open one. A tile whose check runs or waits
-- does nothing. Any other tile starts its check, closing an open flyout, and
-- opens nothing; the result lands on its strip. The page never changes.
function State.ClickTile(appearance)
    if dialogOpen() then return end
    local id = appearance.id
    if view.open and view.open.id == id then return closeList() end
    local result = tileResult(id)
    if checking[id] and not result then return end
    batch(function()
        if result then
            view.open = appearance
            learnItems(appearance)
        else
            view.open = nil
            startCheck(appearance)
        end
        notify()
    end)
end

-- The flyout's close mark, Escape and a click outside it.
State.CloseList = closeList

-- "Check again" in the item list: always a new check of that appearance.
function State.CheckAgain()
    if not view.open or checking[view.open.id] or dialogOpen() then return end
    local appearance = view.open
    batch(function()
        startCheck(appearance)
        notify()
    end)
end

-- TC_Buy's report of how a purchase ended (spec 2.7 steps 5 and 6): after
-- a purchase, a gone auction or a failed purchase the check of that
-- appearance runs again, so the list and the tile show what is left. A
-- search that failed or a dialog closed before an outcome reads nothing.
function State.BuyFinished(outcome, variant)
    if outcome ~= "completed" and outcome ~= "failed" and outcome ~= "gone" then return end
    local appearance = variant and variant.appearance
    if not appearance or variant.visit ~= visit or away or checking[appearance.id] then return end
    batch(function()
        startCheck(appearance)
        notify()
    end)
end

-- Turns the page by step; a page turn closes the flyout. Answers whether
-- the page turned.
local function turn(step)
    local page = view.page + step
    if page < 1 or page > pageCount(#shown()) then return false end
    view.page, view.open = page, nil
    return true
end

function State.NextPage() if turn(1) then notify() end end
function State.PreviousPage() if turn(-1) then notify() end end

-- The mouse wheel over the tiles: up is the previous page.
function State.Wheel(delta)
    if turn(delta > 0 and -1 or 1) then notify() end
end

-- The empty-state buttons' actions.
local function showAll()
    State.SetFilter("All")
end
local function selectAll()
    State.SelectMode("All")
end
local function clearSearch()
    State.SetSearch("")
end

-- A price as its coin parts, { amount, coin }, in gold, silver, copper
-- order. Parts that are zero are left out; on a tile, from 100 gold up the
-- copper part is too (spec 2.5). Zero is "0c".
local COIN_LETTERS = { gold = "g", silver = "s", copper = "c" }
local function money(copper, onTile)
    local parts = {}
    local amounts = { gold = math.floor(copper / 10000), silver = math.floor(copper / 100) % 100, copper = copper % 100 }
    for _, coin in ipairs({ "gold", "silver", "copper" }) do
        local leftOut = coin == "copper" and onTile and copper >= TILE_COPPER_BELOW
        if amounts[coin] > 0 and not leftOut then parts[#parts + 1] = { amount = amounts[coin], coin = coin } end
    end
    if not parts[1] then parts[1] = { amount = 0, coin = "copper" } end
    return parts
end

local function moneyText(parts)
    local words = {}
    for i, part in ipairs(parts) do words[i] = part.amount .. COIN_LETTERS[part.coin] end
    return table.concat(words, " ")
end

local function plural(n, one, many)
    return n == 1 and ("1 " .. one) or (n .. " " .. many)
end

-- Ages read "just now" under one minute and "N min ago" after (A10):
-- "Checked just now", "Scanned 4 min ago".
local function age(at, verb)
    local seconds = now() - at
    if seconds < 60 then return verb .. " just now" end
    return ("%s %d min ago"):format(verb, math.floor(seconds / 60))
end

local CHECK_AGAIN = "Check again"

-- An item's own name and quality for a row that carries none, as a scan's rows
-- do not: from the items the list learnt, else the client's item data; nil
-- until it has them. Read for the open appearance's rows only.
local function itemOwn(itemID, know)
    for _, item in ipairs(know and know.all or {}) do
        if item.itemID == itemID and item.name then return item.name, item.quality end
    end
    local name, quality, _
    if C_Item and C_Item.GetItemInfo then name, _, quality = C_Item.GetItemInfo(itemID) end
    return name, quality
end

-- An item's bind type, for the buy dialog's hint: from the items the list
-- learnt, else the client's item data (value 14 of C_Item.GetItemInfo);
-- nil while unknown.
local function itemBind(itemID, know)
    for _, item in ipairs(know and know.all or {}) do
        if item.itemID == itemID and item.bindType ~= nil then return item.bindType end
    end
    if C_Item and C_Item.GetItemInfo then return (select(14, C_Item.GetItemInfo(itemID))) end
end

local function itemRows(out, items)
    for i, item in ipairs(items or {}) do out.rows[i] = { name = item.name, quality = item.quality } end
end

-- The flyout of the open appearance (spec 2.6, layout B section 6): head,
-- body and foot. The head is the type and, when collected, "Collected".
-- state is "checking", "found", "not for sale", "cannot be sold", "could not
-- check", or "not checked" after a check was stopped by leaving the tab,
-- which lists the items it had learnt. The body comes from the newest read,
-- a check or the slot's scan. A row's name is nil while it has not loaded.
-- The foot's button is off while a check runs.
local function itemList()
    local appearance = view.open
    local id = appearance.id
    local run, result, know = checking[id], latest[id] or scanResult(id), known[id]
    local slot = TC.Slots[appearance.slot]
    local out = {
        appearance = appearance, collected = collected[id] == true, weapon = slot.weapon,
        typeText = slot.name, rows = {}, foot = { button = CHECK_AGAIN, enabled = not run },
    }
    if slot.weapon then
        -- a weapon's type is its weapon type (spec 2.6)
        for _, weapon in ipairs(weaponTypesOf(appearance.slot) or {}) do
            if weapon.category == appearance.category then
                out.typeText = weapon.name
                break
            end
        end
    else
        -- the armor type of any item, tradeable or not
        for _, item in ipairs(know and know.all or {}) do
            if item.subType then
                out.typeText = out.typeText .. ", " .. item.subType:lower()
                break
            end
        end
    end
    if run then
        out.state, out.title, out.foot.age = "checking", "Checking the auction house", "Checking"
        itemRows(out, know and know.items)
        return out
    end
    if not result then
        out.state = "not checked"
        itemRows(out, know and know.items)
        return out
    end
    out.state = result.outcome
    if result.outcome ~= "could not check" and result.at then
        out.foot.age = age(result.at, result.scanned and "Scanned" or "Checked")
    end
    local itemsLeftOut = result.leftOut and ("Could not check %d of %d items."):format(result.leftOut, result.total)
    if result.outcome == "found" then
        out.title = plural(#result.rows, "item variant", "item variants") .. ", cheapest first"
        -- every found row offers Buy when the client has the calls for it
        -- (TC_Buy); it is off while a check or a scan runs
        local buyable = TC.Buy ~= nil and TC.Buy.Available()
        for i, row in ipairs(result.rows) do
            local parts = money(row.minPrice)
            local name, quality = row.name, row.quality
            if not name then name, quality = itemOwn(row.itemKey.itemID, know) end
            out.rows[i] = { name = variantName(row.itemKey) or name, quality = quality,
                forSale = "x" .. row.totalQuantity, money = parts, price = moneyText(parts) }
            if buyable then
                out.rows[i].buy = { enabled = not readsRunning(), variant = { itemKey = row.itemKey,
                    name = out.rows[i].name, quality = quality, minPrice = row.minPrice,
                    bindType = itemBind(row.itemKey.itemID, know), appearance = appearance, visit = visit } }
            end
        end
        if (result.leftOut or 0) > 0 then out.foot.note = itemsLeftOut end
    elseif result.outcome == "not for sale" then
        out.title, out.text = "Not for sale right now", "No item with this appearance is on the auction house."
        itemRows(out, result.items or (know and know.items))
    elseif result.outcome == "cannot be sold" then
        out.title, out.text = "Not for sale right now", "No item with this appearance can be sold on the auction house."
    elseif result.queryFailed then
        out.title = "The auction house did not answer."
    elseif result.noItems then
        out.title = "The items of this appearance could not be read."
    else
        out.title = itemsLeftOut
    end
    return out
end

-- The status line (spec 2.8): its text, its button and, while a scan runs,
-- the progress value. In All a slot not scanned offers "Price this slot"
-- before the hint (layout B, 7.1): one scan of the slot, as Scan again.
local function statusLine(answer)
    local slot = view.slot
    if scan and scan.slot == slot then
        answer.status = "Scanning " .. TC.Slots[slot].name:lower()
        answer.progress = math.min(scan.pages / scan.expected, MAX_PROGRESS)
    elseif failures[slot] then
        answer.status, answer.statusButton = STATUS_FAILED, SCAN_AGAIN
    elseif scans[slot] then
        answer.status, answer.statusButton = age(scans[slot].at, "Scanned"), SCAN_AGAIN
    elseif view.mode == "All" then
        answer.statusButton = PRICE_SLOT
    end
    -- the hint is advice, not state, and is drawn so (visual pass, board 9)
    answer.statusHint = answer.status == STATUS_ALL
    if answer.statusButton then answer.statusAction = State.ScanAgain end
end

-- The slot row: the 14 slots in their groups, the chosen one marked.
local function slotRow()
    local row = {}
    for i, slot in ipairs(TC.Slots) do
        row[i] = { key = slot.key, name = slot.name, group = slot.group, art = slot.art, selected = slot.key == view.slot }
    end
    return row
end

-- The weapon type dropdown of a weapon slot: its text and its entries, "All
-- weapon types" first (value nil), then the chosen class's weapon types in
-- the slot; nil while they are not learnt or when the class has none.
local function weaponDropdown()
    local types = weaponTypesOf(view.slot, chosenClass())
    if not (types and types[1]) then return nil end
    local entries = { { name = ALL_WEAPON_TYPES, selected = view.weaponType == nil } }
    local text = ALL_WEAPON_TYPES
    for _, weapon in ipairs(types) do
        local selected = weapon.category == view.weaponType
        entries[#entries + 1] = { name = weapon.name, value = weapon.category, selected = selected }
        if selected then text = weapon.name end
    end
    return { text = text, entries = entries }
end

-- The funnel's Show entries: the Filter's values, the chosen one marked.
local function showEntries(filter)
    local entries = {}
    for i, value in ipairs(State.FILTERS) do entries[i] = { name = value, value = value, selected = value == filter } end
    return entries
end

-- The funnel's class choice (spec 2.3): its text and class file (for the colour)
-- and its entries: "All classes" (value ALL_CLASSES), then the client's
-- classes in the client's order (C_SpecializationInfo.GetAllClassIDs, as
-- Blizzard_Wardrobe.lua:1641 lists them), the character's own marked; only
-- the own class when the client has no class list.
local function classDropdown()
    local own = ownClass()
    local chosen = view.class == ALL_CLASSES and ALL_CLASSES or chosenClass()
    local answer = { text = ALL_CLASSES_TEXT,
        entries = { { name = ALL_CLASSES_TEXT, value = ALL_CLASSES, selected = chosen == ALL_CLASSES } } }
    local ids = C_SpecializationInfo and C_SpecializationInfo.GetAllClassIDs and C_SpecializationInfo.GetAllClassIDs()
    if type(ids) ~= "table" or not ids[1] then ids = { own } end
    for _, classID in ipairs(ids) do
        local name, file = classInfo(classID)
        if name then
            local selected = classID == chosen
            answer.entries[#answer.entries + 1] = { name = classID == own and (name .. " (this character)") or name,
                value = classID, classFile = file, selected = selected }
            if selected then answer.text, answer.classFile = name, file end
        end
    end
    return answer
end

-- A price in full as its coin parts, as the item list shows it; for the buy
-- dialog.
function State.MoneyParts(copper)
    return money(copper)
end

-- "Buy" on the row at that index of the open item list: opens the buy
-- dialog for its item variant (TC_Buy), which runs one search. Nothing
-- happens while the dialog is open, while a check or a scan runs, or for a
-- row that offers no Buy.
function State.BuyRow(index)
    if not view.open or dialogOpen() or readsRunning() or not TC.Buy then return end
    local row = itemList().rows[index]
    if row and row.buy and row.buy.enabled then TC.Buy.Start(row.buy.variant) end
end

-- The tile tooltip (visual pass, board 7), built as Collections builds its
-- own (CollectionWardrobeUtil.SetAppearanceTooltip, Blizzard_FrameXMLUtil/
-- CollectionsUtil.lua:183-384). The client's strings and colours are read
-- when it has them; the English texts after them are the board's wording,
-- used only without them (their wording on Forever is unverified).
local function clientText(name, fallback)
    local s = _G[name]
    return type(s) == "string" and s or fallback
end
local function fontColour(name, r, g, b)
    local c = _G[name]
    if type(c) == "table" and c.GetRGB then return { c:GetRGB() } end
    return { r, g, b }
end
local LOWEST_PRICE, SEE_ITEMS, CHECK_HINT = "Lowest price", "Click to see the items for sale.", "Click to check the auction house."
local NO_ANSWER_TEXT, CHECK_AGAIN_HINT, DETAILS_HINT = "No answer from the auction house.", "Click to check again.", "Click for details."

-- An item quality's colour (C_Item.GetItemQualityColor), white without one.
local function qualityColour(quality, white)
    if type(quality) == "number" and C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok and r then return { r, g, b } end
    end
    return white
end

-- A source's name in its quality colour, the client's own or its item's
-- once loaded; until then Collections' red "Retrieving item information"
-- (GetAppearanceNameTextAndColor, CollectionsUtil.lua:132-154).
local function sourceName(source, c)
    local name, quality = source.name, source.quality
    if not name and source.itemID then
        name = TC.Appearances.ItemName(source.itemID)
        if name and C_Item and C_Item.GetItemInfo then quality = select(3, C_Item.GetItemInfo(source.itemID)) end
    end
    if not name then return clientText("RETRIEVING_ITEM_INFO", "Retrieving item information"), c.red end
    return name, qualityColour(quality, c.white)
end

-- A source's source text: "Collected" in green, or the client's name of its
-- source type (TRANSMOG_SOURCE_n) in white (GetAppearanceSourceTextAndColor,
-- CollectionsUtil.lua:156-170).
local function sourceText(source, c)
    if source.isCollected then return clientText("TRANSMOG_COLLECTED", "Collected"), c.green end
    local text = source.sourceType and _G["TRANSMOG_SOURCE_" .. source.sourceType]
    return type(text) == "string" and text or "", c.white
end

-- The boss of a boss drop with a single drop, as the header's source line
-- says it (CollectionsUtil.lua:221-232, 298-306, 312-318); nil otherwise.
local function dropText(source)
    local TCol = C_TransmogCollection
    if source.sourceType ~= (TRANSMOG_SOURCE_BOSS_DROP or 1) or not (TCol and TCol.GetAppearanceSourceDrops) then return nil end
    local drops = TCol.GetAppearanceSourceDrops(source.sourceID)
    if type(drops) ~= "table" or #drops ~= 1 then return nil end
    local drop = drops[1]
    local where = clientText("WARDROBE_TOOLTIP_ENCOUNTER_SOURCE", "%s (%s)"):format(drop.encounter, drop.instance)
    if type(drop.difficulties) == "table" and drop.difficulties[1] then
        return clientText("WARDROBE_TOOLTIP_BOSS_DROP_FORMAT_WITH_DIFFICULTIES", "Drop: %s (%s)"):format(where,
            table.concat(drop.difficulties, clientText("PLAYER_LIST_DELIMITER", ", ")))
    end
    return clientText("WARDROBE_TOOLTIP_BOSS_DROP_FORMAT", "Drop: %s"):format(where)
end

-- The source the tooltip heads with (CollectionWardrobeUtil.
-- GetDefaultSourceIndex, CollectionsUtil.lua:3-39), else the first.
local function headIndex(sources)
    local pick = CollectionWardrobeUtil and CollectionWardrobeUtil.GetDefaultSourceIndex
    local ok, index = false, nil
    if pick then ok, index = pcall(pick, sources) end
    return ok and sources[index] and index or 1
end

-- The tile tooltip's lines for an appearance, each { text, color, right,
-- rightColor, money }: the head item's name and, when not collected, its
-- source; then, with more than one item, "Other items using this
-- appearance:" and every item with its source or "Collected", collected
-- ones included (Collections hides the list for a collected appearance,
-- CollectionsUtil.lua:330); no "Tab to cycle" line. Then, when the browser
-- keeps a result for the tile, the lowest price or "Not for sale" and its
-- age, and the click hint. It reads the game's appearance data, never the
-- auction house; it asks for the data of this appearance's items whose
-- names are not loaded, once a visit (LoadNames).
function State.TileTooltip(appearance)
    local c = { white = fontColour("HIGHLIGHT_FONT_COLOR", 1, 1, 1), normal = fontColour("NORMAL_FONT_COLOR", 1, 0.82, 0),
        green = fontColour("GREEN_FONT_COLOR", 0.1, 1, 0.1), red = fontColour("RED_FONT_COLOR", 1, 0.125, 0.125),
        grey = fontColour("GRAY_FONT_COLOR", 0.5, 0.5, 0.5) }
    local sources = TC.Appearances.Sources(appearance)
    local lines, missing = {}, {}
    for _, source in ipairs(sources) do
        if not source.name and source.itemID then missing[#missing + 1] = source.itemID end
    end
    if missing[1] and not away then TC.Appearances.LoadNames(missing) end
    local head = sources[1] and headIndex(sources)
    if head then
        local name, colour = sourceName(sources[head], c)
        lines[1] = { text = name, color = colour }
        if not sources[head].isCollected then
            local text, textColour = sourceText(sources[head], c)
            local ok, drop = pcall(dropText, sources[head])
            text = ok and drop or text
            if text ~= "" then lines[#lines + 1] = { text = text, color = textColour } end
        end
    end
    if #sources > 1 then
        lines[#lines + 1] = { text = " " }
        lines[#lines + 1] = { text = clientText("WARDROBE_OTHER_ITEMS", "Other items using this appearance:"), color = c.normal }
        for i, source in ipairs(sources) do
            local name, colour = sourceName(source, c)
            local text, textColour = sourceText(source, c)
            local mark = clientText(i == head and "WARDROBE_TOOLTIP_CYCLE_ARROW_ICON" or "WARDROBE_TOOLTIP_CYCLE_SPACER_ICON", "")
            lines[#lines + 1] = { text = mark .. name, color = colour, right = text, rightColor = textColour }
        end
    end
    local result = view.mode == "For sale" and forSaleResult(appearance.id) or tileResult(appearance.id)
    if result then
        lines[#lines + 1] = { text = " " }
        local first = result.rows[1]
        if first then
            local parts = money(first.minPrice)
            lines[#lines + 1] = { text = LOWEST_PRICE, color = c.normal, right = moneyText(parts), money = parts, rightColor = c.white }
        else
            lines[#lines + 1] = { text = LOWEST_PRICE, color = c.normal, right = "Not for sale", rightColor = c.grey }
        end
        if result.at then lines[#lines + 1] = { text = age(result.at, result.scanned and "Scanned" or "Checked"), color = c.grey } end
        lines[#lines + 1] = { text = first and SEE_ITEMS or DETAILS_HINT, color = c.grey }
    elseif checking[appearance.id] then
        -- reading: no hint
    elseif noAnswer[appearance.id] then
        lines[#lines + 1] = { text = NO_ANSWER_TEXT, color = c.grey }
        lines[#lines + 1] = { text = CHECK_AGAIN_HINT, color = c.grey }
    else
        lines[#lines + 1] = { text = CHECK_HINT, color = c.grey }
    end
    return lines
end

-- What to draw now. Without a list there are no tiles and nothing that says
-- the slot has no appearance.
function State.View()
    local forSaleMode = view.mode == "For sale"
    local filter = forSaleMode and "Not collected" or view.filter
    local slot = TC.Slots[view.slot]
    local answer = {
        mode = view.mode, filter = filter, page = view.page, slots = slotRow(),
        weaponTypes = weaponDropdown(), classes = classDropdown(), search = view.search,
        filters = showEntries(filter), filterFixed = forSaleMode, filtersChanged = not filtersAtStart(),
        status = STATUS_ALL, tiles = {}, count = "",
        pageText = "", paging = false, previousEnabled = false, nextEnabled = false,
    }
    statusLine(answer)
    if not list then return answer end
    local appearances = shown()
    local pages = pageCount(#appearances)
    local size = PAGE_SIZE
    for i = (view.page - 1) * size + 1, math.min(view.page * size, #appearances) do
        local appearance = appearances[i]
        -- strip: nil while nothing is known, so no strip is drawn (visual
        -- pass, decision 3A)
        local tile = {
            appearance = appearance, collected = collected[appearance.id], weapon = slot.weapon,
            open = view.open ~= nil and view.open.id == appearance.id,
        }
        local result = forSaleMode and forSaleResult(appearance.id) or tileResult(appearance.id)
        if result and result.rows[1] then
            tile.strip, tile.money = "price", money(result.rows[1].minPrice, true)
            tile.price = moneyText(tile.money)
        elseif result then
            tile.strip, tile.price = "not for sale", "Not for sale"
        elseif checking[appearance.id] then
            tile.strip = "bar"
        elseif noAnswer[appearance.id] then
            tile.strip, tile.price = "no answer", "No answer"
        end
        answer.tiles[#answer.tiles + 1] = tile
    end
    -- while the first scan of the slot runs, placeholders fill the page, each
    -- framed like the slot's first listed appearance, and no empty state is
    -- answered, whatever the search, the class or the Filter
    local scanning = forSaleMode and scan ~= nil and scan.slot == view.slot and not scans[view.slot]
    if scanning then
        while #answer.tiles < size do
            answer.tiles[#answer.tiles + 1] = { placeholder = true, strip = "bar", cameraAppearance = list[1] }
        end
    end
    if view.open then answer.list = itemList() end
    local total = #typed()
    answer.count = countText(#appearances, total)
    answer.pageText = ("Page %d / %d"):format(view.page, math.max(pages, 1))
    -- the widest form of the page text for this count, so its room never changes
    answer.pageTextWidest = ("Page %d / %d"):format(math.max(pages, 1), math.max(pages, 1))
    answer.paging = pages > 1
    answer.previousEnabled = view.page > 1
    answer.nextEnabled = view.page < pages
    local slotWord = slot.name:lower()
    local class = chosenClass()
    local className = class and classInfo(class)
    local forClass = className and (" for " .. className) or ""
    if scanning then
        -- no empty state while the scan runs
    elseif total == 0 then
        -- the class filter or the weapon type leaves nothing of the slot (spec 2.9)
        answer.empty = { title = "No matches", text = ("No %s appearances%s."):format(slotWord, forClass) }
    elseif #appearances == 0 and view.search ~= "" and shown(true)[1] then
        -- only the search leaves nothing (spec 2.9)
        answer.empty = { title = "No matches",
            text = ("No %s appearance has an item named like \"%s\"."):format(slotWord, view.search),
            button = "Clear search", action = clearSearch }
    elseif forSaleMode then
        -- only a kept scan says nothing is for sale
        if #appearances == 0 and scans[view.slot] then
            answer.empty = { title = "Nothing for sale",
                text = ("No %s appearance you have not collected is on the auction house right now."):format(slotWord),
                button = "Show all appearances", action = selectAll }
        end
    elseif #appearances == 0 then
        -- The list is never empty (an empty read keeps no list), so past
        -- the weapon type only the Filter can leave nothing.
        local text = view.filter == "Collected" and ("No collected %s appearances%s."):format(slotWord, forClass)
            or ("Every %s appearance%s is collected."):format(slotWord, forClass)
        answer.empty = { title = "No matches", text = text, button = "Show all", action = showAll }
    end
    -- an empty state and tiles are never drawn together
    if answer.empty then answer.tiles = {} end
    return answer
end
