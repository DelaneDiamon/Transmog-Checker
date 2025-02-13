-- This module adds extra transmog info to tooltips.
if not TC_ItemChecker then
    print("TC_Tooltip: Missing dependency TC_ItemChecker!")
    return
end

GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        -- Retrieve basic item info.
        local name, link, rarity, level, reqLevel, itemType, subType, stackCount, equipLoc = GetItemInfo(itemLink)
        local status, eligible, altSources = TC_ItemChecker:GetTransmogStatus(itemLink)
        
        if status then
            if status == 1 then
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFF00FF00EXACT COLLECTED|r")
            elseif status == 2 then
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFF00FF00MODEL COLLECTED|r")
            elseif status == 3 then
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFFFF7F00MODEL NOT COLLECTED|r")
            elseif status == 4 then
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFFFF7F00NOT COLLECTABLE BY CLASS, ALTERNATIVES:|r")
                -- List each alternative allowed source.
                for _, alt in ipairs(altSources or {}) do
                    local altHex = select(4, GetItemQualityColor(alt.quality)) or "FFFFFFFF"
                    -- Prepend |c to the hex string since it doesn't include it by default.
                    tooltip:AddLine("|cFF9D9D9DTC:|r " .. "|c" .. altHex .. alt.name .. "|r")
                end
            elseif status == 5 then
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFFFF0000INVALID CLASS TO COLLECT|r")
            end
            tooltip:Show()
        end
    end
end)

print("TC_Tooltip: Module loaded.") 