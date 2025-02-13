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

local function GetAllowedArmorForPlayer()
    local playerClass = select(2, UnitClass("player"))
    local playerLevel = UnitLevel("player")
    local mapping = {
        DEATHKNIGHT = 4,                           -- Plate
        WARRIOR     = (playerLevel < 40) and 3 or 4,  -- Mail/Plate
        PALADIN     = (playerLevel < 40) and 3 or 4,  -- Mail/Plate
        HUNTER      = (playerLevel < 40) and 2 or 3,  -- Leather/Mail
        ROGUE       = 2,                           -- Leather
        PRIEST      = 1,                           -- Cloth
        SHAMAN      = (playerLevel < 40) and 2 or 3,  -- Leather/Mail
        MAGE        = 1,                           -- Cloth
        WARLOCK     = 1,                           -- Cloth
        MONK        = 2,                           -- Leather
        DRUID       = 2,                           -- Leather
        DEMONHUNTER = 2,                           -- Leather
    }
    return mapping[playerClass]
end

local function ProcessSource(source, hoveredSourceID, allowedType, itemClassID, itemEquipLoc)
    if not source.itemID then 
        print("Debug: Source has no itemID")
        return false, nil 
    end
    
    local _, _, _, _, _, sClassID, sSubClassID = GetItemInfoInstant(source.itemID)
    print(string.format("Debug: Processing source itemID: %d, ClassID: %d, SubClassID: %d", source.itemID, sClassID, sSubClassID))
    
    if sClassID ~= itemClassID then 
        print("Debug: Class ID mismatch")
        return false, nil 
    end
    
    if source.sourceID == hoveredSourceID then 
        print("Debug: Same source, skipping")
        return false, nil 
    end
    
    -- For armor pieces that require type checking
    if itemClassID == 4 and armorSlotsThatRequireAllowedCheck[itemEquipLoc] then
        print(string.format("Debug: Checking armor type. Required: %d, Found: %d", allowedType, sSubClassID))
        if sSubClassID ~= allowedType then 
            print("Debug: Wrong armor type")
            return false, nil 
        end
    end
    
    if source.isCollected then
        print("Debug: Source is collected")
        return true, nil
    else
        local name, _, quality = GetItemInfo(source.itemID)
        print(string.format("Debug: Source not collected. Name: %s", name or "nil"))
        if name then
            return false, { name = name, quality = quality }
        end
        return false, nil
    end
end

local function CollectSources(sources, hoveredSourceID, allowedType, itemClassID, itemEquipLoc)
    local modelCollected = false
    local altSources = {}
    
    print(string.format("Debug: Processing %d sources", #sources))
    for _, source in pairs(sources) do
        local isCollected, altSource = ProcessSource(source, hoveredSourceID, allowedType, itemClassID, itemEquipLoc)
        if isCollected then
            modelCollected = true
        elseif altSource then
            table.insert(altSources, altSource)
        end
    end
    
    print(string.format("Debug: Found %d alternatives", #altSources))
    return modelCollected, altSources
end

function TC_ItemChecker:GetTransmogStatus(itemLink)
    -- Basic validation
    if not itemLink then return nil end
    
    -- Check if item belongs to valid equipment slot
    local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
    print("Debug - Item Equipment Location:", itemEquipLoc)
    if not itemEquipLoc or not validEquipLocs[itemEquipLoc] then
        return nil
    end

    -- Get item class info
    local _, _, _, _, _, itemClassID, itemSubClassID = GetItemInfoInstant(itemLink)
    if itemClassID ~= 4 and itemClassID ~= 2 then -- Not armor or weapon
        return nil
    end

    -- Check if armor type is allowed for player
    local allowedType = GetAllowedArmorForPlayer()
    local isAllowedArmor = true
    if itemClassID == 4 and armorSlotsThatRequireAllowedCheck[itemEquipLoc] then
        isAllowedArmor = (itemSubClassID == allowedType)
    end

    -- Get appearance info
    local appearanceID, hoveredSourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not appearanceID or not hoveredSourceID then
        return nil
    end

    -- Get all sources for this appearance
    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
    if not sources then
        return nil
    end

    -- Check if exact appearance is collected
    local exactCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(hoveredSourceID)
    
    -- Process all sources
    local modelCollected, altSources = CollectSources(sources, hoveredSourceID, allowedType, itemClassID, itemEquipLoc)

    -- Return appropriate status
    if isAllowedArmor then
        if exactCollected then
            return 1 -- EXACT COLLECTED
        elseif modelCollected then
            return 2 -- MODEL COLLECTED
        else
            return 3 -- MODEL NOT COLLECTED
        end
    else
        if #altSources > 0 then
            return 4, false, altSources -- NOT COLLECTABLE BY CLASS, ALTERNATIVES
        else
            return 5, false -- INVALID CLASS TO COLLECT
        end
    end
end

print("TC_ItemChecker: Module loaded.") 