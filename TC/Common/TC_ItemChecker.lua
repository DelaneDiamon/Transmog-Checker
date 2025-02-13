TC_ItemChecker = TC_ItemChecker or {}

local validEquipLocs = {
    ["INVTYPE_HEAD"]        = true,
    ["INVTYPE_SHOULDER"]    = true,
    ["INVTYPE_BODY"]        = true,
    ["INVTYPE_CHEST"]       = true,
    ["INVTYPE_ROBE"]        = true,
    ["INVTYPE_WAIST"]       = true,
    ["INVTYPE_LEGS"]        = true,
    ["INVTYPE_FEET"]        = true,
    ["INVTYPE_WRIST"]       = true,
    ["INVTYPE_HAND"]        = true,
    ["INVTYPE_CLOAK"]       = true,
    ["INVTYPE_WEAPON"]      = true,
    ["INVTYPE_SHIELD"]      = true,
    ["INVTYPE_2HWEAPON"]    = true,
    ["INVTYPE_WEAPONMAINHAND"] = true,
    ["INVTYPE_WEAPONOFFHAND"]  = true,
    ["INVTYPE_HOLDABLE"]    = true,
    ["INVTYPE_TABARD"]      = true,
    ["INVTYPE_RANGED"]      = true, 
    ["INVTYPE_RANGEDRIGHT"] = true,
}

-- List of equipment slots where the allowed armor subtype check applies.
local armorSlotsThatRequireAllowedCheck = {
    ["INVTYPE_HEAD"]      = true,
    ["INVTYPE_SHOULDER"]  = true,
    ["INVTYPE_CHEST"]     = true,
    ["INVTYPE_WRIST"]     = true,
    ["INVTYPE_HAND"]      = true,
    ["INVTYPE_WAIST"]     = true,  -- belt
    ["INVTYPE_LEGS"]      = true,
    ["INVTYPE_FEET"]      = true,
}

-- Returns the allowed armor subtype for the current player.
local function GetAllowedArmorForPlayer()
    local playerClass = select(2, UnitClass("player"))
    local playerLevel = UnitLevel("player")
    local mapping = {
        DEATHKNIGHT = 4,                           -- Plate
        WARRIOR     = (playerLevel < 40) and 3 or 4,  -- <40: Mail, else Plate
        PALADIN     = (playerLevel < 40) and 3 or 4,
        HUNTER      = (playerLevel < 40) and 2 or 3,  -- <40: Leather, else Mail
        ROGUE       = 2,                           -- Leather
        PRIEST      = 1,                           -- Cloth
        SHAMAN      = (playerLevel < 40) and 2 or 3,  -- <40: Leather, else Mail
        MAGE        = 1,                           -- Cloth
        WARLOCK     = 1,                           -- Cloth
        MONK        = 2,                           -- Leather
        DRUID       = 2,                           -- Leather
        DEMONHUNTER = 2,                           -- Leather
    }
    return mapping[playerClass]
end

-- Returns three values:
--   status     : (number)
--                1 = EXACT COLLECTED
--                2 = MODEL COLLECTED (an allowed alternative is collected)
--                3 = MODEL NOT COLLECTED (appearance from allowed armor/weapon not collected)
--                4 = NOT COLLECTABLE BY CLASS, ALTERNATIVES exist
--                5 = INVALID CLASS TO COLLECT (no allowed alternative)
--   eligible   : (boolean) whether the current character can equip the item (from IsEquippableItem)
--   altSources : (table) list of alternative allowed sources (each entry is a table with keys: name and quality)
function TC_ItemChecker:GetTransmogStatus(itemLink)
    if not itemLink then
        return nil, false, nil
    end

    local _, _, itemRarity, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
    -- If the item does not have an equip slot or its slot is not among valid ones (e.g. ring/neck), return early.
    if not itemEquipLoc or not validEquipLocs[itemEquipLoc] then
        return nil, false, nil
    end

    -- Check if the item is equippable by the current character.
    local eligible = IsEquippableItem(itemLink)
    -- Note: We no longer return early if not eligible. Even when the current class cannot equip the item,
    -- we want to check for alternative allowed appearances.

    local _, _, _, _, _, itemClassID, itemSubClassID = GetItemInfoInstant(itemLink)
    if itemClassID ~= 4 and itemClassID ~= 2 then
        return nil, eligible, nil
    end

    local allowedArmor = false
    local allowedType = nil
    if itemClassID == 4 then
        if armorSlotsThatRequireAllowedCheck[itemEquipLoc] then
            allowedType = GetAllowedArmorForPlayer()
            allowedArmor = (itemSubClassID == allowedType)
        else
            -- For armor in slots like cloaks, shields, etc., treat them as allowed.
            allowedArmor = true
        end
    else
        -- For weapons, they are always considered allowed.
        allowedArmor = true
    end

    local appearanceID, hoveredSourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not (appearanceID and hoveredSourceID) then
        return 5, eligible, nil
    end

    local exactCollected = false
    if allowedArmor then
        exactCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(hoveredSourceID)
    end

    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
    if not sources then
        return 5, eligible, nil
    end

    local modelCollected = false
    local altSources = {}
    for _, source in pairs(sources) do
        if source.itemID then
            local _, _, _, _, _, sClassID, sSubClassID = GetItemInfoInstant(source.itemID)
            if sClassID == itemClassID then
                if itemClassID == 4 then
                    if armorSlotsThatRequireAllowedCheck[itemEquipLoc] then
                        if sSubClassID == allowedType then
                            if source.sourceID ~= hoveredSourceID then
                                if source.isCollected then
                                    modelCollected = true
                                else
                                    local altName, _, altQuality = GetItemInfo(source.itemID)
                                    if altName then
                                        table.insert(altSources, { name = altName, quality = altQuality })
                                    end
                                end
                            end
                        end
                    else
                        -- For armor in non-checked slots (e.g. cloaks, shields), do not filter by armor subclass.
                        if source.sourceID ~= hoveredSourceID then
                            if source.isCollected then
                                modelCollected = true
                            else
                                local altName, _, altQuality = GetItemInfo(source.itemID)
                                if altName then
                                    table.insert(altSources, { name = altName, quality = altQuality })
                                end
                            end
                        end
                    end
                elseif itemClassID == 2 then
                    if source.sourceID ~= hoveredSourceID then
                        if source.isCollected then
                            modelCollected = true
                        else
                            local altName, _, altQuality = GetItemInfo(source.itemID)
                            if altName then
                                table.insert(altSources, { name = altName, quality = altQuality })
                            end
                        end
                    end
                end
            end
        end
    end

    if allowedArmor then
        if exactCollected then
            return 1, eligible, altSources   -- EXACT COLLECTED
        elseif modelCollected then
            return 2, eligible, altSources   -- MODEL COLLECTED
        else
            return 3, eligible, altSources   -- MODEL NOT COLLECTED
        end
    else
        if #altSources > 0 then
            return 4, eligible, altSources   -- NOT COLLECTABLE BY CLASS, ALTERNATIVES exist.
        else
            return 5, eligible, nil          -- INVALID CLASS TO COLLECT (no allowed alternatives)
        end
    end
end

print("TC_ItemChecker: Module loaded.") 