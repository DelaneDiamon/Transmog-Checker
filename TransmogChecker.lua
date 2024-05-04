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

                print("appearanceID", appearanceID)
                print("sourceID", sourceID)


                local isKnown = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)

                print ("isKnown", isKnown)
                if isKnown then
                    tooltip:AddLine("|cFF00FF00Transmog Source: COLLECTED|r")
                else
                    tooltip:AddLine("|cFFFF0000Transmog Source: NOT COLLECTED|r")
                end

                local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
                local appearanceCollected = false
                if sources then
                    for i, source in pairs(sources) do
                        if C_TransmogCollection.PlayerHasTransmog(source.itemID, source.itemAppearanceModID) then
                            appearanceCollected = true
                            break
                        end
                    end
                    
                    if appearanceCollected then
                        tooltip:AddLine("|cFF00FF00Appearance: COLLECTED|r")
                    else
                        tooltip:AddLine("|cFFFF0000Appearance: NOT COLLECTED|r")
                    end
                end

                tooltip:Show()
            end
        end
    end)
end
