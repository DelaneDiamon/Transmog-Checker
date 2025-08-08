TC_ItemChecker = TC_ItemChecker or {}
TC_ItemChecker.debug = false -- Debug flag, off by default

function TC_ItemChecker:Debug(...)
    if TC_ItemChecker.debug then
        print("|cFF9D9D9DTC Debug:|r", ...)
    end
end

-- Status codes
local STATUS_EXACT_COLLECTED = 1
local STATUS_MODEL_COLLECTED = 2
local STATUS_MODEL_NOT_COLLECTED = 3
local STATUS_NOT_COLLECTABLE_BY_CLASS = 4
local STATUS_INVALID_CLASS_TO_COLLECT = 5
local STATUS_NO_INFO_YET = 6 -- New: neutral state for missing/uncached API data

-- Add command to toggle debug mode
SLASH_TC1 = "/tc"
SlashCmdList["TC"] = function(msg)
    if msg == "debug" then
        TC_ItemChecker.debug = not TC_ItemChecker.debug
        print("|cFF9D9D9DTC:|r Debug mode " .. (TC_ItemChecker.debug and "enabled" or "disabled"))
    end
end

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

-- Helper to obtain class/subclass across Classic/Retail differences of GetItemInfoInstant
local function GetItemClassAndSubClass(item)
    local r1, r2, r3, r4, r5, r6, r7 = GetItemInfoInstant(item)
    -- Retail (7 returns): classID=r6, subClassID=r7
    -- Classic variants (6 returns): classID=r5, subClassID=r6
    local classID, subClassID
    if r7 ~= nil then
        classID, subClassID = r6, r7
    else
        classID, subClassID = r5, r6
    end
    return classID, subClassID
end

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

-- Determine if the player can collect the given source/item by class rules
local function IsPlayerEligibleForItem(hoveredSourceID, itemClassID, itemEquipLoc, itemSubClassID)
    -- For armor, use strict armor-type rule first. Do not trust source info flags
    -- because playerCanCollect may be false for BoE or not-in-inventory items.
    if itemClassID == 4 and armorSlotsThatRequireAllowedCheck[itemEquipLoc] then
        local allowedType = GetAllowedArmorForPlayer()
        local eligible = (itemSubClassID == allowedType)
        TC_ItemChecker:Debug(string.format("Armor eligibility fallback: itemSubClass=%s, allowed=%s -> %s",
            tostring(itemSubClassID), tostring(allowedType), tostring(eligible)))
        return eligible
    end

    -- For weapons/others, prefer source info when available
    if hoveredSourceID and C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
        local si = C_TransmogCollection.GetSourceInfo(hoveredSourceID)
        if si then
            if si.isValidSourceForPlayer == false then
                TC_ItemChecker:Debug("Eligibility: source is not valid for player")
                return false
            end
            if si.isValidSourceForPlayer == true then
                TC_ItemChecker:Debug("Eligibility: source is valid for player")
                return true
            end
            if si.playerCanCollect == false then
                TC_ItemChecker:Debug("Eligibility: player cannot collect source")
                return false
            end
            if si.playerCanCollect == true then
                TC_ItemChecker:Debug("Eligibility: player can collect source")
                return true
            end
        end
    end

    -- For weapons/others, consult API when available; trust explicit false, but
    -- if API returns true/nil, allow it.
    if hoveredSourceID and C_TransmogCollection and C_TransmogCollection.PlayerCanCollectSource then
        local ok = C_TransmogCollection.PlayerCanCollectSource(hoveredSourceID)
        if ok == false then return false end
        if ok == true then return true end
    end

    -- Default to eligible for non-armor slots if no better signal is available
    return true
end

local function ProcessSource(source, hoveredSourceID, allowedType, itemClassID, itemEquipLoc)
    if not source.itemID then 
        TC_ItemChecker:Debug("Source has no itemID")
        return false, nil 
    end
    
    TC_ItemChecker:Debug(string.format("Processing source itemID: %d, sourceType: %d", source.itemID, source.sourceType or -1))
    
    local sClassID, sSubClassID = GetItemClassAndSubClass(source.itemID)
    TC_ItemChecker:Debug(string.format("Processing source itemID: %d, ClassID: %d, SubClassID: %d", source.itemID, sClassID, sSubClassID))
    
    if sClassID ~= itemClassID then 
        TC_ItemChecker:Debug("Class ID mismatch")
        return false, nil 
    end
    
    if source.sourceID == hoveredSourceID then 
        TC_ItemChecker:Debug("Same source, skipping")
        return false, nil 
    end
    
    if itemClassID == 4 and armorSlotsThatRequireAllowedCheck[itemEquipLoc] then
        TC_ItemChecker:Debug(string.format("Checking armor type. Required: %d, Found: %d", allowedType, sSubClassID))
        if sSubClassID ~= allowedType then 
            TC_ItemChecker:Debug("Wrong armor type")
            return false, nil 
        end
    end
    
    if source.isCollected then
        TC_ItemChecker:Debug("Source is collected")
        return true, nil
    else
        local name, _, quality = GetItemInfo(source.itemID)
        TC_ItemChecker:Debug(string.format("Source not collected. Name: %s", name or "nil"))
        if name then
            -- Include itemID and sourceType in the return
            return false, {
                name = name,
                quality = quality,
                itemID = source.itemID,
                sourceType = source.sourceType,
                sourceInfo = source.sourceInfo  -- Add this to see more details
            }
        end
        return false, nil
    end
