TC = TC or {}
TC_ItemChecker = TC_ItemChecker or {}
TC_ItemChecker.debug = false -- Debug flag, off by default

function TC_ItemChecker:Debug(...)
    if TC_ItemChecker.debug then
        print("|cFF9D9D9DTC Debug:|r", ...)
    end
end

-- Add command to toggle debug mode
SLASH_TC1 = "/tc"
SlashCmdList["TC"] = function(msg)
    if msg == "debug" then
        TC_ItemChecker.debug = not TC_ItemChecker.debug
        print("|cFF9D9D9DTC:|r Debug mode " .. (TC_ItemChecker.debug and "enabled" or "disabled"))
    end
end


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


local function GetAllowedArmorForPlayer()
    local playerClass = select(2, UnitClass("player"))
    local playerLevel = UnitLevel("player")
    local classRule = TC.CLASS_TO_ARMOR[playerClass]
    if type(classRule) == "table" then
        return (playerLevel < TC.CLASS_ARMOR_UPGRADE_LEVEL) and classRule.low or classRule.high
    else
        return classRule
    end
end

-- Determine if the player can collect the given source/item by class rules
local function IsPlayerEligibleForItem(hoveredSourceID, itemClassID, itemEquipLoc, itemSubClassID)
    -- For armor, use strict armor-type rule first. Do not trust source info flags
    -- because playerCanCollect may be false for BoE or not-in-inventory items.
    if itemClassID == TC.ITEM_CLASS.ARMOR and TC.ARMOR_SLOTS_REQUIRE_CHECK[itemEquipLoc] then
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
    
    if itemClassID == 4 and TC.ARMOR_SLOTS_REQUIRE_CHECK[itemEquipLoc] then
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
                local quality = info.quality
                local fetchedName, _, fetchedQuality = GetItemInfo(info.itemID)
                if not name and fetchedName then name = fetchedName end
                if quality == nil and fetchedQuality then quality = fetchedQuality end

                -- If data isn't cached yet, request it and skip showing placeholders
                if not name and C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(info.itemID) then
                    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(info.itemID) end
                else
                    table.insert(alternatives, {
                        name = name or ("item:" .. tostring(info.itemID)),
                        quality = quality,
                        itemID = info.itemID,
                        sourceType = info.sourceType or info.categoryID, -- try sourceType; fallback to categoryID
                    })
                end
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
    if not itemEquipLoc or not TC.VALID_EQUIP_LOCS[itemEquipLoc] then
        TC_ItemChecker:Debug(string.format("No valid equipment slot"))
        return nil  -- Only return nil for invalid equipment slots
    end
    

    -- Get item class info
    local itemClassID, itemSubClassID = GetItemClassAndSubClass(itemLink)
    if itemClassID ~= TC.ITEM_CLASS.ARMOR and itemClassID ~= TC.ITEM_CLASS.WEAPON then -- Not armor or weapon
        TC_ItemChecker:Debug(string.format("Not armor or weapon"))
        return TC.STATUS.NO_INFO_YET, false  -- Neutral for non-armor/weapon
    end

    -- Check if armor type is allowed for player
    local allowedType = GetAllowedArmorForPlayer()
    local isAllowedArmor = true
    if itemClassID == TC.ITEM_CLASS.ARMOR and TC.ARMOR_SLOTS_REQUIRE_CHECK[itemEquipLoc] then
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
        return TC.STATUS.NO_INFO_YET, false
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
        return TC.STATUS.EXACT_COLLECTED, true, altSources -- EXACT COLLECTED
    elseif modelCollected then
        TC_ItemChecker:Debug(string.format("Model collected"))
        return TC.STATUS.MODEL_COLLECTED, true, altSources -- MODEL COLLECTED
    elseif IsPlayerEligibleForItem(hoveredSourceID, itemClassID, itemEquipLoc, itemSubClassID) then
        TC_ItemChecker:Debug(string.format("Allowed armor"))
        return TC.STATUS.MODEL_NOT_COLLECTED, true, altSources -- MODEL NOT COLLECTED
    end

    if not IsPlayerEligibleForItem(hoveredSourceID, itemClassID, itemEquipLoc, itemSubClassID) then
        TC_ItemChecker:Debug("Not collectable by class")
        return TC.STATUS.NOT_COLLECTABLE_BY_CLASS, false
    end

    TC_ItemChecker:Debug(string.format("No definitive info; neutral state"))
    -- Switch to neutral state if we reached here without definitive info
    return TC.STATUS.NO_INFO_YET, false

end

print("TC_ItemChecker: Module loaded.") 
