-- The scan: one read of the auction house for a single slot (spec section
-- 3, "What a scan reads, and when"). It hides the filter entries of the
-- slot, reading every page through the query queue, finding each row's
-- appearance, grouping the rows by appearance with the lowest price, and the
-- page seam (spec 4.5).
TC = TC or {}
TC.Scan = {}

local Scan = TC.Scan

-- The queue stops a scan here; one cut off is a failure.
local MAX_PAGES = 60

-- The scan filter entries of a slot, from TC.Slots (spec 4.3): every entry
-- names its subclass, or the server returns the whole class (spec 4.5). A
-- weapon slot's entries cover every weapon type any class has in the slot
-- (TC-38), one per category, from the slot table's entry of that category;
-- a category the table has none for is left out. types: the slot's
-- WeaponTypes for every class, else the fixed split. Enum values are read when a
-- scan runs; nil when the slot is unknown or the client lacks one of its
-- members, which fails that slot's scan only.
local function filterEntries(slot, types)
    local E, entry = Enum, TC.Slots[slot]
    if not (entry and E and E.ItemClass and E.InventoryType) then return nil end
    local filters = entry.filters
    if entry.weapon then
        filters = {}
        for _, weapon in ipairs(types or TC.Appearances.WeaponTypes(slot, false)) do
            filters[#filters + 1] = TC.Appearances.CategoryFilter(weapon.category)
        end
        if not filters[1] then return nil end
    end
    local entries = {}
    for _, filter in ipairs(filters) do
        local subclasses = filter[1] == "Armor" and E.ItemArmorSubclass or E.ItemWeaponSubclass
        local built = { classID = E.ItemClass[filter[1]], subClassID = subclasses and subclasses[filter[2]],
            inventoryType = filter[3] and E.InventoryType[filter[3]] }
        if not (built.classID and built.subClassID and (built.inventoryType or not filter[3])) then return nil end
        entries[#entries + 1] = built
    end
    return entries
end

-- A sort list with one entry is ignored; the pair comes back cheapest first
-- (spec 4.2 and 4.5).
local function priceThenName()
    local Sort = Enum and Enum.AuctionHouseSortOrder
    if not (Sort and Sort.Price and Sort.Name) then return nil end
    return { { sortOrder = Sort.Price, reverseSort = false }, { sortOrder = Sort.Name, reverseSort = false } }
end

local function keyText(key)
    return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
end

-- a row's item key as text, nil when the row has none
local function rowText(row)
    local key = row.itemKey
    return type(key) == "table" and key.itemID and keyText(key) or nil
end

local function cheaper(a, b)
    if a.minPrice ~= b.minPrice then return a.minPrice < b.minPrice end
    return keyText(a.itemKey) < keyText(b.itemKey)
end

-- Adds the rows from `from` on to the scan's grouped result: { [appearanceID]
-- = { id, rows, minPrice } }, rows being item variants. The result persists
-- across pages, so a page costs its new rows only. A row repeated at a page
-- seam is one variant; the lowest price is found by comparing, not by
-- position, and a group's first row is its cheapest so far (the final order
-- is computed once, when the scan ends, spec 4.5). It reads no item data: a
-- name is read where the item list is drawn. state.appearanceOf caches each
-- item's appearance (false: none).
local function group(state, rows, from)
    local found, variants, appearanceOf = state.found, state.variants, state.appearanceOf
    for i = from, #rows do
        local row = rows[i]
        local key = row.itemKey
        local itemID = type(key) == "table" and key.itemID
        -- a row without a buyout price is not for sale here
        if itemID and type(row.minPrice) == "number" and row.minPrice > 0 then
            if appearanceOf[itemID] == nil then
                -- an item's appearance and source, or nothing (measured in game)
                appearanceOf[itemID] = C_TransmogCollection.GetItemInfo(itemID) or false
            end
            local id = appearanceOf[itemID]
            local text = keyText(key)
            local variant = variants[text]
            if id and not variant then
                variant = { itemKey = key, minPrice = row.minPrice, totalQuantity = row.totalQuantity }
                variants[text] = variant
                local g = found[id]
                if not g then
                    g = { id = id, rows = {}, minPrice = row.minPrice }
                    found[id] = g
                end
                g.rows[#g.rows + 1] = variant
                variant.group = g
            elseif variant and row.minPrice < variant.minPrice then
                variant.minPrice, variant.totalQuantity = row.minPrice, row.totalQuantity
            end
            local g = variant and variant.group
            if g and variant.minPrice < g.rows[1].minPrice then
                for j, v in ipairs(g.rows) do
                    if v == variant then
                        g.rows[1], g.rows[j] = variant, g.rows[1]
                        break
                    end
                end
            end
            if g then g.minPrice = g.rows[1].minPrice end
        end
    end
end

-- The final order, once: each group's item variants cheapest first.
local function order(found)
    for _, g in pairs(found) do
        for _, v in ipairs(g.rows) do v.group = nil end
        table.sort(g.rows, cheaper)
        g.minPrice = g.rows[1].minPrice
    end
end

-- Runs one scan of the slot. onProgress(found, pages) follows each page with
-- the rows so far grouped by appearance (one table that grows) and the
-- pages read. done is called once: done({ appearances = found, pages = n })
-- when every page was read, or done(nil, reason) when a query failed, the
-- scan was cut off at 60 pages, or a call it needs is missing. Neither is
-- called after the queue's CancelAll. types: a weapon slot's WeaponTypes for
-- every class, when the caller has them.
function Scan.Run(slot, onProgress, done, types)
    local entries, sorts = filterEntries(slot, types), priceThenName()
    if not (C_TransmogCollection and C_TransmogCollection.GetItemInfo) then
        return done(nil, "C_TransmogCollection.GetItemInfo is missing")
    elseif not (entries and sorts) then
        return done(nil, "an Enum value of the scan filter is missing")
    end
    local state = { found = {}, variants = {}, appearanceOf = {} }
    local seen, lastText, read = 0, nil, 0
    -- groups the rows not yet grouped: those after the ones seen, or all of
    -- them when the client replaced its list instead of adding to it
    local function take(rows)
        local from = seen + 1
        if seen > 0 and not (rows[seen] and rowText(rows[seen]) == lastText) then from = 1 end
        group(state, rows, from)
        seen = #rows
        lastText = seen > 0 and rowText(rows[seen]) or nil
    end
    -- the server's "uncollected only" filter is not sent (spec A2)
    TC.AuctionQueue.Browse({ searchString = "", sorts = sorts, filters = {}, itemClassFilters = entries }, MAX_PAGES, {
        page = function(rows, pages)
            read = pages
            take(rows)
            onProgress(state.found, pages)
        end,
        done = function(rows, cut)
            if cut then return done(nil, ("the scan was cut off at %d pages"):format(MAX_PAGES)) end
            take(rows)
            order(state.found)
            done({ appearances = state.found, pages = read })
        end,
        failed = function(reason)
            done(nil, reason)
        end,
    })
end
