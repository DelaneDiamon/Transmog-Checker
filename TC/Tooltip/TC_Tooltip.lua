-- This module adds extra transmog info to tooltips.
if not TC_ItemChecker then
    print("TC_Tooltip: Missing dependency TC_ItemChecker!")
    return
end

local TC_PREFIX_COLOR = "FF9D9D9D"

-- Source type descriptions
local SOURCE_TYPES = {
    [1] = "Boss Drop",
    [2] = "Quest",
    [3] = "Vendor",
    [4] = "World Drop",
    [5] = "Achievement",
    [6] = "Profession",
}

GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        local status, eligible, altSources = TC_ItemChecker:GetTransmogStatus(itemLink)

        if status then
            TC_ItemChecker:Debug('Checking status %d', status)
            if status == 1 then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFF00FF00EXACT COLLECTED|r")
            elseif status == 2 then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFF00FF00MODEL COLLECTED|r")
            elseif status == 3 then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFFFF7F00MODEL NOT COLLECTED|r")
            elseif status == 4 then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFFFF7F00NOT COLLECTABLE BY CLASS|r")
            elseif status == 5 then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFFFF0000INVALID CLASS TO COLLECT|r")
            end

            TC_ItemChecker:Debug('Showing alternatives %s', altSources)

            -- Show alternative sources for statuses 1, 2, 3, and 4
            if (status == 1 or status == 2 or status == 3 or status == 4) and altSources then
                for _, alt in ipairs(altSources) do
                    local altHex = select(4, GetItemQualityColor(alt.quality)) or "FFFFFFFF"
                    local sourceType = SOURCE_TYPES[alt.sourceType] or "Unknown"
                    tooltip:AddLine(string.format("|c%sALT:|r |c%s%s|r |c%s[%d] (%s)|r", 
                        TC_PREFIX_COLOR,
                        altHex,
                        alt.name,
                        TC_PREFIX_COLOR,
                        alt.itemID,
                        sourceType
                    ))
                end
            end
            
            tooltip:Show()
        end
    end
end)

print("TC_Tooltip: Module loaded.") 