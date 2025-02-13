-- This module adds extra transmog info to tooltips.
if not TC_ItemChecker then
    print("TC_Tooltip: Missing dependency TC_ItemChecker!")
    return
end

local tooltipFrame = CreateFrame("Frame")

GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        local collected, isExact = TC_ItemChecker:IsTransmogCollected(itemLink)
        if isExact then
            tooltip:AddLine("|cFF9D9D9DTC:|r |cFF00FF00EXACT COLLECTED|r")
        else
            if collected then
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFF00FF00MODEL COLLECTED|r")
            elseif collected == nil then
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFFFF0000INVALID CLASS TO COLLECT|r")
            else
                tooltip:AddLine("|cFF9D9D9DTC:|r |cFFFF7F00MODEL NOT COLLECTED|r")
            end
        end
        tooltip:Show()
    end
end)

print("TC_Tooltip: Module loaded.") 