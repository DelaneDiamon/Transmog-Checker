-- The check: one lookup of the auction house for the items that carry one
-- appearance (spec section 3, "What a check reads, and when"). It hides which
-- items can be traded, one name browse per distinct name through the query
-- queue, keeping only the rows of the appearance's items, and the limits of
-- Assumption A5.
TC = TC or {}
TC.Check = {}

local Check = TC.Check

local function enum(name, key, fallback)
    local values = Enum and Enum[name]
    return values and values[key] or fallback
end

-- Enum.ItemBind (ItemConstantsDocumentation.lua:249-261). Only 0, 1 and 2
-- were seen in game; quest items (4) are skipped as the spec says.
local BIND_ON_PICKUP = enum("ItemBind", "OnAcquire", 1)
local BIND_QUEST = enum("ItemBind", "Quest", 4)
-- A sort list with one entry is ignored; the pair comes back cheapest first
-- (spec 4.2 and 4.5).
local PRICE_THEN_NAME = {
    { sortOrder = enum("AuctionHouseSortOrder", "Price", 0), reverseSort = false },
    { sortOrder = enum("AuctionHouseSortOrder", "Name", 1), reverseSort = false },
}
-- Spec Assumption A5.
local MAX_NAMES, MAX_PAGES = 10, 5

-- Raised by CancelAll; a check whose generation is older stops.
local generation = 0

-- An item whose data the client answered as failed to load is not on this
-- server (TC-32): it can never be for sale, so it is neither looked up nor
-- counted. An item whose data never answered still counts as tradeable.
local function tradeable(item)
    if not item.loaded then return not item.failed end
    return item.bindType ~= BIND_ON_PICKUP and item.bindType ~= BIND_QUEST
end

local function keyText(key)
    return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
end

local function cheaper(a, b)
    if a.minPrice ~= b.minPrice then return a.minPrice < b.minPrice end
    return keyText(a.itemKey) < keyText(b.itemKey)
end

-- The item variant's own name, such as "... of the Owl", once the client
-- has it; nil until then (C_AuctionHouse.GetItemKeyInfo, spec 4.1). Asking
-- is also what makes the client fetch it.
function Check.VariantName(itemKey)
    local AH = C_AuctionHouse
    local info = AH and AH.GetItemKeyInfo and AH.GetItemKeyInfo(itemKey)
    return type(info) == "table" and info.itemName or nil
end

-- An error in the check's own handling goes to the client's error handler.
local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

-- The appearance's items as a check sees them: done(tradeables, items), the
-- items that can be traded and all of them. An item whose data did not
-- answer counts as tradeable; one that failed to load does not. It reads
-- item data only, never the auction house, and
-- is not stopped by CancelAll.
function Check.Items(appearance, done)
    TC.Appearances.Items(appearance, function(items)
        local tradeables = {}
        for _, item in ipairs(items) do
            if tradeable(item) then tradeables[#tradeables + 1] = item end
        end
        done(tradeables, items)
    end)
end

-- Runs one check of the appearance. onItems (optional) gets the tradeable
-- items and all items as soon as they are known, before any answer. done
-- gets { outcome, rows, items, total, leftOut, queryFailed, noItems, error }:
-- outcome is "found", "not for sale", "cannot be sold" or "could not check"
-- (A7); rows are the item variants found, cheapest first; items the
-- tradeable items; leftOut how many of those total were not looked up;
-- noItems that no item of the appearance is known. Neither is called after
-- CancelAll.
function Check.Run(appearance, done, onItems)
    local mine = generation
    Check.Items(appearance, function(tradeables, items)
        if mine ~= generation then return end
        local wanted, byName, names = {}, {}, {}
        for _, item in ipairs(items) do wanted[item.itemID] = item end
        for _, item in ipairs(tradeables) do
            if item.loaded then
                if not byName[item.name] then
                    byName[item.name] = {}
                    names[#names + 1] = item.name
                end
                table.insert(byName[item.name], item)
            end
        end
        if onItems then onItems(tradeables, items) end
        local result = { rows = {}, items = tradeables, total = #tradeables, leftOut = 0, queryFailed = false }
        -- "cannot be sold" needs at least one item, every one known to bind
        -- on pickup, to be a quest item or to have failed to load (not on
        -- this server); no source, or sources that give no
        -- item, say nothing about selling
        if #items == 0 then
            result.outcome, result.noItems, result.error = "could not check", true, "no item of the appearance is known"
            return done(result)
        elseif #tradeables == 0 then
            result.outcome = "cannot be sold"
            return done(result)
        end
        local lookedUp, open, kept = 0, math.min(#names, MAX_NAMES), {}
        local function finish()
            result.leftOut = #tradeables - lookedUp
            for _, row in pairs(kept) do result.rows[#result.rows + 1] = row end
            table.sort(result.rows, cheaper)
            if result.broken then
                result.outcome = "could not check"
            elseif result.rows[1] then
                result.outcome = "found"
            elseif result.leftOut == 0 then
                result.outcome = "not for sale"
            else
                result.outcome = "could not check"
                result.error = result.error or ("%d of %d items not looked up"):format(result.leftOut, #tradeables)
            end
            done(result)
        end
        if open == 0 then return finish() end
        for i = 1, open do
            local name = names[i]
            TC.AuctionQueue.Browse({ searchString = name, sorts = PRICE_THEN_NAME, filters = {} }, MAX_PAGES, {
                done = function(rows, cut)
                    if mine ~= generation then return end
                    -- an error here still finishes the check, as could not
                    -- check, and is reported once
                    local ok, err = pcall(function()
                        -- a name matches loosely: keep the appearance's own
                        -- items, and each item variant once
                        local matched = {}
                        for _, row in ipairs(rows) do
                            local key = row.itemKey
                            local item = key and wanted[key.itemID]
                            local text = item and keyText(key)
                            if item then matched[key.itemID] = true end
                            if item and type(row.minPrice) == "number" and row.minPrice > 0
                                and (not kept[text] or row.minPrice < kept[text].minPrice) then
                                kept[text] = { itemKey = key, minPrice = row.minPrice, totalQuantity = row.totalQuantity,
                                    name = item.name, quality = item.quality }
                                Check.VariantName(key)
                            end
                        end
                        -- a browse cut off at MAX_PAGES looked up only the
                        -- items it found a row of (A7)
                        for _, item in ipairs(byName[name]) do
                            if not cut or matched[item.itemID] then
                                lookedUp = lookedUp + 1
                            else
                                result.error = ("the browse for %s was cut off at %d pages"):format(name, MAX_PAGES)
                            end
                        end
                    end)
                    if not ok then
                        result.broken, result.error = true, tostring(err)
                        report(err)
                    end
                    open = open - 1
                    if open == 0 then finish() end
                end,
                failed = function(reason)
                    if mine ~= generation then return end
                    result.queryFailed, result.error = true, reason
                    open = open - 1
                    if open == 0 then finish() end
                end,
            })
        end
    end)
end

-- Stops every running check: no further browse is queued for it and its
-- callbacks are not called. The queue itself is cancelled separately.
function Check.CancelAll()
    generation = generation + 1
end
