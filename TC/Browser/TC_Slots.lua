-- The 14 slots of the appearance browser's slot row, in Collections' order
-- (Blizzard_Collections/Camelot/Blizzard_Wardrobe.lua:24-27, OverrideDefaults),
-- in one table (spec 4.3): the slot's name, its group in the row, Collections'
-- art for its button, its Collections categories, the inventory slot its
-- appearances are listed for, and its scan filter entries. anyClass: the
-- class filter does not narrow the slot (cloaks, shirts and tabards; weapon
-- slots are narrowed by each class's weapon types instead, TC-38). zoom: how much farther out than
-- Collections' own camera the slot's models are framed (1 when absent), so a
-- cloak is not cut off. Values are names
-- of the client's enums, read where they are used; a category also carries
-- its value on build 71037 (TransmogSharedDocumentation.lua:6-40). Only the
-- feet row was run in game; every other row is the spec's inferred or
-- unverified default (spec 4.3, open point 3). A table, no code: it creates
-- no frame and reads nothing.
TC = TC or {}

-- Four entries, one per armor type, for an armor slot's inventory type.
local function armorTypes(inventoryType)
    local entries = {}
    for _, armorType in ipairs({ "Cloth", "Leather", "Mail", "Plate" }) do
        entries[#entries + 1] = { "Armor", armorType, inventoryType }
    end
    return entries
end

-- A filter entry is { ItemClass key, subclass key, InventoryType key or nil };
-- the subclass enum is ItemArmorSubclass for Armor, ItemWeaponSubclass for
-- Weapon. Every entry names its subclass (spec 4.5).
local chest = armorTypes("IndexChestType")
for _, entry in ipairs(armorTypes("IndexRobeType")) do chest[#chest + 1] = entry end

-- A weapon slot's categories in Collections' order (ascending, as
-- Blizzard_Wardrobe.lua:884 walks them), each the fixed split of spec 4.3
-- used when the weapon types cannot be learnt from GetCategoryInfo (open
-- point 4), with its own filter entry.
TC.Slots = {
    { key = "head", name = "Head", group = 1, art = "head", slotID = 1,
        categories = { { "Head", 1 } }, filters = armorTypes("IndexHeadType") },
    { key = "shoulder", name = "Shoulder", group = 1, art = "shoulder", slotID = 3,
        categories = { { "Shoulder", 2 } }, filters = armorTypes("IndexShoulderType") },
    { key = "back", name = "Back", group = 1, art = "back", slotID = 15, anyClass = true, zoom = 1.236,
        categories = { { "Back", 3 } }, filters = { { "Armor", "Cloth", "IndexCloakType" } } },
    { key = "chest", name = "Chest", group = 1, art = "chest", slotID = 5,
        categories = { { "Chest", 4 } }, filters = chest },
    { key = "shirt", name = "Shirt", group = 1, art = "shirt", slotID = 4, anyClass = true,
        categories = { { "Shirt", 5 } }, filters = { { "Armor", "Generic", "IndexBodyType" } } },
    -- the subclass is a guess: tabards are not in Blizzard's tree (spec 4.3)
    { key = "tabard", name = "Tabard", group = 1, art = "tabard", slotID = 19, anyClass = true,
        categories = { { "Tabard", 6 } }, filters = { { "Armor", "Generic", "IndexTabardType" } } },
    { key = "wrist", name = "Wrist", group = 1, art = "wrist", slotID = 9,
        categories = { { "Wrist", 7 } }, filters = armorTypes("IndexWristType") },
    { key = "hands", name = "Hands", group = 2, art = "hands", slotID = 10,
        categories = { { "Hands", 8 } }, filters = armorTypes("IndexHandType") },
    { key = "waist", name = "Waist", group = 2, art = "waist", slotID = 6,
        categories = { { "Waist", 9 } }, filters = armorTypes("IndexWaistType") },
    { key = "legs", name = "Legs", group = 2, art = "legs", slotID = 7,
        categories = { { "Legs", 10 } }, filters = armorTypes("IndexLegsType") },
    { key = "feet", name = "Feet", group = 2, art = "feet", slotID = 8,
        categories = { { "Feet", 11 } }, filters = armorTypes("IndexFeetType") },
    { key = "mainhand", name = "Main hand", group = 3, art = "mainhand", slotID = 16, weapon = true,
        categories = { { "OneHAxe", 13, { "Weapon", "Axe1H" } }, { "OneHSword", 14, { "Weapon", "Sword1H" } },
            { "OneHMace", 15, { "Weapon", "Mace1H" } }, { "Dagger", 16, { "Weapon", "Dagger" } },
            { "Fist", 17, { "Weapon", "Unarmed" } }, { "TwoHAxe", 20, { "Weapon", "Axe2H" } },
            { "TwoHSword", 21, { "Weapon", "Sword2H" } }, { "TwoHMace", 22, { "Weapon", "Mace2H" } },
            { "Staff", 23, { "Weapon", "Staff" } }, { "Polearm", 24, { "Weapon", "Polearm" } } } },
    { key = "offhand", name = "Off hand", group = 3, art = "secondaryhand", slotID = 17, weapon = true,
        categories = { { "Shield", 18, { "Armor", "Shield" } },
            { "Holdable", 19, { "Armor", "Generic", "IndexHoldableType" } } } },
    { key = "ranged", name = "Ranged", group = 3, art = "ranged", slotID = 18, weapon = true,
        categories = { { "Wand", 12, { "Weapon", "Wand" } }, { "Bow", 25, { "Weapon", "Bows" } },
            { "Gun", 26, { "Weapon", "Guns" } }, { "Crossbow", 27, { "Weapon", "Crossbow" } } } },
}

-- A weapon slot's filter entries are its categories' own. TC.Slots[key] is
-- the slot of that key.
for _, slot in ipairs(TC.Slots) do
    TC.Slots[slot.key] = slot
    if slot.weapon then
        slot.filters = {}
        for _, category in ipairs(slot.categories) do slot.filters[#slot.filters + 1] = category[3] end
    end
end