end

local function CollectSources(sources, hoveredSourceID, allowedType, itemClassID, itemEquipLoc)
    local modelCollected = false
    local altSources = {}
    
    TC_ItemChecker:Debug(string.format("Processing %d sources", #sources))
    for _, source in pairs(sources) do
        local isCollected, altSource = ProcessSource(source, hoveredSourceID, allowedType, itemClassID, itemEquipLoc)
        if isCollected then
            modelCollected = true
        elseif altSource then
            table.insert(altSources, altSource)
        end
    end
    
    TC_ItemChecker:Debug(string.format("Found %d alternatives", #altSources))
    return modelCollected, altSources
end

-- Build alternative sources using MoP-compatible API
local function BuildAlternativeSources(appearanceID, hoveredSourceID)
    if not appearanceID or not C_TransmogCollection or not C_TransmogCollection.GetAllAppearanceSources then
        return nil
    end
    local sourceIDs = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
    if not sourceIDs or #sourceIDs == 0 then return nil end

    local alternatives = {}
    for _, sid in ipairs(sourceIDs) do
        if sid ~= hoveredSourceID then
            local info = C_TransmogCollection.GetSourceInfo and C_TransmogCollection.GetSourceInfo(sid)
            if info and info.itemID then
                local name = info.name
                if not name then
                    name = (GetItemInfo(info.itemID))
                end
                table.insert(alternatives, {
                    name = name or ("item:" .. tostring(info.itemID)),
                    quality = info.quality,
                    itemID = info.itemID,
                    sourceType = info.sourceType or info.categoryID, -- try sourceType; fallback to categoryID
                })
            end
        end
    end

    if #alternatives == 0 then return nil end
    return alternatives
end

function TC_ItemChecker:GetTransmogStatus(itemLink)
    -- Basic validation
    if not itemLink then 
        TC_ItemChecker:Debug(string.format("No item link"))
        return nil 
    end

    -- Check if item belongs to valid equipment slot
    local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
    if not itemEquipLoc or not validEquipLocs[itemEquipLoc] then
        TC_ItemChecker:Debug(string.format("No valid equipment slot"))
        return nil  -- Only return nil for invalid equipment slots
    end
    

    -- Get item class info
    local itemClassID, itemSubClassID = GetItemClassAndSubClass(itemLink)
    if itemClassID ~= 4 and itemClassID ~= 2 then -- Not armor or weapon
        TC_ItemChecker:Debug(string.format("Not armor or weapon"))
        return STATUS_NO_INFO_YET, false  -- Neutral for non-armor/weapon
    end

    -- Check if armor type is allowed for player
    local allowedType = GetAllowedArmorForPlayer()
    local isAllowedArmor = true
    if itemClassID == 4 and armorSlotsThatRequireAllowedCheck[itemEquipLoc] then
        isAllowedArmor = (itemSubClassID == allowedType)
        TC_ItemChecker:Debug(string.format("Armor type is allowed: %d", isAllowedArmor))
    end

    -- Get appearance info
    local appearanceID, hoveredSourceID = C_TransmogCollection.GetItemInfo(itemLink)

    if not hoveredSourceID then
        TC_ItemChecker:Debug(string.format("No hovered source ID"))
        -- Attempt to request item data to load if available
        local itemID = select(1, GetItemInfoInstant(itemLink))
        if itemID and C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        end
        return STATUS_NO_INFO_YET, false
    end

    -- Check if exact appearance is collected
    local exactCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(hoveredSourceID)

    -- Appearance-level collection without relying on enumerating sources
    local modelCollected = false
    if appearanceID and C_TransmogCollection.PlayerHasTransmog then
        modelCollected = C_TransmogCollection.PlayerHasTransmog(appearanceID) and true or false
    end

    local altSources = BuildAlternativeSources(appearanceID, hoveredSourceID)

    -- Return appropriate status
    if exactCollected then
        TC_ItemChecker:Debug(string.format("Exact collected"))
        return STATUS_EXACT_COLLECTED, true, altSources -- EXACT COLLECTED
    elseif modelCollected then
        TC_ItemChecker:Debug(string.format("Model collected"))
        return STATUS_MODEL_COLLECTED, true, altSources -- MODEL COLLECTED
    elseif IsPlayerEligibleForItem(hoveredSourceID, itemClassID, itemEquipLoc, itemSubClassID) then
        TC_ItemChecker:Debug(string.format("Allowed armor"))
        return STATUS_MODEL_NOT_COLLECTED, true, altSources -- MODEL NOT COLLECTED
    end

    if not IsPlayerEligibleForItem(hoveredSourceID, itemClassID, itemEquipLoc, itemSubClassID) then
        TC_ItemChecker:Debug("Not collectable by class")
        return STATUS_NOT_COLLECTABLE_BY_CLASS, false
    end

    TC_ItemChecker:Debug(string.format("No definitive info; neutral state"))
    -- Switch to neutral state if we reached here without definitive info
    return STATUS_NO_INFO_YET, false

end

print("TC_ItemChecker: Module loaded.") 