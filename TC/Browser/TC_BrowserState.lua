-- The appearance browser's state: the view of one visit to the auction house
-- and every rule of what to draw. It creates no frame, so it runs outside the
-- game. The panel draws what View answers and is told through the listener
-- when that answer changed.
TC = TC or {}
TC.BrowserState = {}

local State = TC.BrowserState
-- Every text is read from the locale table when it is drawn (Locales/).
local L = TC.L

-- Layout B: 8 columns of 3 rows, 24 tiles a page, whether a flyout is open
-- or not.
local PAGE_SIZE = 24
-- From 100 gold up a tile leaves the copper out (spec 2.5).
local TILE_COPPER_BELOW = 100 * 10000
-- Spec Assumption A10: the progress bar expects the page count of the slot's
-- last scan, or 5 for a first scan, and stays below 95 percent until the end.
local FIRST_SCAN_PAGES, MAX_PROGRESS = 5, 0.95

-- The Show filter's values, kept in the saved table and compared in the
-- rules, each with its name's locale key.
State.FILTERS = { { value = "all", nameKey = "SHOW_ALL" }, { value = "collected", nameKey = "COLLECTED" },
    { value = "notCollected", nameKey = "NOT_COLLECTED" } }
-- The Show choice offered while an appearance is pending (TC-39).
local PENDING_FILTER = "pending"
-- Up to 1.0.0 the saved Show was its English name: each becomes its value.
local OLD_SHOW = { ["All"] = "all", ["Collected"] = "collected", ["Not collected"] = "notCollected",
    ["Bought, not collected"] = PENDING_FILTER }
-- The sort's choices: the game's order, or by the lowest known price, the
-- appearances without one after the priced ones in the game's order. The
-- game's order keeps its stored value "default" (slice C: renamed, no
-- longer the default).
local SORTS = { { value = "default", nameKey = "SORT_COLLECTIONS" }, { value = "priceLow", nameKey = "SORT_PRICE_LOW" },
    { value = "priceHigh", nameKey = "SORT_PRICE_HIGH" } }
-- The Source filter's entry for a source whose type it does not name.
local OTHER_SOURCE = "other"

-- The six choices kept between sessions (slice B, the slot slice C, the
-- class slice D2), each with its default: Scan when shown, Show, For sale
-- only, the sort, the slot (the first of the slot row, Head) and the class:
-- "all" for All classes, else "own", the character's own (a single other
-- class is not kept, addon-settings v1: it would follow the player onto
-- another character). saved is the table they are kept in:
-- TransmogCheckerDB.browser once State.Bind handed it over, a table of this
-- file's own before.
local DEFAULTS = { scanWhenShown = true, show = "notCollected", forSaleOnly = false, sort = "priceLow", slot = TC.Slots[1].key,
    class = "own" }
local saved = {}

local function isSort(value)
    for _, sort in ipairs(SORTS) do
        if sort.value == value then return true end
    end
    return false
end

-- A saved value as the state takes it: a missing or malformed one is its
-- default; a saved Show of Bought, not collected is the default, Not
-- collected (nothing may be pending in a new session). An English Show of
-- 1.0.0 is read as its value.
local function flag(value, default)
    if type(value) == "boolean" then return value end
    return default
end
local function savedValues(t)
    local show, was = DEFAULTS.show, OLD_SHOW[t.show] or t.show
    for _, filter in ipairs(State.FILTERS) do
        if was == filter.value then show = was end
    end
    -- a slot is its key; TC.Slots is also indexed by number
    local slot = type(t.slot) == "string" and TC.Slots[t.slot] and t.slot or DEFAULTS.slot
    return { scanWhenShown = flag(t.scanWhenShown, DEFAULTS.scanWhenShown), show = show,
        forSaleOnly = flag(t.forSaleOnly, DEFAULTS.forSaleOnly), sort = isSort(t.sort) and t.sort or DEFAULTS.sort,
        slot = slot, class = t.class == "all" and "all" or DEFAULTS.class }
end
-- Takes t as the saved table: its values as the state takes them are
-- written back into it, so it holds no malformed value.
local function useSaved(t)
    for key, value in pairs(savedValues(t)) do t[key] = value end
    saved = t
end
useSaved(saved)
-- The pending sentences, by what is pending.
local function pendingTexts()
    return { bags = L.PENDING_BAGS, bought = L.PENDING_BOUGHT }
end

local view, listener
-- The current slot's appearances under the class, read once per visit and
-- kept per slot in lists, and whether each is collected, read again on every
-- Refresh. No list (nil) means it could not be read yet; it is never an empty
-- slot. learnt: every class's weapon types (LearnWeaponTypes), learnt once
-- per visit on the first weapon slot, nil before; learning: that pass runs.
-- noneFound: the slots whose last list read answered no appearance or raised
-- (testpass F9); they are read again on the next Refresh. partial: the
-- slots whose list is shown but not final (TC-43: narrowed while
-- Collections is shown); read again on the next Refresh.
local list, lists, collected, learnt, learning, noneFound, partial
-- The weapon slot Scan when shown left waiting for that pass, or nil.
local waitingSlot
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
-- The source types of each appearance, read once per visit and only while
-- the Source filter narrows: by appearance id, a set of Source entries.
-- unsure: the same for an appearance one of whose types the client did not
-- give (sourceKeys).
local sourcesOf, unsure
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
-- True from Enter until Leave: the tab is shown, so Scan when shown may scan.
local entered = false
local KEYS_PER_FRAME = 20
-- Bought, not collected (TC-39): an item that binds when equipped is
-- collected only when it is equipped or sold to a vendor (measured in game).
-- bought: the appearances of the purchases this addon completed, kept until
-- the UI is reloaded (no visit's Reset discards them). bags: the appearances
-- the bags' items carry, as last read (SetBags). pending: of both, those not
-- collected, each "bags" or "bought" (the bags first).
-- seen: the bought appearances an item of which a bag read has found; from
-- then on only the bags decide (selling or mailing the item away ends it).
local bought, bags, pending, seen = {}, {}, {}, {}
-- The lowest price the browser saw this session, for the item tooltip
-- (slice D1): by appearance id, { copper, at, slot } from the latest
-- finished scan or check that answered for it. Kept in memory only: no
-- visit's Reset discards it, a reload does.
local sessionPrices = {}

-- The class dropdown's value for "All classes"; a class is its class id.
local ALL_CLASSES = "all"

-- For a developer, read with /dump TC.BrowserState.lastError: the text of
-- the last error from a failed list read, a failed check or a failed scan.
State.lastError = nil

-- Each visit starts on the saved slot, else Head (slice C).
local function startView()
    -- open: the appearance whose flyout is open, or nil; weaponType: the
    -- category the weapon type dropdown picks, nil for all weapon types;
    -- class: a class id or ALL_CLASSES, nil for the character's own class;
    -- search: the Search box's text; filter: Show; forSaleOnly, sort: as
    -- saved; sourcesOff: the Source filter's unticked entries (a source
    -- type, or OTHER_SOURCE), none at the start
    local start = savedValues(saved)
    return { slot = start.slot, filter = start.show, forSaleOnly = start.forSaleOnly, sort = start.sort,
        class = start.class == "all" and ALL_CLASSES or nil, sourcesOff = {}, page = 1, search = "" }
end
view = startView()

local function clearResults()
    kept, latest, checking, waitingChecks, active, known, reading, variantNames, noAnswer = {}, {}, {}, {}, nil, {}, {}, {}, {}
    scans, scan, failures, stoppedScan, sourcesOf, unsure = {}, nil, {}, nil, {}, {}
    list, lists, collected, learnt, learning, noneFound, waitingSlot, partial = nil, {}, {}, nil, false, {}, nil, {}
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

