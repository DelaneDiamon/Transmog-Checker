-- The appearance source: the game's appearances for a slot, in the order
-- Collections shows them, each class's weapon types, whether each is
-- collected, the item a tile shows it with, and the items that carry it. It
-- hides the Collections category of each slot and
-- leaves Collections' own settings as it found them.
TC = TC or {}
TC.Appearances = {}

local Appearances = TC.Appearances

local function enum(name, key, fallback)
    local values = Enum and Enum[name]
    return values and values[key] or fallback
end

-- A category's Enum.TransmogCollectionType value, from TC.Slots' { key, value }.
local function categoryValue(category)
    return enum("TransmogCollectionType", category[1], category[2])
end

local function location(slotID)
    return {
        slotID = slotID,
        type = enum("TransmogType", "Appearance", 0),
        modification = enum("TransmogModification", "Main", 0),
    }
end

-- The client's list for the category, without hidden visuals, sorted as
-- Collections sorts it (Blizzard_Wardrobe.lua:962-975), added to list; an
-- appearance already in it is not added again, but its categories (category
-- to its place in that category's own order) learn this one.
local function readCategory(list, seen, slot, slotID, category)
    local infos = C_TransmogCollection.GetCategoryAppearances(category, location(slotID))
    local visible = {}
    for _, info in ipairs(type(infos) == "table" and infos or {}) do
        if info.visualID and not info.isHideVisual then
            visible[#visible + 1] = info
        end
    end
    local compare = CollectionWardrobeUtil and CollectionWardrobeUtil.CompareAppearance
    if compare then
        -- an order function that fails leaves the client's order
        local sorted = { unpack(visible) }
        if pcall(table.sort, sorted, compare) then
            visible = sorted
        end
    end
    for rank, info in ipairs(visible) do
        local appearance = seen[info.visualID]
        if not appearance then
            appearance = { id = info.visualID, slot = slot, category = category, categories = {} }
            seen[info.visualID] = appearance
            list[#list + 1] = appearance
        end
        appearance.categories[category] = rank
    end
end

-- The client's name of a filter entry's subclass, such as "Daggers"
-- (C_Item.GetItemSubClassInfo, ItemDocumentation.lua:1020-1036), or nil.
local function subclassName(filter)
    local E = Enum
    local subclasses = E and (filter[1] == "Armor" and E.ItemArmorSubclass or E.ItemWeaponSubclass)
    local classID, subClassID = E and E.ItemClass and E.ItemClass[filter[1]], subclasses and subclasses[filter[2]]
    if not (classID and subClassID and C_Item and C_Item.GetItemSubClassInfo) then return nil end
    local ok, name = pcall(C_Item.GetItemSubClassInfo, classID, subClassID)
    return ok and name or nil
end

-- Which flag of GetCategoryInfo (name, isWeapon, canHaveIllusions,
-- canMainHand, canOffHand, canRanged) fits a weapon slot's inventory slot.
local FLAG_OF_SLOT = { [16] = 4, [17] = 5, [18] = 6 }

-- Every weapon slot's categories in the slot table, ascending, each once:
-- the categories the weapon types are learnt from.
local function weaponCategories()
    local list, seen = {}, {}
    for _, entry in ipairs(TC.Slots) do
        if entry.weapon then
            for _, category in ipairs(entry.categories) do
                local value = categoryValue(category)
                if not seen[value] then
                    seen[value] = true
                    list[#list + 1] = value
                end
            end
        end
    end
    table.sort(list)
    return list
end

-- Whether any class learnt has a weapon type in the slot.
local function anyType(learnt, slot)
    for _, has in pairs(learnt) do
        if next(has[slot]) then return true end
    end
    return false
end

-- The weapon types of a weapon slot, in Collections' order (ascending, as
-- Blizzard_Wardrobe.lua:884 walks them): a list of { category, name }.
-- learnt is what LearnWeaponTypes gave: for classID, the categories that
-- class has in the slot; for nil (every class) or a class it did not learn,
-- those any class has. false, or a slot no class has a weapon type in: the
-- fixed split of spec 4.3 (open point 4) for every class, named by the
-- client's subclass names. An armor slot has none.
function Appearances.WeaponTypes(slot, learnt, classID)
    local entry = TC.Slots[slot]
    local types = {}
    if not (entry and entry.weapon) then return types end
    if not (learnt and anyType(learnt, slot)) then
        for _, category in ipairs(entry.categories) do
            types[#types + 1] = { category = categoryValue(category), name = subclassName(category[3]) or category[1] }
        end
        return types
    end
    local own = classID ~= nil and learnt[classID]
    for _, category in ipairs(weaponCategories()) do
        local name
        if own then
            name = own[slot][category]
        else
            for _, has in pairs(learnt) do name = name or has[slot][category] end
        end
        if name then types[#types + 1] = { category = category, name = name } end
    end
    return types
end

-- The weapon types Collections' class filter gives now (TC-38): by weapon
-- slot key, the weapon categories GetCategoryInfo answers with the slot's
-- flag, each with its name; and whether it answered for any category.
local function readTypes()
    local info = C_TransmogCollection.GetCategoryInfo
    local has, answered = {}, false
    for _, entry in ipairs(TC.Slots) do
        if entry.weapon then has[entry.key] = {} end
    end
    for _, category in ipairs(weaponCategories()) do
        local answer = { info(category) }
        if type(answer[1]) == "string" then
            answered = true
            for _, entry in ipairs(TC.Slots) do
                if entry.weapon and answer[FLAG_OF_SLOT[entry.slotID]] then
                    has[entry.key][category] = answer[1]
                end
            end
        end
    end
    return has, answered
end

-- The one place that writes Collections' class filter: sets it to classID
-- and answers whether the client took it (read back).
local function setClassFilter(classID)
    local TCol = C_TransmogCollection
    if not (TCol and TCol.SetClassFilter and TCol.GetClassFilter) then return false end
    return pcall(TCol.SetClassFilter, classID) and TCol.GetClassFilter() == classID
end

-- The classes the weapon types are learnt for: the client's class list
-- (C_SpecializationInfo.GetAllClassIDs), else the character's own.
local function classIDs()
    local Spec = C_SpecializationInfo
    local ids = Spec and Spec.GetAllClassIDs and Spec.GetAllClassIDs()
    if type(ids) == "table" and ids[1] then return ids end
    local id = UnitClass and select(3, UnitClass("player"))
    return { id }
end

-- The pass that runs, or nil.
local pass

-- Reads what the filter gives for classID into run, after checking the
-- filter is still on it.
local function learnClass(run, classID)
    if C_TransmogCollection.GetClassFilter() ~= classID then error("the class filter moved", 0) end
    local has, answered = readTypes()
    run.learnt[classID], run.answered = has, run.answered or answered
end

-- Puts the filter back as it was found (read back). A refused write is
-- tried once more on the next frame, unless a new pass runs by then; when
-- that is refused too, onError gets the text.
local function restore(run)
    if setClassFilter(run.was) then return end
    local function refused()
        if run.onError then run.onError("the class filter was not put back to " .. tostring(run.was)) end
    end
    if not (C_Timer and C_Timer.After) then return refused() end
    C_Timer.After(0, function()
        if not pass and not setClassFilter(run.was) then refused() end
    end)
end

-- Ends a pass: the filter back as it was found, then done gets learnt, or
-- false (the fixed split) when nothing answered.
local function finish(run, learnt)
    if pass == run then pass = nil end
    restore(run)
    run.done(learnt and run.answered and learnt or false)
end

-- One frame of the pass, as the probe read: the class set on the frame
-- before is read, then the next class is set, so nothing is read in the
-- frame of a write. Collections opened in the middle ends the pass on the
-- fixed split.
local function step(run, i)
    if pass ~= run then return end
    local ok = pcall(function()
        if CollectionsJournal and CollectionsJournal.IsShown and CollectionsJournal:IsShown() then
            error("Collections is open", 0)
        end
        if i > 1 then learnClass(run, run.classes[i - 1]) end
        if run.classes[i] and not setClassFilter(run.classes[i]) then error("the class filter was refused", 0) end
    end)
    if not ok then return finish(run, false) end
    if not run.classes[i] then return finish(run, run.learnt) end
    C_Timer.After(0, function() step(run, i + 1) end)
end

-- Learns which weapon categories each class has in each weapon slot (TC-38,
-- measured with /tcprobe weapons on 2026-11-25): Collections' class filter
-- is set to each class in turn, one class per frame, and GetCategoryInfo
-- read on the frame after the set, then put back as it was found. done(learnt)
-- is called once, at the end of the pass, with { [classID] = { [slot key] =
-- { [category] = name } } }, or false for the fixed split: when a call
-- raises, a set raises or is refused, nothing answers, or a call is missing.
-- Not called after StopWeaponTypes. onError(text) is called when the filter
-- could not be put back. The filter is put back on every way out.
function Appearances.LearnWeaponTypes(done, onError)
    if pass then Appearances.StopWeaponTypes() end
    local TCol = C_TransmogCollection
    local ok, was, classes = pcall(function()
        return TCol and TCol.GetCategoryInfo and TCol.GetClassFilter and TCol.GetClassFilter(), classIDs()
    end)
    if not (ok and was and classes[1] and C_Timer and C_Timer.After) then return done(false) end
    pass = { was = was, classes = classes, done = done, onError = onError, learnt = {} }
    step(pass, 1)
end

-- Stops a pass spread over frames (the tab was left or the visit ended):
-- the filter is put back at once and done is not called.
function Appearances.StopWeaponTypes()
    local run = pass
    pass = nil
    if run then restore(run) end
end

-- The scan filter entry the slot table gives a weapon category, or nil when
-- no weapon slot's table has the category.
function Appearances.CategoryFilter(category)
    for _, entry in ipairs(TC.Slots) do
        if entry.weapon then
            for _, own in ipairs(entry.categories) do
                if categoryValue(own) == category then return own[3] end
            end
        end
    end
end

-- The categories List reads for the slot: an armor slot's one; a weapon
-- slot's weapon types (types, when the caller has them, else the fixed
-- split), or the one weaponType picks.
local function categoriesOf(slot, entry, weaponType, types)
    if not entry.weapon then return { categoryValue(entry.categories[1]) } end
    local categories = {}
    for _, weapon in ipairs(types or Appearances.WeaponTypes(slot, false)) do
        if weaponType == nil or weapon.category == weaponType then categories[#categories + 1] = weapon.category end
    end
    return categories
end

-- The appearances of a slot, in Collections' order, each { id, slot,
-- category, categories }. A weapon slot is the union of its weapon types'
-- lists, each in Collections' order, in the order of the weapon types, each
-- appearance once; weaponType (a category) narrows it to one. types: the
-- slot's WeaponTypes when the caller has them. A category's list is the
-- same under every class filter (measured in game on 2026-11-25), so the
-- filter is not touched.
function Appearances.List(slot, weaponType, types)
    local entry = TC.Slots[slot]
    local TCol = C_TransmogCollection
    if not (entry and TCol and TCol.GetCategoryAppearances) then return {} end
    local list, seen = {}, {}
    for _, category in ipairs(categoriesOf(slot, entry, weaponType, types)) do
        readCategory(list, seen, slot, entry.slotID, category)
    end
    return list
end

-- Collected when the account has the appearance from any of its sources.
-- This loop is the one rule for collected (spec section 3); the list's own
-- isCollected flag and the per-source appearance info call (spec 4.5) are
-- not used for it.
function Appearances.IsCollected(appearance)
    local TCol = C_TransmogCollection
    if not (TCol and TCol.GetAllAppearanceSources and TCol.PlayerHasTransmogItemModifiedAppearance) then
        return false
    end
    for _, sourceID in ipairs(TCol.GetAllAppearanceSources(appearance.id) or {}) do
        if TCol.PlayerHasTransmogItemModifiedAppearance(sourceID) then
            return true
        end
    end
    return false
end

-- The appearances the items in the backpack and the equipped bags carry, as
-- a set of appearance ids (TC-39). The bags are walked as Blizzard's
-- SearchBagsForFirstItem walks them (ContainerFrame.lua:411-420): Backpack to
-- NUM_TOTAL_EQUIPPED_BAG_SLOTS, C_Container.GetContainerNumSlots and
-- GetContainerItemID (ContainerDocumentation.lua:175-190, 313-325); an item's
-- appearance is C_TransmogCollection.GetItemInfo, which needs no item data.
-- Without those calls the set is empty.
function Appearances.ReadBags()
    local found = {}
    local Bags, TCol = C_Container, C_TransmogCollection
    if not (Bags and Bags.GetContainerNumSlots and Bags.GetContainerItemID and TCol and TCol.GetItemInfo) then
        return found
    end
    local first = Enum and Enum.BagIndex and Enum.BagIndex.Backpack or 0
    local seen = {}
    for bag = first, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, Bags.GetContainerNumSlots(bag) or 0 do
            local itemID = Bags.GetContainerItemID(bag, slot)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                local appearanceID = TCol.GetItemInfo(itemID)
                if appearanceID then found[appearanceID] = true end
            end
        end
    end
    return found
end

-- The appearance's item ids, each once, in the order of its sources; kept on
-- the appearance once its sources gave any. It needs no item data.
function Appearances.ItemIDs(appearance)
    if appearance.itemIDs then return appearance.itemIDs end
    local TCol = C_TransmogCollection
    local ids, seen = {}, {}
    local sources = TCol and TCol.GetAllAppearanceSources and TCol.GetAllAppearanceSources(appearance.id)
    for _, sourceID in ipairs(type(sources) == "table" and sources or {}) do
        local info = TCol.GetSourceInfo and TCol.GetSourceInfo(sourceID)
        local itemID = type(info) == "table" and info.itemID
        if itemID and not seen[itemID] then
            seen[itemID] = true
            ids[#ids + 1] = itemID
        end
    end
    if ids[1] then appearance.itemIDs = ids end
    return ids
end

-- The class filter is the addon's own narrowing by armor type (TC-32): the
-- game lists the same appearances under every class filter (measured in
-- game on 2026-11-25, feet, nine classes). The armor types each class wears,
-- by class id; armor is cumulative. A class not in the table is not
-- narrowed.
local WEARS = {
    [5] = { "Cloth" }, [8] = { "Cloth" }, [9] = { "Cloth" },
    [4] = { "Cloth", "Leather" }, [11] = { "Cloth", "Leather" },
    [3] = { "Cloth", "Leather", "Mail" }, [7] = { "Cloth", "Leather", "Mail" },
    [1] = { "Cloth", "Leather", "Mail", "Plate" }, [2] = { "Cloth", "Leather", "Mail", "Plate" },
}
local ARMOR_TYPES = { "Cloth", "Leather", "Mail", "Plate" }

-- The armor types of the appearance's items, as a set of subclass values, or
-- false when it shows for every class: an item of subclass Generic, or no
-- item that gives an armor type. C_Item.GetItemInfoInstant gives classID
-- (6th) and subClassID (7th) without item data (ItemDocumentation.lua:
-- 659-679); that it does so on Forever is unverified in game.
local function armorTypes(appearance)
    if appearance.armorTypes ~= nil then return appearance.armorTypes end
    local E = Enum
    local armor = E and E.ItemClass and E.ItemClass.Armor
    local subclasses = E and E.ItemArmorSubclass
    local instant = C_Item and C_Item.GetItemInfoInstant
    local types = false
    if armor and subclasses and instant then
        local wearable = {}
        for _, name in ipairs(ARMOR_TYPES) do
            if subclasses[name] then wearable[subclasses[name]] = true end
        end
        for _, itemID in ipairs(Appearances.ItemIDs(appearance)) do
            local _, _, _, _, _, classID, subClassID = instant(itemID)
            -- Generic and Cosmetic armor is worn by every class
            if classID == armor and subClassID ~= nil
                and (subClassID == subclasses.Generic or subClassID == subclasses.Cosmetic) then
                types = false
                break
            elseif classID == armor and wearable[subClassID] then
                types = types or {}
                types[subClassID] = true
            end
        end
    end
    appearance.armorTypes = types
    return types
end

-- Whether the class filter on classID shows the appearance. Weapons,
-- shields, cloaks, shirts and tabards show for every class (TC-32); an
-- armor appearance shows when one of its items has an armor type the class
-- wears. Missing data never hides an appearance.
function Appearances.UsableBy(appearance, classID)
    local entry = TC.Slots[appearance.slot]
    local wears = WEARS[classID]
    if not entry or entry.weapon or entry.anyClass or not wears then return true end
    local types = armorTypes(appearance)
    if not types then return true end
    local subclasses = Enum.ItemArmorSubclass
    for _, name in ipairs(wears) do
        if types[subclasses[name]] then return true end
    end
    return false
end

-- The profession that makes a crafted item (TC-35): an inference from the
-- item's type, applied only to a source the client itself marks as
-- profession; the client cannot name the profession. Only the types one
-- profession alone makes are named. Each entry: ItemClass key, subclass key
-- (ItemArmorSubclass for Armor, ItemWeaponSubclass for Weapon), the
-- profession; slot: only for that equip location; notSlot: not for those
-- equip locations (a set). Head pieces of cloth and leather are left out:
-- engineers make goggles of both in the classic game, so a crafted head
-- piece stays plain "Profession", as cloaks do.
local PROFESSION_OF_TYPE = {
    { "Armor", "Cloth", "Tailoring", notSlot = { INVTYPE_CLOAK = true, INVTYPE_HEAD = true } },
    { "Armor", "Leather", "Leatherworking", notSlot = { INVTYPE_HEAD = true } },
    { "Armor", "Plate", "Blacksmithing" },
    { "Armor", "Generic", "Tailoring", slot = "INVTYPE_BODY" },
    { "Weapon", "Wand", "Enchanting" },
    { "Weapon", "Guns", "Engineering" },
}

-- The English name of the profession the item's type settles, or nil. It
-- reads C_Item.GetItemInfoInstant (equip location 4th, class 6th, subclass
-- 7th, ItemDocumentation.lua:659-679), which needs no item data.
function Appearances.Profession(itemID)
    local E, instant = Enum, C_Item and C_Item.GetItemInfoInstant
    if not (itemID and E and E.ItemClass and instant) then return nil end
    local _, _, _, equipLoc, _, classID, subClassID = instant(itemID)
    if classID == nil or subClassID == nil then return nil end
    for _, entry in ipairs(PROFESSION_OF_TYPE) do
        local subclasses = entry[1] == "Armor" and E.ItemArmorSubclass or E.ItemWeaponSubclass
        if classID == E.ItemClass[entry[1]] and subclasses and subClassID == subclasses[entry[2]]
            and (entry.slot == nil or entry.slot == equipLoc) and not (entry.notSlot and entry.notSlot[equipLoc]) then
            return entry[3]
        end
    end
    return nil
end

-- Spec Assumption A5: a check waits at most 2 seconds for item names.
local ITEM_WAIT = 2

-- Items calls still waiting for item data.
local pending = {}
-- Item names once the client gave them, by item id. failed: items whose
-- data the client answered as failed to load this visit; they are not on
-- this server and are never asked again (TC-32).
local names, failed = {}, {}
-- Search's name loading (TC-32): the item ids still to ask for, 20 per
-- frame; asked: ids queued or asked this visit; loads: raised by
-- ResetLoads, so a tick of an earlier visit stops.
local LOADS_PER_FRAME = 20
local toLoad, asked, loads = {}, {}, 0
local nameListener

-- The item's name if the client has its data, else nil; it never asks the
-- client to load it (IsItemDataCachedByID first, when the client has it).
function Appearances.ItemName(itemID)
    if names[itemID] then return names[itemID] end
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then return nil end
    local name = C_Item.GetItemInfo(itemID)
    names[itemID] = name
    return name
end

-- fn(itemID) is called when an item's name arrives.
function Appearances.SetNameListener(fn)
    nameListener = fn
end

local function loadTick()
    local mine = loads
    local n = 0
    while toLoad[1] and n < LOADS_PER_FRAME do
        local itemID = table.remove(toLoad, 1)
        if not failed[itemID] and not Appearances.ItemName(itemID) then
            C_Item.RequestLoadItemDataByID(itemID)
            n = n + 1
        end
    end
    if toLoad[1] and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if mine == loads then loadTick() end
        end)
    end
end

-- Asks the client for the data of the items that have no name yet, 20 per
-- frame, the first 20 at once. An item asked for in this visit, or one that
-- failed to load, is not asked again. It never reads the auction house.
function Appearances.LoadNames(itemIDs)
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
    local idle = not toLoad[1]
    for _, itemID in ipairs(itemIDs) do
        if not asked[itemID] and not failed[itemID] and not Appearances.ItemName(itemID) then
            asked[itemID] = true
            toLoad[#toLoad + 1] = itemID
        end
    end
    if idle then loadTick() end
end

-- Drops the items still waiting to be asked for (the player left the tab or
-- the slot); they were not asked, so a later use may ask for them.
function Appearances.StopLoads()
    loads = loads + 1
    for _, itemID in ipairs(toLoad) do asked[itemID] = nil end
    toLoad = {}
end

-- A new visit: what failed may load now, and nothing is left to ask for.
function Appearances.ResetLoads()
    loads = loads + 1
    toLoad, asked, failed = {}, {}, {}
end

-- C_Item.GetItemInfo: 1 name, 3 quality, 7 subtype, 14 bind type
-- (ItemDocumentation.lua:636-655); nothing until the item's data is in.
local function readItem(item)
    local getInfo = C_Item and C_Item.GetItemInfo
    local name, quality, subType, bindType, _
    if getInfo then
        name, _, quality, _, _, _, subType, _, _, _, _, _, _, bindType = getInfo(item.itemID)
    end
    if name then
        item.name, item.quality, item.subType, item.bindType, item.loaded = name, quality, subType, bindType, true
    end
    return item.loaded
end

-- Every item loaded, or reported by the client as failed to load.
local function allLoaded(request)
    for _, item in ipairs(request.items) do
        if not (item.loaded or item.failed) then return false end
    end
    return true
end

local function answer(request)
    if request.answered then return end
    request.answered = true
    pending[request] = nil
    request.done(request.items)
end

local itemFrame = CreateFrame("Frame")
-- ITEM_DATA_LOAD_RESULT(itemID, success), ItemDocumentation.lua:1855-1864.
itemFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
itemFrame:SetScript("OnEvent", function(_, _, itemID, success)
    if success == false then
        failed[itemID] = true
    elseif asked[itemID] and Appearances.ItemName(itemID) and nameListener then
        nameListener(itemID)
    end
    for request in pairs(pending) do
        for _, item in ipairs(request.items) do
            if item.itemID == itemID and not readItem(item) and success == false then item.failed = true end
        end
        if allLoaded(request) then answer(request) end
    end
end)

-- The appearance's items, each once, in the order of its sources: done gets
-- a list of { itemID, name, quality, bindType, subType, loaded, failed }. It
-- is called once: as soon as every item's data is in or the client reported
-- it failed to load, and at the latest 2 seconds after the call, with loaded
-- false on the items that are not in. An item that failed to load earlier
-- in the visit is failed at once and not asked again.
function Appearances.Items(appearance, done)
    local request = { items = {}, done = done }
    for _, itemID in ipairs(Appearances.ItemIDs(appearance)) do
        request.items[#request.items + 1] = { itemID = itemID, loaded = false, failed = failed[itemID] }
    end
    for _, item in ipairs(request.items) do
        if not readItem(item) and not item.failed and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(item.itemID)
        end
    end
    if allLoaded(request) or not (C_Timer and C_Timer.After) then
        return answer(request)
    end
    pending[request] = true
    C_Timer.After(ITEM_WAIT, function()
        for _, item in ipairs(request.items) do
            if not item.loaded then readItem(item) end
        end
        answer(request)
    end)
end

-- The appearance's sources in the category List read it from, each the
-- client's AppearanceSourceInfo (GetAppearanceSources,
-- TransmogItemsDocumentation.lua:212-228: sourceID, itemID, isCollected,
-- sourceType, name and quality once the item is loaded), in Collections'
-- order (CollectionWardrobeUtil.SortSources, as GetSortedAppearanceSources
-- sorts them, Blizzard_FrameXMLUtil/CollectionsUtil.lua:43-89). An order
-- function that fails leaves the client's order; no answer is an empty list.
function Appearances.Sources(appearance)
    local TCol = C_TransmogCollection
    local entry = TC.Slots[appearance.slot]
    if not (TCol and TCol.GetAppearanceSources and entry) then return {} end
    local category = appearance.category or categoryValue(entry.categories[1])
    local sources = TCol.GetAppearanceSources(appearance.id, category, location(entry.slotID))
    if type(sources) ~= "table" then return {} end
    local sort = CollectionWardrobeUtil and CollectionWardrobeUtil.SortSources
    local ok, sorted = false, nil
    if sort then ok, sorted = pcall(sort, sources) end
    return ok and type(sorted) == "table" and sorted or sources
end

-- The source a tile is dressed with: the first of the category's sources
-- after Collections' sort, or else any source of the appearance
-- (WardrobeItemsCollectionMixin:GetAnAppearanceSourceFromVisual, as the
-- probe's tiles used it).
function Appearances.DisplaySource(appearance)
    local TCol = C_TransmogCollection
    if not (TCol and TC.Slots[appearance.slot]) then return nil end
    local sources = Appearances.Sources(appearance)
    if sources[1] then return sources[1].sourceID end
    local all = TCol.GetAllAppearanceSources and TCol.GetAllAppearanceSources(appearance.id)
    return type(all) == "table" and all[1] or nil
end
