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

-- Status mapping (keep in sync with TC_ItemChecker)
local STATUS_EXACT_COLLECTED = 1
local STATUS_MODEL_COLLECTED = 2
local STATUS_MODEL_NOT_COLLECTED = 3
local STATUS_NOT_COLLECTABLE_BY_CLASS = 4
local STATUS_INVALID_CLASS_TO_COLLECT = 5
local STATUS_NO_INFO_YET = 6

GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        local status, eligible, altSources = TC_ItemChecker:GetTransmogStatus(itemLink)

        if status then
            TC_ItemChecker:Debug('Checking status %d', status)
            if status == STATUS_EXACT_COLLECTED then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFF00FF00EXACT COLLECTED|r")
            elseif status == STATUS_MODEL_COLLECTED then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFF00FF00MODEL COLLECTED|r")
            elseif status == STATUS_MODEL_NOT_COLLECTED then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFFFF7F00MODEL NOT COLLECTED|r")
            elseif status == STATUS_NOT_COLLECTABLE_BY_CLASS then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFFFF7F00NOT COLLECTABLE BY CLASS|r")
            elseif status == STATUS_INVALID_CLASS_TO_COLLECT then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFFFF0000INVALID CLASS TO COLLECT|r")
            elseif status == STATUS_NO_INFO_YET then
                tooltip:AddLine("|c" .. TC_PREFIX_COLOR .. "TC:|r |cFFAAAAAANo transmog info yet|r")
            end

            TC_ItemChecker:Debug('Showing alternatives %s', altSources)

            -- Show alternative sources for statuses 1, 2, 3, and 4
            if (status == STATUS_EXACT_COLLECTED or status == STATUS_MODEL_COLLECTED or status == STATUS_MODEL_NOT_COLLECTED or status == STATUS_NOT_COLLECTABLE_BY_CLASS) and altSources then
                for _, alt in ipairs(altSources) do
                    local altHex = select(4, GetItemQualityColor(alt.quality)) or "FFFFFFFF"
                    local sourceType = SOURCE_TYPES[alt.sourceType]
                    if sourceType then
                        tooltip:AddLine(string.format("|c%sALT:|r |c%s%s|r |c%s[%d] (%s)|r", 
                            TC_PREFIX_COLOR,
                            altHex,
                            alt.name,
                            TC_PREFIX_COLOR,
                            alt.itemID,
                            sourceType
                        ))
                    else
                        tooltip:AddLine(string.format("|c%sALT:|r |c%s%s|r |c%s[%d]|r", 
                            TC_PREFIX_COLOR,
                            altHex,
                            alt.name,
                            TC_PREFIX_COLOR,
                            alt.itemID
                        ))
                    end
                end
            end
            
            tooltip:Show()
        end
    end
end)

print("TC_Tooltip: Module loaded.") 