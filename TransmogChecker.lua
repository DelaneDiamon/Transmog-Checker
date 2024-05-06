local f = CreateFrame("Frame")
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
f:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)
f:RegisterEvent("ADDON_LOADED")

function f:ADDON_LOADED(addonName)
    if addonName ~= "TransmogChecker" then return end
    self:UnregisterEvent("ADDON_LOADED")

    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local _, link = tooltip:GetItem()

        if link then
            local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, _, _, _, bindType = GetItemInfo(link)

            if bindType > 0 and validEquipLocs[itemEquipLoc] then
                local appearanceID, sourceID  = C_TransmogCollection.GetItemInfo(link)

                local isExactKnown = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
                local appearanceCollected = false
                local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
                
                if sources then
                    if appearanceCollected == false then
                        for i, source in pairs(sources) do
                            if C_TransmogCollection.PlayerHasTransmog(source.itemID, source.itemAppearanceModID) then
                                appearanceCollected = true
                                break
                            end
                        end
                    end
                else 
                    appearanceCollected = nil
                end

                if appearanceCollected then
                    tooltip:AddLine("|cFF00FF00Item Model: COLLECTED|r")
                elseif appearanceCollected == nil then
                    tooltip:AddLine("|cFFFF0000Item Model: CLASS NOT ELIGIBLE TO COLLECT|r")
                else 
                    tooltip:AddLine("|cFFFF7F00Item Model: NOT COLLECTED|r")
                end

                if isExactKnown then
                    tooltip:AddLine("|cFF00FF00Exact Item Source: COLLECTED|r")
                    appearanceCollected = true
                else
                    tooltip:AddLine("|cFFFF7F00Exact Item Source: NOT COLLECTED|r")
                end

                tooltip:Show()
            end
        end
    end)
end
