local f = CreateFrame("Frame")
local validEquipLocs = {
				["INVTYPE_HEAD"] = true,
                ["INVTYPE_SHOULDER"] = true,
                ["INVTYPE_BODY"] = true,    -- shirts
                ["INVTYPE_CHEST"] = true,
                ["INVTYPE_ROBE"] = true,   -- for chest items with long models
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
                ["INVTYPE_HOLDABLE"] = true,   -- off-hand frills
                ["INVTYPE_TABARD"] = true
    }
f:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)
f:RegisterEvent("ADDON_LOADED")

function f:ADDON_LOADED(addonName)
    if addonName ~= "ItemChecker" then return end
    self:UnregisterEvent("ADDON_LOADED")

    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local _, link = tooltip:GetItem()
        tooltip.ItemChecker_link = link 

		local link = tooltip.ItemChecker_link

        if link then
			local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, _, _, _, bindType = GetItemInfo(link)

            if bindType > 0 and validEquipLocs[itemEquipLoc] then

				local sourceID, appearanceID = C_TransmogCollection.GetItemInfo(link)
				local isKnown = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(appearanceID)
				if isKnown then
					tooltip:AddLine("|cFF00FF00Transmog: COLLECTED|r")
				else
					tooltip:AddLine("|cFFFF0000Transmog NOT COLLECTED|r")
				end

				tooltip:Show()
			end
        end
		
    end)
end
