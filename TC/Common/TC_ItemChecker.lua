TC_ItemChecker = TC_ItemChecker or {}

local validEquipLocs = {
    ["INVTYPE_HEAD"] = true,
    ["INVTYPE_SHOULDER"] = true,
    ["INVTYPE_BODY"] = true,
    ["INVTYPE_CHEST"] = true,
    ["INVTYPE_ROBE"] = true,
    ["INVTYPE_WAIST"] = true,
    ["INVTYPE_LEGS"] = true,
    ["INVTYPE_FEET"] = true,
    ["INVTYPE_WRIST"] = true,
    ["INVTYPE_HAND"] = true,
    ["INVTYPE_CLOAK"] = true,
    ["INVTYPE_WEAPON"] = true,
    ["INVTYPE_SHIELD"] = true,
    ["INVTYPE_2HWEAPON"] = true,
    ["INVTYPE_WEAPONMAINHAND"] = true,
    ["INVTYPE_WEAPONOFFHAND"] = true,
    ["INVTYPE_HOLDABLE"] = true,
    ["INVTYPE_TABARD"] = true,
    ["INVTYPE_RANGED"] = true, 
    ["INVTYPE_RANGEDRIGHT"] = true,
}

function TC_ItemChecker:IsTransmogCollected(itemLink)
    if not itemLink then
        return nil, nil
    end

    local _, _, itemRarity, _, _, _, _, _, itemEquipLoc, _, _, _, _, _, bindType = GetItemInfo(itemLink)
    local isExactKnown = nil

    if bindType and bindType > 0 and itemRarity and itemRarity > 1 and validEquipLocs[itemEquipLoc] then
        local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
        if appearanceID and sourceID then
            isExactKnown = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
            local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
            if sources then
                for _, source in pairs(sources) do
                    if source.isCollected then
                        return true, isExactKnown
                    end
                end
                return false, isExactKnown
            end
        end
    end

    return nil, isExactKnown
end

print("TC_ItemChecker: Module loaded.") 