-- What the tiles, the tooltip, For sale only and the sort know of an
-- appearance's price: the tile's result, else the rows a failed first scan
-- of the slot had found (spec 2.9), though that scan is not kept.
local function forSaleResult(id)
    local failure = failures[view.slot]
    return tileResult(id) or (failure and runResult(failure, id))
end

-- The lowest price known for an appearance, or nil.
local function priceOf(id)
    local result = forSaleResult(id)
    return result and result.rows[1] and result.rows[1].minPrice
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

-- A string when it has a text, else nil. The client's own texts (the tile
-- tooltip and the Source filter) are read through TC.ClientText
-- (Locales/Locale.lua): the client's in its own language, else ours.
local function nonEmpty(s)
    return type(s) == "string" and s ~= "" and s or nil
end

-- The Source filter's entries: one per source type the client names
-- (TRANSMOG_SOURCE_n, else TC.SOURCE_TYPES' name of our own), n from 1 to
-- C_TransmogCollection.GetNumTransmogSources, else to the last English
-- one, leaving out a type IsValidTransmogSource refuses, as Collections
-- lists them (Blizzard_Collections/Mainline/Blizzard_Wardrobe.lua:67-71;
-- TransmogItemsDocumentation.lua:574, 833); then Other. Read once.
local sourceEntries
local function sourceTypes()
    if sourceEntries then return sourceEntries end
    local TCol, english = C_TransmogCollection, TC.SOURCE_TYPES or {}
    local ok, count = false, nil
    if TCol and TCol.GetNumTransmogSources then ok, count = pcall(TCol.GetNumTransmogSources) end
    if not (ok and type(count) == "number") then count = #english end
    local entries = {}
    for n = 1, count do
        local valid = true
        if TCol and TCol.IsValidTransmogSource then
            local asked, answer = pcall(TCol.IsValidTransmogSource, n)
            valid = not asked or answer ~= false
        end
        local name = valid and TC.ClientText("TRANSMOG_SOURCE_" .. n, english[n] and english[n].nameKey)
        if name then entries[#entries + 1] = { key = n, name = name } end
    end
    entries[#entries + 1] = { key = OTHER_SOURCE, name = L.SOURCE_OTHER }
    sourceEntries = entries
    return entries
end

-- The Source entries of an appearance: the type of each of its sources as
-- the tile tooltip reads them (TC.Appearances.Sources, one
-- GetAppearanceSources call, no item data asked for), a type the filter
-- does not name, none or a read that raises as Other. Read once per visit,
-- unless a source's type came back nil (Nilable before its item data is in,
-- AppearanceSourceDocumentation.lua:21; for some items for good, TC-43):
-- then it is kept only until the next Refresh or the next item names that
-- arrive (unsure), and read again after, until every type is known.
local function sourceKeys(appearance)
    local keys = sourcesOf[appearance.id] or unsure[appearance.id]
    if keys then return keys end
    keys = {}
    local named, unknown = {}, false
    for _, entry in ipairs(sourceTypes()) do named[entry.key] = true end
    local ok, sources = pcall(TC.Appearances.Sources, appearance)
    if not ok then State.lastError = tostring(sources) end
    for _, source in ipairs(ok and type(sources) == "table" and sources or {}) do
        local n = source.sourceType
        if n == nil then unknown = true end
        keys[(type(n) == "number" and named[n]) and n or OTHER_SOURCE] = true
    end
    if not next(keys) then keys[OTHER_SOURCE] = true end
    if unknown then unsure[appearance.id] = keys else sourcesOf[appearance.id] = keys end
    return keys
end

-- Whether the Source filter keeps the appearance: with every entry ticked
-- it keeps all and reads nothing; else one of its sources' entries is ticked.
local function fromSources(appearance)
    if not next(view.sourcesOff) then return true end
    for key in pairs(sourceKeys(appearance)) do
        if not view.sourcesOff[key] then return true end
    end
    return false
end

-- Search (TC-32): an appearance stays when the name of one of its items
-- contains the text, whatever the case; with For sale only also when the
-- name of an item variant the scan found does. A name the client has not
-- loaded does not match. It only reads what is known; names are asked for
-- by startSearch.
local function matches(appearance, text)
    for _, itemID in ipairs(TC.Appearances.ItemIDs(appearance)) do
        local name = TC.Appearances.ItemName(itemID)
        if name and name:lower():find(text, 1, true) then return true end
    end
    if not view.forSaleOnly then return false end
    local result = forSaleResult(appearance.id)
    for _, row in ipairs(result and result.rows or {}) do
        local name = variantNames[keyText(row.itemKey)]
        if name and name:lower():find(text, 1, true) then return true end
    end
    return false
end

-- The sort (A3 for the price): the game's order, or the priced appearances
-- by their lowest price, equal prices in the game's order, then the others
-- in the game's order.
local function sorted(out)
    if view.sort ~= "priceLow" and view.sort ~= "priceHigh" then return out end
    local price, place = {}, {}
    for i, appearance in ipairs(out) do price[appearance], place[appearance] = priceOf(appearance.id), i end
    local high = view.sort == "priceHigh"
    table.sort(out, function(a, b)
        local pa, pb = price[a], price[b]
        if pa and pb and pa ~= pb then
            if high then return pa > pb end
            return pa < pb
        end
        if (pa == nil) ~= (pb == nil) then return pa ~= nil end
        return place[a] < place[b]
    end)
    return out
end

-- The filters in the order the empty states ask about them: Show, Source,
-- For sale only, Search. For sale only is tested before Source, so the
-- sources of an appearance it leaves out are not read.
local STAGES = { show = 1, source = 2, sale = 3, search = 4 }

-- The appearances the filters keep, all of them or up to the stage upTo
-- (the empty states ask which one left nothing), in the sort's order.
local function shown(upTo)
    local last = STAGES[upTo or "search"]
    local out = {}
    for _, appearance in ipairs(typed()) do
        local id = appearance.id
        local keep
        if view.filter == PENDING_FILTER then
            keep = pending[id] and not collected[id]
        else
            keep = view.filter == "all" or (view.filter == "collected") == collected[id]
        end
        keep = keep and (last < 3 or not view.forSaleOnly or priceOf(id) ~= nil)
        keep = keep and (last < 2 or fromSources(appearance))
        if keep then out[#out + 1] = appearance end
    end
    if last < 4 then return out end
    if view.search ~= "" then
        local text, found = view.search:lower(), {}
        for _, appearance in ipairs(out) do
            if matches(appearance, text) then found[#found + 1] = appearance end
        end
        out = found
    end
    return sorted(out)
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

-- Search is in use on the slot: the names of its items (item data) and,
-- with For sale only, of its scan's item variants are asked for (never the
-- auction house's rows).
local function startSearch()
    if view.search == "" or not list or away then return end
    local ids = {}
    for _, appearance in ipairs(list) do
        for _, itemID in ipairs(TC.Appearances.ItemIDs(appearance)) do ids[#ids + 1] = itemID end
    end
    TC.Appearances.LoadNames(ids)
    if view.forSaleOnly then startKeys() end
end

-- The count: the appearances shown and, once anything of the slot has a
-- price result (a scan, kept, running or failed, or a check), how many of
-- them are for sale: "365 appearances, 12 for sale".
local function countText(appearances)
    local n = #appearances
    local text = TC.Plural("COUNT_APPEARANCES", n):format(n)
    local slot = view.slot
    local known = scans[slot] ~= nil or failures[slot] ~= nil or (scan ~= nil and scan.slot == slot)
    for _, result in pairs(kept) do known = known or result.slot == slot end
    if not known then return text end
    local forSale = 0
    for _, appearance in ipairs(appearances) do
        if priceOf(appearance.id) then forSale = forSale + 1 end
    end
    return TC.Plural("COUNT_FOR_SALE", forSale):format(text, forSale)
end

function State.SetListener(fn)
    listener = fn
end

-- Scan when shown (below); declared here for the weapon type pass.
local autoScan

-- Starts learning every class's weapon types; a pass that ends on a later
-- frame refreshes, and Scan when shown may then scan the weapon slot that
-- waited for it, when it is still the current slot.
local function learnWeaponTypes()
    learning = true
    local mine, now = visit, true
    TC.Appearances.LearnWeaponTypes(function(types)
        if mine ~= visit then return end
        learnt, learning = types, false
        if not now then
            local waited = waitingSlot
            waitingSlot = nil
            batch(function()
                State.Refresh()
                if waited == view.slot and autoScan() then notify() end
            end)
        end
    end, function(text) State.lastError = text end)
    now = false
end

-- Works out which appearances are pending: those of the bags and the
-- purchases that are not collected; a collected one leaves the purchases, and
-- so does one that was seen in the bags and is not there now. Answers whether
-- that changed. It changes nothing when the collected check raises.
local function updatePending()
    local now, changed = {}, false
    for _, from in ipairs({ { bags, "bags" }, { bought, "bought" } }) do
        for id in pairs(from[1]) do
            local gone = from[2] == "bought" and seen[id] and not bags[id]
            if not now[id] and not gone and not TC.Appearances.IsCollected({ id = id }) then now[id] = from[2] end
        end
    end
    for id in pairs(bought) do
        if not now[id] then
            bought[id], seen[id] = nil, nil
        elseif bags[id] then
            seen[id] = true
        end
    end
    for id, source in pairs(now) do
        if pending[id] ~= source then changed = true end
    end
    for id in pairs(pending) do
        if not now[id] then changed = true end
    end
    pending = now
    return changed
end

-- updatePending for the callers outside the list read: a raise from the
-- appearance API leaves the pending state as it was and is reported once.
local pendingFailed = false
local function tryPending()
    local ok, changed = pcall(updatePending)
    if ok then return changed end
    State.lastError = tostring(changed)
    if not pendingFailed then
        pendingFailed = true
        report(changed)
    end
    return false
end

-- A list read that waited (TC-43) can be read again; its note is kept in
-- lastError. Nothing is read while the tab is not shown.
local function listReady(note)
    if note then State.lastError = note end
    if not away then State.Refresh() end
end
-- Collections' filter category not put back (TC-43) is kept in lastError.
TC.Appearances.SetListErrorListener(function(text) State.lastError = text end)

-- Reads the list if there is none and whether each appearance is collected;
-- answers whether anything changed. An empty or failed read keeps no list,
-- so the next Refresh reads again. A weapon slot waits for its weapon types;
-- a read that waits (TC.Appearances.List answers nil) is no list yet, as
-- while it loads, and listReady reads again; a list not final (partial) is
-- shown and read again.
-- Answers also the error text when the list read raised.
local function read()
    local changed = updatePending()
    local slot = view.slot
    if TC.Slots[slot].weapon and learnt == nil then
        if not learning then learnWeaponTypes() end
        if learnt == nil then return changed end
        changed = true
    end
    if not list or partial[slot] then
        local ok, result, note, notFinal = pcall(TC.Appearances.List, slot, nil, weaponTypesOf(slot), listReady)
        if ok and note then State.lastError = note end
        if ok and result == nil then return changed end
        if not ok or type(result) ~= "table" or not result[1] then
            changed = changed or not noneFound[slot]
            noneFound[slot], partial[slot] = true, nil
            -- a list not final that reads nothing now is no list either
            if list then list, lists[slot], changed = nil, nil, true end
            if ok then return changed end
            lists[slot] = nil
            return changed, tostring(result)
        end
        list, changed = result, true
        lists[slot], noneFound[slot], partial[slot] = result, nil, notFinal or nil
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
-- is never kept beyond that. An error from the list read is no list yet: the
-- slot says no appearances were found. An error elsewhere in the read keeps
-- what the grid showed. Either is kept in lastError and reported once.
-- Answers whether the listener was told.
local readFailed = false
function State.Refresh()
    if refreshing then return false end
    refreshing = true
    unsure = {}
    local ok, changed, listError = pcall(read)
    refreshing = false
    local failure = not ok and tostring(changed) or listError
    if failure then
        State.lastError = failure
        if not readFailed then
            readFailed = true
            report(failure)
        end
        if not ok then changed = true end
    end
    changed = settle() or changed
    if clampPage() or changed then
        notify()
        return true
    end
    return false
end

-- The appearances the bags' items carry (TC.Appearances.ReadBags), from the
-- panel when the tab is shown and once per bag change while it is shown.
-- With a list, the listener is told when what is pending changed.
function State.SetBags(found)
    bags = found or {}
    if tryPending() and list then
        settle()
        clampPage()
        notify()
    end
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
    local start = startView()
    local changed = next(lists) ~= nil or view.slot ~= start.slot or view.filter ~= start.filter
        or view.forSaleOnly ~= start.forSaleOnly or view.sort ~= start.sort or next(view.sourcesOff) ~= nil
        or view.page ~= 1 or view.open ~= nil or next(latest) ~= nil or next(checking) ~= nil or next(scans) ~= nil
        or scan ~= nil or next(failures) ~= nil or view.search ~= "" or view.class ~= start.class
    if TC.Buy then TC.Buy.Close() end
    stopReads()
    TC.Appearances.StopWeaponTypes()
    TC.Appearances.StopLists()
    visit = visit + 1
    view = start
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
    away, entered = true, false
    dropKeys()
    TC.Appearances.StopLoads()
    -- a weapon type pass puts the class filter back at once and runs again
    -- on the next need
    TC.Appearances.StopWeaponTypes()
    -- a list read waiting a frame puts Collections' filter category back (TC-43)
    TC.Appearances.StopLists()
    learning, waitingSlot = false, nil
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
            -- the scan answers for every appearance of its slot
            for id, p in pairs(sessionPrices) do if p.slot == slot then sessionPrices[id] = nil end end
            for id, group in pairs(result.appearances) do
                local first = group.rows[1]
                if first then sessionPrices[id] = { copper = first.minPrice, at = at, slot = slot } end
            end
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

-- Scan when shown (slice B): while the tab is shown and the setting is on,
-- the current slot is scanned unless a scan of it runs or it has a kept
-- scan of this visit (again: also then, for a scan stopped by leaving the
-- tab). A weapon slot waits for its weapon types (the pass ends on a later
-- frame and comes back here). Answers whether a scan started.
function autoScan(again)
    if not (saved.scanWhenShown and entered) or away or dialogOpen() then return false end
    if (scan and scan.slot == view.slot) or (scans[view.slot] and not again) then return false end
    if TC.Slots[view.slot].weapon and learnt == nil then
        waitingSlot = view.slot
        return false
    end
    scanSlot()
    return true
end

-- A click on a slot of the slot row: page 1, no item list, the weapon type
-- back on all weapon types; the other filters and the sort stay. Nothing is
-- read from the auction house, unless Scan when shown scans the slot
-- (autoScan); a slot scanned in this visit shows its kept result. A scan of
-- the slot left keeps running and is kept under that slot, unless this
-- slot is scanned (scanSlot). The name loading of the slot left stops;
-- a search text that is not empty counts as a use of Search on the new slot.
-- The slot is kept between sessions (slice C).
function State.SelectSlot(slot)
    if slot == view.slot or not TC.Slots[slot] or dialogOpen() then return end
    batch(function()
        TC.Appearances.StopLoads()
        dropKeys()
        view.slot, view.weaponType, view.page, view.open = slot, nil, 1, nil
        saved.slot = slot
        list = lists[slot]
        State.Refresh()
        autoScan()
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
-- (A3), keeps the slot, the other filters, the weapon type when the class
-- has it, the search and the sort, goes to page 1 and reads nothing. All
-- classes is kept between visits and sessions, any other choice as the
-- character's own.
function State.SelectClass(value)
    local was = view.class == ALL_CLASSES and ALL_CLASSES or chosenClass()
    if value == nil or value == was then return end
    view.class, view.page = value, 1
    saved.class = value == ALL_CLASSES and "all" or "own"
    fitWeaponType()
    settle()
    notify()
end

-- The Search box's text. Typing narrows on the client and goes to page 1.
-- Its use asks the client for the names of the slot's items it has not
-- loaded (item data only, never the auction house's rows) and, with For
-- sale only, of the item variants the scan found; each only once (startSearch). They
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
    local searching = not away and view.forSaleOnly and view.search ~= ""
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
        unsure = {}
        settle()
        clampPage()
        notify()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, tell) else tell() end
end)

-- The scan control: a new scan of the current slot now, again when it was
-- scanned. The old result stays on screen until the new one ends.
function State.ScanAgain()
    if (scan and scan.slot == view.slot) or dialogOpen() then return end
    batch(function()
        scanSlot()
        notify()
    end)
end

-- The player selected the tab or came back to it: with Scan when shown on,
-- the slot is scanned unless it has a kept scan, and again when its scan
-- was stopped by leaving the tab (A6); with it off nothing is read.
function State.Enter()
    away, entered = false, true
    local stopped = stoppedScan
    stoppedScan = nil
    batch(function()
        if autoScan(stopped == view.slot) then notify() end
    end)
end

-- A choice of the funnel changed: page 1, the flyout closes when its tile
-- left the page; nothing is read from the auction house.
local function narrowed()
    view.page = 1
    settle()
    notify()
end

-- The funnel's Show choice (the Filter), kept between sessions.
function State.SetFilter(filter)
    if filter == view.filter then return end
    view.filter, saved.show = filter, filter
    narrowed()
end

-- For sale only: narrows to the appearances with a known price, from the
-- slot's scan or a check of this visit; kept between sessions. With a
-- search text, the names of the scan's item variants are asked for
-- (startSearch).
function State.SetForSaleOnly(on)
    on = on == true
    if on == view.forSaleOnly then return end
    view.forSaleOnly, saved.forSaleOnly = on, on
    startSearch()
    narrowed()
end

-- A Source entry (a source type, or OTHER_SOURCE) ticked or unticked.
function State.SetSource(key, on)
    if (not view.sourcesOff[key]) == (on == true) then return end
    view.sourcesOff[key] = (not on) or nil
    narrowed()
end

-- The sort ("default" for Collections order, "priceLow", "priceHigh"),
-- kept between sessions.
function State.SetSort(value)
    if value == view.sort or not isSort(value) then return end
    view.sort, saved.sort = value, value
    narrowed()
end

-- Scan when shown, kept between sessions. Turning it on starts no scan:
-- the next show of the tab or slot change does. The settings page is told
-- (TC.SettingChanged), as it is of the item tooltip's settings.
function State.SetScanWhenShown(on)
    on = on == true
    if on == saved.scanWhenShown then return end
    saved.scanWhenShown = on
    notify()
    if TC.SettingChanged then TC.SettingChanged("scanWhenShown") end
end

-- Scan when shown as saved (the settings page reads it).
function State.ScanWhenShown()
    return saved.scanWhenShown
end

-- The saved table (TransmogCheckerDB.browser), handed over once the client
-- has loaded it (TransmogChecker.lua, ADDON_LOADED): its values, malformed
-- ones as the defaults, become the view's, and each change is written into
-- it. The six values are Scan when shown, Show, For sale only, the sort,
-- the slot and the class.
function State.Bind(t)
    if type(t) ~= "table" then return end
    useSaved(t)
    view.filter, view.forSaleOnly, view.sort, view.page = t.show, t.forSaleOnly, t.sort, 1
    view.class = t.class == "all" and ALL_CLASSES or nil
    if view.slot ~= t.slot then view.slot, view.weaponType, list = t.slot, nil, lists[t.slot] end
    settle()
end

-- Whether the class is neutral: All classes or the character's own, the two
-- a visit can start on. Neither lights the mark, and Reset keeps either.
local function classNeutral()
    return view.class == nil or view.class == ALL_CLASSES or view.class == (ownClass())
end

-- Whether Reset filters would change nothing: Show Not collected (slice G),
-- For sale only off,
-- every Source entry ticked, a neutral class, all weapon types, no search
-- text and the sort Price: low to high.
local function filtersAtStart()
    return view.filter == DEFAULTS.show and view.forSaleOnly == DEFAULTS.forSaleOnly and not next(view.sourcesOff)
        and classNeutral() and view.weaponType == nil and view.search == ""
        and view.sort == DEFAULTS.sort
end

-- "Reset filters": every filter and the sort back to its default, page 1;
-- a single other class back to the character's own; reads nothing.
function State.ResetFilters()
    if filtersAtStart() then return end
    view.filter, view.forSaleOnly, view.sort, view.sourcesOff = DEFAULTS.show, DEFAULTS.forSaleOnly, DEFAULTS.sort, {}
    saved.show, saved.forSaleOnly, saved.sort = view.filter, view.forSaleOnly, view.sort
    if not classNeutral() then view.class, saved.class = nil, DEFAULTS.class end
    view.weaponType, view.search = nil, ""
    narrowed()
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
        if result.outcome ~= "could not check" then
            kept[id] = result
            local first = result.rows and result.rows[1]
            sessionPrices[id] = first and { copper = first.minPrice, at = result.at, slot = result.slot } or nil
        else
            noAnswer[id] = true
        end
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
-- search that failed or a dialog closed before an outcome reads nothing. A
-- completed purchase makes its appearance pending until it is collected
-- (TC-39).
function State.BuyFinished(outcome, variant)
    if outcome ~= "completed" and outcome ~= "failed" and outcome ~= "gone" then return end
    local appearance = variant and variant.appearance
    if not appearance then return end
    batch(function()
        if outcome == "completed" then
            bought[appearance.id], seen[appearance.id] = true, nil
            if tryPending() then
                settle()
                clampPage()
                notify()
            end
        end
        if variant.visit ~= visit or away or checking[appearance.id] then return end
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
    State.SetFilter("all")
end
local function showUnpriced()
    State.SetForSaleOnly(false)
end
local function clearSearch()
    State.SetSearch("")
end

-- A price as its coin parts, { amount, coin }, in gold, silver, copper
-- order. Parts that are zero are left out; on a tile, from 100 gold up the
-- copper part is too (spec 2.5). Zero is "0c".
local function coinLetter(coin)
    return coin == "gold" and L.COIN_GOLD or coin == "silver" and L.COIN_SILVER or L.COIN_COPPER
end
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
    for i, part in ipairs(parts) do words[i] = part.amount .. coinLetter(part.coin) end
    return table.concat(words, " ")
end

-- Ages read "just now" under one minute and "N min ago" after (A10):
-- "Checked just now", "Scanned 4 min ago".
-- The item tooltip's price line reads the same age without the verb.
function State.Age(at)
    local seconds = now() - at
    if seconds < 60 then return L.AGE_JUST_NOW end
    local minutes = math.floor(seconds / 60)
    return TC.Plural("AGE_MINUTES", minutes):format(minutes)
end
-- The age after its verb: scanned, else checked.
local function age(at, scanned)
    return (scanned and L.AGE_SCANNED or L.AGE_CHECKED):format(State.Age(at))
end

-- The item tooltip's price (slice D1): the lowest price the browser saw
-- this session for the appearance and when, or nil. It reads what scans and
-- checks kept, never the auction house.
function State.SessionPrice(appearanceID)
    local p = sessionPrices[appearanceID]
    if p then return p.copper, p.at end
end

-- What is pending for the appearance (TC-39): "bags", "bought" or nil, as
-- the last bag read and the purchases left it.
function State.Pending(appearanceID)
    return pending[appearanceID]
end

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
-- a check or the slot's scan. A row's name is nil while it has not loaded;
-- a found row carries its item's id, for the head's icon.
-- The foot's button is off while a check runs.
local function itemList()
    local appearance = view.open
    local id = appearance.id
    local run, result, know = checking[id], latest[id] or scanResult(id), known[id]
    local slot = TC.Slots[appearance.slot]
    local out = {
        appearance = appearance, collected = collected[id] == true, weapon = slot.weapon,
        typeText = L[slot.nameKey], rows = {}, foot = { button = L.CHECK_AGAIN, enabled = not run },
    }
    -- bought or in the bags, not collected (TC-39): in the place of Collected
    if pending[id] and not out.collected then out.pendingText = pendingTexts()[pending[id]] end
    if slot.weapon then
        -- a weapon's type is its weapon type (spec 2.6)
        for _, weapon in ipairs(weaponTypesOf(appearance.slot) or {}) do
            if weapon.category == appearance.category then
                out.typeText = weapon.name
                break
            end
        end
    else
        -- the armor type of any item, tradeable or not, as the client names it
        for _, item in ipairs(know and know.all or {}) do
            if item.subType then
                out.typeText = L.FLYOUT_TYPE_SUBTYPE:format(out.typeText, item.subType)
                break
            end
        end
    end
    if run then
        out.state, out.title, out.foot.age = "checking", L.FLYOUT_CHECKING_TITLE, L.FLYOUT_CHECKING_FOOT
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
        out.foot.age = age(result.at, result.scanned)
    end
    local itemsLeftOut = result.leftOut and TC.Plural("CHECK_LEFT_OUT", result.total):format(result.leftOut, result.total)
    if result.outcome == "found" then
        -- short enough for one line beside the icon (testpass 1)
        out.title = TC.Plural("FLYOUT_FOUND", #result.rows):format(#result.rows)
        -- every found row offers Buy when the client has the calls for it
        -- (TC_Buy); it is off while a check or a scan runs
        local buyable = TC.Buy ~= nil and TC.Buy.Available()
        for i, row in ipairs(result.rows) do
            local parts = money(row.minPrice)
            local name, quality = row.name, row.quality
            if not name then name, quality = itemOwn(row.itemKey.itemID, know) end
            out.rows[i] = { name = variantName(row.itemKey) or name, quality = quality, itemID = row.itemKey.itemID,
                forSale = "x" .. row.totalQuantity, money = parts, price = moneyText(parts) }
            if buyable then
                out.rows[i].buy = { enabled = not readsRunning(), variant = { itemKey = row.itemKey,
                    name = out.rows[i].name, quality = quality, minPrice = row.minPrice,
                    bindType = itemBind(row.itemKey.itemID, know), appearance = appearance, visit = visit } }
            end
        end
        if (result.leftOut or 0) > 0 then out.foot.note = itemsLeftOut end
    elseif result.outcome == "not for sale" then
        out.title, out.text = L.NOT_FOR_SALE_NOW, L.NOT_ON_AUCTION_HOUSE
        itemRows(out, result.items or (know and know.items))
    elseif result.outcome == "cannot be sold" then
        out.title, out.text = L.NOT_FOR_SALE_NOW, L.CANNOT_BE_SOLD
    elseif result.queryFailed then
        out.title = L.STATUS_FAILED
    elseif result.noItems then
        out.title = L.ITEMS_UNREADABLE
    else
        out.title = itemsLeftOut
    end
    return out
end

-- The bottom row's scan control (spec 2.8, slice B): one button, Scan
-- slot, that scans the slot now (off while its scan runs), and its
-- sub-line: not scanned yet, scanning with the progress value, the failure,
-- or the scan's age.
local function statusLine(answer)
    local slot = view.slot
    answer.statusButton, answer.statusAction, answer.statusEnabled = L.SCAN_SLOT, State.ScanAgain, true
    -- nothing known is drawn as advice, not state (visual pass, board 9)
    answer.statusHint = false
    if scan and scan.slot == slot then
        answer.status = L.SCANNING_SLOT:format(L[TC.Slots[slot].nameKey])
        answer.progress = math.min(scan.pages / scan.expected, MAX_PROGRESS)
        answer.statusEnabled = false
    elseif failures[slot] then
        answer.status = L.STATUS_FAILED
    elseif scans[slot] then
        answer.status = age(scans[slot].at, true)
    else
        answer.status, answer.statusHint = L.NOT_SCANNED, true
    end
end

-- The slot row: the 14 slots in their groups, the chosen one marked.
local function slotRow()
    local row = {}
    for i, slot in ipairs(TC.Slots) do
        row[i] = { key = slot.key, name = L[slot.nameKey], group = slot.group, art = slot.art, selected = slot.key == view.slot }
    end
    return row
end

-- The weapon type dropdown of a weapon slot: its text and its entries, "All
-- weapon types" first (value nil), then the chosen class's weapon types in
-- the slot; nil while they are not learnt or when the class has none.
local function weaponDropdown()
    local types = weaponTypesOf(view.slot, chosenClass())
    if not (types and types[1]) then return nil end
    local entries = { { name = L.ALL_WEAPON_TYPES, selected = view.weaponType == nil } }
    local text = L.ALL_WEAPON_TYPES
    for _, weapon in ipairs(types) do
        local selected = weapon.category == view.weaponType
        entries[#entries + 1] = { name = weapon.name, value = weapon.category, selected = selected }
        if selected then text = weapon.name end
    end
    return { text = text, entries = entries }
end

-- The funnel's Show entries: the Filter's values, the chosen one marked;
-- while an appearance of any slot is pending, Bought, not collected too.
local function showEntries(filter)
    local entries = {}
    for i, show in ipairs(State.FILTERS) do
        entries[i] = { name = L[show.nameKey], value = show.value, selected = show.value == filter }
    end
    if next(pending) then
        entries[#entries + 1] = { name = L.SHOW_PENDING, value = PENDING_FILTER, selected = filter == PENDING_FILTER }
    end
    return entries
end

-- The funnel's Source entries, each { name, value, selected }: ticked
-- unless the player unticked it.
local function sourceEntriesOf()
    local entries = {}
    for i, entry in ipairs(sourceTypes()) do
        entries[i] = { name = entry.name, value = entry.key, selected = not view.sourcesOff[entry.key] }
    end
    return entries
end

-- The Source menu's entries (slice E, E4), as sourceEntriesOf: an entry
-- only when an appearance of the slot's list (the class and weapon type
-- chosen, before Show, For sale only, Source and Search) has a source of
-- its type, or when it is unticked, so it can be ticked again. Every entry
-- while the list is not read or a source type of it is not known yet. The
-- funnel asks at each opening: one GetAppearanceSources call per
-- appearance whose types sourceKeys has not kept (kept for the visit; an
-- unknown one until the next Refresh or item names), none after.
function State.SourceEntries()
    local entries = sourceEntriesOf()
    if not list or partial[view.slot] then return entries end
    local has = {}
    for _, appearance in ipairs(typed()) do
        for key in pairs(sourceKeys(appearance)) do has[key] = true end
        if unsure[appearance.id] then return entries end
    end
    local out = {}
    for _, entry in ipairs(entries) do
        if has[entry.value] or not entry.selected then out[#out + 1] = entry end
    end
    return out
end

-- The funnel's sort entries, the chosen one marked.
local function sortEntries()
    local entries = {}
    for i, sort in ipairs(SORTS) do entries[i] = { name = L[sort.nameKey], value = sort.value, selected = sort.value == view.sort } end
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
    local answer = { text = L.ALL_CLASSES,
        entries = { { name = L.ALL_CLASSES, value = ALL_CLASSES, selected = chosen == ALL_CLASSES } } }
    local ids = C_SpecializationInfo and C_SpecializationInfo.GetAllClassIDs and C_SpecializationInfo.GetAllClassIDs()
    if type(ids) ~= "table" or not ids[1] then ids = { own } end
    for _, classID in ipairs(ids) do
        local name, file = classInfo(classID)
        if name then
            local selected = classID == chosen
            answer.entries[#answer.entries + 1] = { name = classID == own and L.CLASS_THIS_CHARACTER:format(name) or name,
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
-- when it has them and the chosen language is the client's; the locale
-- table's texts are the board's wording, used without them or under
-- another language (their wording on Forever is unverified): TC.ClientText.
local function fontColour(name, r, g, b)
    local c = _G[name]
    if type(c) == "table" and c.GetRGB then return { c:GetRGB() } end
    return { r, g, b }
end

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
    if not name then return TC.ClientText("RETRIEVING_ITEM_INFO", "RETRIEVING_ITEM"), c.red end
    return name, qualityColour(quality, c.white)
end

-- A rule of the tooltip that raises is reported once (by rule name) and
-- answers nil, so only its line is left out.
local failedRules = {}
local function rule(name, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    if not failedRules[name] then
        failedRules[name] = true
        report(a)
    end
end

-- The client's name of a source's source type (TRANSMOG_SOURCE_n, a
-- 1-based index), else our own (TC.SOURCE_TYPES), else "".
local function typeText(source)
    local n = source.sourceType
    local own = TC.SOURCE_TYPES and TC.SOURCE_TYPES[n]
    return n and TC.ClientText("TRANSMOG_SOURCE_" .. n, own and own.nameKey) or ""
end

-- Source type 6 is profession (recorded in game on tailored items, TC-35).
local PROFESSION_SOURCE = 6
local MAX_DROPS = 6

-- A boss drop's drops (C_TransmogCollection.GetAppearanceSourceDrops,
-- TransmogItemsDocumentation.lua:180-195, 1161-1171: names only), those
-- with an encounter or instance name, in the client's order; nil for
-- another source type or without any.
local function drops(source)
    local TCol = C_TransmogCollection
    if source.sourceType ~= (TRANSMOG_SOURCE_BOSS_DROP or 1) or not (TCol and TCol.GetAppearanceSourceDrops) then return nil end
    local list = {}
    for _, drop in ipairs(type(source.sourceID) == "number" and TCol.GetAppearanceSourceDrops(source.sourceID) or {}) do
        if type(drop) == "table" and (nonEmpty(drop.encounter) or nonEmpty(drop.instance)) then list[#list + 1] = drop end
    end
    return list[1] and list or nil
end

-- A drop's "<encounter> (<instance>)" (CollectionsUtil.lua:232) and its
-- difficulties joined as Collections joins them (:298-306), or nil.
local function dropPlace(drop)
    local encounter, instance = nonEmpty(drop.encounter), nonEmpty(drop.instance)
    local place = encounter and instance
        and TC.ClientText("WARDROBE_TOOLTIP_ENCOUNTER_SOURCE", "DROP_PLACE"):format(encounter, instance) or encounter or instance
    local texts = {}
    for _, text in ipairs(type(drop.difficulties) == "table" and drop.difficulties or {}) do
        if nonEmpty(text) then texts[#texts + 1] = text end
    end
    local difficulties = texts[1] and table.concat(texts, TC.ClientText("PLAYER_LIST_DELIMITER", "LIST_DELIMITER")) or nil
    return place, difficulties
end

-- The head source's source lines, as text: one drop as Collections words
-- it (CollectionsUtil.lua:312-318); several drops each on a line under
-- "Boss drop:", at most 6 and then "and N more"; a profession named where
-- the item's type settles it; else the source type.
local function sourceLines(source, maxDrops)
    local list = rule("drops", drops, source)
    if list and not list[2] then
        local place, difficulties = dropPlace(list[1])
        if difficulties then
            return { TC.ClientText("WARDROBE_TOOLTIP_BOSS_DROP_FORMAT_WITH_DIFFICULTIES", "DROP_WITH_DIFFICULTIES"):format(place, difficulties) }
        end
        return { TC.ClientText("WARDROBE_TOOLTIP_BOSS_DROP_FORMAT", "DROP"):format(place) }
    elseif list then
        local lines = { L.BOSS_DROP_HEADER }
        for i, drop in ipairs(list) do
            if i > maxDrops then
                lines[#lines + 1] = TC.Plural("MORE_DROPS", #list - maxDrops):format(#list - maxDrops)
                break
            end
            local place, difficulties = dropPlace(drop)
            lines[#lines + 1] = difficulties and ("%s (%s)"):format(place, difficulties) or place
        end
        return lines
    end
    local text = typeText(source)
    local profession = source.sourceType == PROFESSION_SOURCE and rule("profession", TC.Appearances.Profession, source.itemID)
    if profession then return { L.SOURCE_WITH_PROFESSION:format(text, profession) } end
    return { text ~= "" and text or nil }
end

-- A source's text in the list of other items: "Collected" in green, or in
-- white the short form of its source (GetAppearanceSourceTextAndColor,
-- CollectionsUtil.lua:156-170): one drop's encounter, "<first> +N" for
-- several, the inferred profession, else the source type.
local function sourceText(source, c)
    if source.isCollected then return TC.ClientText("TRANSMOG_COLLECTED", "COLLECTED"), c.green end
    local list = rule("drops", drops, source)
    if list then
        local first = nonEmpty(list[1].encounter) or list[1].instance
        return list[2] and ("%s +%d"):format(first, #list - 1) or first, c.white
    end
    local profession = source.sourceType == PROFESSION_SOURCE and rule("profession", TC.Appearances.Profession, source.itemID)
    return profession or typeText(source), c.white
end

-- A source's short text, as the list of other items words it: the item
-- tooltip's rows (TC-15) use it, without its colour.
function State.SourceText(source)
    return (sourceText(source, { green = true, white = true }))
end

-- A source in one line, for the item tooltip's status line: its source
-- lines when they are one line (a drop in full, the profession, the source
-- type), else the short text (several drops); nil without any.
function State.SourceLine(source)
    local lines = sourceLines(source, MAX_DROPS)
    if lines[2] then return State.SourceText(source) end
    return lines[1]
end

local function otherItemsText()
    return TC.ClientText("WARDROBE_OTHER_ITEMS", "OTHER_ITEMS_HEADER")
end
-- "and N more items"
local function moreItems(n)
    return TC.Plural("MORE_ITEMS", n):format(n)
end

-- The words the item tooltip shares with the browser (slice D1): the Show
-- filter's "Collected" and "Not collected", the list's header and its
-- "and N more items" (a function of N) and the pending sentences.
function State.Wording()
    return { collected = TC.ClientText("TRANSMOG_COLLECTED", "COLLECTED"), notCollected = L.NOT_COLLECTED,
        otherItems = otherItemsText(), moreItems = moreItems, pending = pendingTexts() }
end

-- The source the tooltip heads with (CollectionWardrobeUtil.
-- GetDefaultSourceIndex, CollectionsUtil.lua:3-39), else the first.
local function headIndex(sources)
    local pick = CollectionWardrobeUtil and CollectionWardrobeUtil.GetDefaultSourceIndex
    local ok, index = false, nil
    if pick then ok, index = pcall(pick, sources) end
    return ok and sources[index] and index or 1
end

-- C_Item.GetItemInfo (ItemDocumentation.lua:626-656) of an item whose data
-- is in, else nothing: it never asks the client to load it.
local function loadedInfo(itemID)
    if not (itemID and C_Item and C_Item.GetItemInfo and TC.Appearances.ItemName(itemID)) then return nil end
    return C_Item.GetItemInfo(itemID)
end

-- The locale key of each equip location's name (the client's INVTYPE_
-- globals, as the game's item tooltip names the slot).
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { nameKey = "SLOT_HEAD" }, INVTYPE_SHOULDER = { nameKey = "SLOT_SHOULDER" },
    INVTYPE_BODY = { nameKey = "SLOT_SHIRT" }, INVTYPE_CHEST = { nameKey = "SLOT_CHEST" },
    INVTYPE_ROBE = { nameKey = "SLOT_CHEST" }, INVTYPE_WAIST = { nameKey = "SLOT_WAIST" },
    INVTYPE_LEGS = { nameKey = "SLOT_LEGS" }, INVTYPE_FEET = { nameKey = "SLOT_FEET" },
    INVTYPE_WRIST = { nameKey = "SLOT_WRIST" }, INVTYPE_HAND = { nameKey = "SLOT_HANDS" },
    INVTYPE_CLOAK = { nameKey = "SLOT_BACK" }, INVTYPE_TABARD = { nameKey = "SLOT_TABARD" },
    INVTYPE_WEAPON = { nameKey = "SLOT_ONE_HAND" }, INVTYPE_2HWEAPON = { nameKey = "SLOT_TWO_HAND" },
    INVTYPE_WEAPONMAINHAND = { nameKey = "SLOT_MAIN_HAND" }, INVTYPE_WEAPONOFFHAND = { nameKey = "SLOT_OFF_HAND" },
    INVTYPE_SHIELD = { nameKey = "SLOT_OFF_HAND" }, INVTYPE_HOLDABLE = { nameKey = "SLOT_HELD_IN_OFF_HAND" },
    INVTYPE_RANGED = { nameKey = "SLOT_RANGED" }, INVTYPE_RANGEDRIGHT = { nameKey = "SLOT_RANGED" },
}

-- "Requires level N" (above 1) and "<subtype>, <slot>" (the slot is the
-- client's INVTYPE_ name of the equip location, TC.ClientText), what is
-- loaded of them, joined by a middle dot; nil with nothing loaded.
local function itemLine(itemID)
    local _, _, _, _, minLevel, _, subType, _, equipLoc = loadedInfo(itemID)
    local parts = {}
    if type(minLevel) == "number" and minLevel > 1 then parts[1] = L.REQUIRES_LEVEL:format(minLevel) end
    local own = nonEmpty(equipLoc) and EQUIP_SLOTS[equipLoc]
    local kind, slot = nonEmpty(subType), nonEmpty(equipLoc) and TC.ClientText(equipLoc, own and own.nameKey)
    parts[#parts + 1] = kind and slot and (kind .. ", " .. slot) or kind or slot
    return parts[1] and table.concat(parts, " \194\183 ") or nil
end

-- How the item binds, for the two kinds that matter for collecting (bind
-- type 14th, Enum.ItemBind, ItemConstantsDocumentation.lua:249-261).
local function bindLine(itemID)
    local bindType = select(14, loadedInfo(itemID))
    local binds = Enum and Enum.ItemBind
    if bindType ~= nil and bindType == (binds and binds.OnEquip or 2) then
        return L.BIND_ON_EQUIP_COLLECT
    elseif bindType ~= nil and bindType == (binds and binds.OnAcquire or 1) then
        return L.BIND_ON_PICKUP
    end
end

-- "Part of set: <name> (<label>)" for the first transmog set holding the
-- source (C_TransmogSets.GetSetsContainingSourceID, GetSetInfo,
-- TransmogSetsDocumentation.lua:167-181, 215-229, 520-540), or nil.
local function setLine(sourceID)
    local Sets = C_TransmogSets
    if not (type(sourceID) == "number" and Sets and Sets.GetSetsContainingSourceID and Sets.GetSetInfo) then return nil end
    local ids = Sets.GetSetsContainingSourceID(sourceID)
    local setID = type(ids) == "table" and ids[1]
    local info = type(setID) == "number" and Sets.GetSetInfo(setID)
    local name = type(info) == "table" and nonEmpty(info.name)
    if not name then return nil end
    local label = nonEmpty(info.label)
    if label and label ~= name then return L.SET_PART_LABEL:format(name, label) end
    return L.SET_PART:format(name)
end

-- The holiday the source requires (GetSourceRequiredHoliday,
-- TransmogItemsDocumentation.lua:647-661), in Collections' wording
-- (CollectionsUtil.lua:373-377), or nil.
local function holidayLine(sourceID)
    local TCol = C_TransmogCollection
    local name = type(sourceID) == "number" and TCol and TCol.GetSourceRequiredHoliday
        and nonEmpty(TCol.GetSourceRequiredHoliday(sourceID))
    return name and TC.ClientText("TRANSMOG_APPEARANCE_USABLE_HOLIDAY", "HOLIDAY_ONLY"):format(name) or nil
end

-- The tooltip never has more lines than this.
local MAX_LINES = 20

-- The lines about the head source, after its name: its source in full when
-- not collected; the item's level and type; how it binds; its set; the
-- holiday it requires; the client's use error, in red. Each rule is
-- protected: one that raises leaves its own line out.
local function headLines(lines, source, c, maxDrops)
    if not source.isCollected then
        for _, text in ipairs(rule("source", sourceLines, source, maxDrops) or {}) do lines[#lines + 1] = { text = text, color = c.white } end
    end
    local text = rule("item", itemLine, source.itemID)
    if text then lines[#lines + 1] = { text = text, color = c.grey } end
    text = rule("bind", bindLine, source.itemID)
    if text then lines[#lines + 1] = { text = text, color = c.white, wrap = true } end
    text = rule("set", setLine, source.sourceID)
    if text then lines[#lines + 1] = { text = text, color = c.normal } end
    text = rule("holiday", holidayLine, source.sourceID)
    if text then lines[#lines + 1] = { text = text, color = c.lightBlue } end
    text = nonEmpty(source.useError)
    if text then lines[#lines + 1] = { text = text, color = c.red, wrap = true } end
end

-- The tile tooltip's lines for an appearance, each { text, color, right,
-- rightColor, money, wrap }; wrap marks the sentences (how it binds, the
-- pending sentence, the use error, the hints), which wrap so the short lines
-- set the tooltip's width (testpass F6). They are the head item's name and
-- the lines about it (headLines); then, with more than one item, "Other items using this
-- appearance:" and every item with its short source or "Collected",
-- collected ones included (Collections hides the list for a collected
-- appearance, CollectionsUtil.lua:330), cut with "and N more items" so the
-- tooltip has at most 20 lines; no "Tab to cycle" line. Then, when the
-- browser keeps a result for the tile, the lowest price or "Not for sale"
-- and its age, and the click hint. It reads the game's appearance and item
-- data, never the auction house; it asks for the data of this appearance's
-- items whose names are not loaded, once a visit (LoadNames).
function State.TileTooltip(appearance)
    local c = { white = fontColour("HIGHLIGHT_FONT_COLOR", 1, 1, 1), normal = fontColour("NORMAL_FONT_COLOR", 1, 0.82, 0),
        green = fontColour("GREEN_FONT_COLOR", 0.1, 1, 0.1), red = fontColour("RED_FONT_COLOR", 1, 0.125, 0.125),
        grey = fontColour("GRAY_FONT_COLOR", 0.5, 0.5, 0.5), lightBlue = fontColour("LIGHTBLUE_FONT_COLOR", 0.53, 0.67, 1) }
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
        headLines(lines, sources[head], c, MAX_DROPS)
    end
    local tail = {}
    -- bought or in the bags, not collected (TC-39): how to collect it
    local waiting = pending[appearance.id]
    if waiting and not collected[appearance.id] then
        tail[1], tail[2] = { text = " " }, { text = pendingTexts()[waiting], color = c.white, wrap = true }
    end
    local result = forSaleResult(appearance.id)
    if result then
        tail[#tail + 1] = { text = " " }
        local first = result.rows[1]
        if first then
            local parts = money(first.minPrice)
            tail[#tail + 1] = { text = L.LOWEST_PRICE, color = c.normal, right = moneyText(parts), money = parts, rightColor = c.white }
        else
            tail[#tail + 1] = { text = L.LOWEST_PRICE, color = c.normal, right = L.NOT_FOR_SALE, rightColor = c.grey }
        end
        if result.at then tail[#tail + 1] = { text = age(result.at, result.scanned), color = c.grey } end
        tail[#tail + 1] = { text = first and L.TIP_SEE_ITEMS or L.TIP_DETAILS, color = c.grey, wrap = true }
    elseif checking[appearance.id] then
        -- reading: no hint
    elseif noAnswer[appearance.id] then
        tail[#tail + 1] = { text = L.TIP_NO_ANSWER, color = c.grey, wrap = true }
        tail[#tail + 1] = { text = L.TIP_CHECK_AGAIN, color = c.grey, wrap = true }
    else
        tail[#tail + 1] = { text = L.TIP_CHECK, color = c.grey, wrap = true }
    end
    -- the rows the list has room for, its blank line and header aside
    local room = MAX_LINES - #lines - #tail - 2
    -- no room even for the notice: the head shows fewer drops
    local maxDrops = MAX_DROPS
    while #sources > 1 and room < 1 and head and maxDrops > 1 do
        maxDrops = maxDrops - 1
        lines = { lines[1] }
        headLines(lines, sources[head], c, maxDrops)
        room = MAX_LINES - #lines - #tail - 2
    end
    if #sources > 1 and room > 0 then
        lines[#lines + 1] = { text = " " }
        lines[#lines + 1] = { text = otherItemsText(), color = c.normal }
        local shown = #sources > room and room - 1 or #sources
        for i = 1, shown do
            local source = sources[i]
            local name, colour = sourceName(source, c)
            local text, textColour = sourceText(source, c)
            lines[#lines + 1] = { text = name, color = colour, right = text, rightColor = textColour }
        end
        if shown < #sources then lines[#lines + 1] = { text = moreItems(#sources - shown), color = c.grey } end
    end
    for _, line in ipairs(tail) do lines[#lines + 1] = line end
    return lines
end


-- Every Source entry ticked again (an empty state's button).
local function allSources()
    view.sourcesOff = {}
    narrowed()
end

-- What to draw now. Without a list there are no tiles; once a read of the
-- slot answered nothing or raised, the empty state says so.
function State.View()
    local slot = TC.Slots[view.slot]
    -- filter: the Show choice's name
    local filterName = L.SHOW_PENDING
    for _, show in ipairs(State.FILTERS) do
        if show.value == view.filter then filterName = L[show.nameKey] end
    end
    local answer = {
        filter = filterName, page = view.page, slots = slotRow(),
        weaponTypes = weaponDropdown(), classes = classDropdown(), search = view.search,
        filters = showEntries(view.filter), forSaleOnly = view.forSaleOnly, sources = sourceEntriesOf(),
        sorts = sortEntries(), scanWhenShown = saved.scanWhenShown, filtersChanged = not filtersAtStart(),
        tiles = {}, count = "", pageText = "", paging = false, previousEnabled = false, nextEnabled = false,
    }
    statusLine(answer)
    if not list then
        if noneFound[view.slot] then answer.empty = { title = L.EMPTY_NO_APPEARANCES_TITLE, text = L.EMPTY_NO_APPEARANCES } end
        return answer
    end
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
            -- bought or in the bags, not collected (TC-39); never with collected
            pending = (pending[appearance.id] and not collected[appearance.id]) and true or nil,
        }
        local result = forSaleResult(appearance.id)
        if result and result.rows[1] then
            tile.strip, tile.money = "price", money(result.rows[1].minPrice, true)
            tile.price = moneyText(tile.money)
        elseif result then
            tile.strip, tile.price = "not for sale", L.NOT_FOR_SALE
        elseif checking[appearance.id] then
            tile.strip = "bar"
        elseif noAnswer[appearance.id] then
            tile.strip, tile.price = "no answer", L.NO_ANSWER
        end
        answer.tiles[#answer.tiles + 1] = tile
    end
    -- with For sale only, while the first scan of the slot runs, the tiles
    -- appear as their prices arrive, placeholders fill the page, each framed
    -- like the slot's first listed appearance, and no empty state is
    -- answered, whatever the other filters
    local scanning = view.forSaleOnly and scan ~= nil and scan.slot == view.slot and not scans[view.slot]
    if scanning then
        while #answer.tiles < size do
            answer.tiles[#answer.tiles + 1] = { placeholder = true, strip = "bar", cameraAppearance = list[1] }
        end
    end
    if view.open then answer.list = itemList() end
    answer.count = countText(appearances)
    answer.pageText = L.PAGE:format(view.page, math.max(pages, 1))
    -- the widest form of the page text for this count, so its room never changes
    answer.pageTextWidest = L.PAGE:format(math.max(pages, 1), math.max(pages, 1))
    answer.paging = pages > 1
    answer.previousEnabled = view.page > 1
    answer.nextEnabled = view.page < pages
    -- the slot's name as the slot row gives it, never lowercased
    local slotName = L[slot.nameKey]
    local class = chosenClass()
    local className = class and classInfo(class)
    -- an empty state's sentence: the one naming the class where a class is chosen
    local function forSlot(text, withClass)
        if className then return withClass:format(slotName, className) end
        return text:format(slotName)
    end
    if scanning or #appearances > 0 then
        -- tiles, or placeholders while the scan runs
    elseif not typed()[1] then
        -- the class filter or the weapon type leaves nothing of the slot (spec 2.9)
        answer.empty = { title = L.NO_MATCHES, text = forSlot(L.EMPTY_NO_SLOT, L.EMPTY_NO_SLOT_CLASS) }
    elseif not shown("show")[1] then
        -- The list is never empty (an empty read keeps no list), so past
        -- the weapon type Show is the first filter that can leave nothing.
        local text = view.filter == "collected" and forSlot(L.EMPTY_NONE_COLLECTED, L.EMPTY_NONE_COLLECTED_CLASS)
            or view.filter == PENDING_FILTER and forSlot(L.EMPTY_NONE_PENDING, L.EMPTY_NONE_PENDING_CLASS)
            or forSlot(L.EMPTY_ALL_COLLECTED, L.EMPTY_ALL_COLLECTED_CLASS)
        answer.empty = { title = L.NO_MATCHES, text = text, button = L.SHOW_ALL_BUTTON, action = showAll }
    elseif not shown("source")[1] then
        answer.empty = { title = L.NO_MATCHES, text = L.EMPTY_NO_SOURCE:format(slotName),
            button = L.ALL_SOURCES, action = allSources }
    elseif not shown("sale")[1] and not scans[view.slot] and failures[view.slot] then
        -- For sale only after the slot's scan failed: as the status line, scan again
        answer.empty = { title = L.STATUS_FAILED, text = L.EMPTY_SCAN_AGAIN:format(slotName),
            button = L.SCAN_SLOT, action = State.ScanAgain }
    elseif not shown("sale")[1] and not scans[view.slot] then
        -- For sale only on a slot with no kept scan: scan it
        answer.empty = { title = L.NOT_SCANNED, text = L.EMPTY_SCAN:format(slotName),
            button = L.SCAN_SLOT, action = State.ScanAgain }
    elseif not shown("sale")[1] then
        -- only a kept scan says nothing is for sale
        answer.empty = { title = L.EMPTY_NOTHING_FOR_SALE_TITLE, text = L.EMPTY_NOTHING_FOR_SALE:format(slotName),
            button = L.SHOW_ALL_APPEARANCES, action = showUnpriced }
    else
        -- only the search leaves nothing (spec 2.9)
        answer.empty = { title = L.NO_MATCHES, text = L.EMPTY_NO_SEARCH:format(slotName, view.search),
            button = L.CLEAR_SEARCH, action = clearSearch }
    end
    -- an empty state and tiles are never drawn together
    if answer.empty then answer.tiles = {} end
    return answer
end
