if not TC_ItemChecker then
    print("TC_Tooltip: Missing dependency TC_ItemChecker!")
    return
end

local hideStrings
local function StripBlizzardNotCollected(tooltip)
    if not (TC.Config and TC.Config.filterBlizzNotCollectedLine) then return end
    if not hideStrings then
        hideStrings = {}
        local candidates = {
            _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN,
            _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNCOLLECTED,
            _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_NOT_COLLECTED,
            _G.TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE,
        }
        for _, s in ipairs(candidates) do
            if type(s) == "string" and s ~= "" then
                hideStrings[s] = true
            end
        end
    end

    local name = tooltip:GetName()
    for i = 1, tooltip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and hideStrings[text] then
                line:SetText("")
                line:Hide()
            end
        end
    end
end

GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        local status, eligible, altSources, requiredLevel = TC_ItemChecker:GetTransmogStatus(itemLink)

        if status then
            TC_ItemChecker:Debug('Checking status %d', status)
            if status == TC.STATUS.EXACT_COLLECTED then
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.EXACT) .. "EXACT COLLECTED|r")
            elseif status == TC.STATUS.MODEL_COLLECTED then
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.MODEL) .. "MODEL COLLECTED|r")
            elseif status == TC.STATUS.MODEL_NOT_COLLECTED then
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.MODEL_NOT) .. "MODEL NOT COLLECTED|r")
            elseif status == TC.STATUS.NOT_COLLECTABLE_BY_CLASS then
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.NOT_COLLECTABLE) .. "NOT COLLECTABLE BY CLASS|r")
            elseif status == TC.STATUS.LEVEL_TOO_LOW then
                local reqText = requiredLevel and tostring(requiredLevel) or "?"
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.MODEL_NOT) .. "MODEL NOT COLLECTED|r")
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.LEVEL_LOW) .. "REQUIRES LEVEL " .. reqText .. " TO COLLECT|r")
            elseif status == TC.STATUS.NO_INFO_YET then
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.NO_INFO) .. "No transmog info yet|r")
            end

            TC_ItemChecker:Debug('Showing alternatives %s', altSources)

            local showAlts = altSources
                and (status == TC.STATUS.EXACT_COLLECTED
                    or status == TC.STATUS.MODEL_COLLECTED
                    or status == TC.STATUS.MODEL_NOT_COLLECTED
                    or status == TC.STATUS.NOT_COLLECTABLE_BY_CLASS
                    or status == TC.STATUS.LEVEL_TOO_LOW)

            if showAlts and TC.Config and TC.Config.hideCollectedAlts
                and (status == TC.STATUS.EXACT_COLLECTED or status == TC.STATUS.MODEL_COLLECTED) then
                showAlts = false
            end

            if showAlts then
                for _, alt in ipairs(altSources) do
                    -- Defensive: try to resolve quality via API if missing to keep color accurate for new items
                    local altQuality = alt.quality
                    if not altQuality and alt.itemID then
                        local _, _, fetchedQuality = GetItemInfo(alt.itemID)
                        if fetchedQuality then
                            altQuality = fetchedQuality
                        elseif C_Item and C_Item.RequestLoadItemDataByID then
                            C_Item.RequestLoadItemDataByID(alt.itemID)
                        end
                    end

                    local altHex = "FFFFFFFF"
                    if altQuality ~= nil then
                        local _, _, _, qHex = GetItemQualityColor(altQuality)
                        if qHex then altHex = qHex end
                    end
                    local sourceType = TC.SOURCE_TYPES[alt.sourceType]
                    if sourceType then
                        tooltip:AddLine(string.format("|c%sALT:|r |c%s%s|r |c%s[%d] (%s)|r", 
                            TC.COLORS.PREFIX,
                            altHex,
                            alt.name,
                            TC.COLORS.PREFIX,
                            alt.itemID,
                            sourceType
                        ))
                    else
                        tooltip:AddLine(string.format("|c%sALT:|r |c%s%s|r |c%s[%d]|r", 
                            TC.COLORS.PREFIX,
                            altHex,
                            alt.name,
                            TC.COLORS.PREFIX,
                            alt.itemID
                        ))
                    end
                end
            end
            
            StripBlizzardNotCollected(tooltip)
            tooltip:Show()
        end
    end
end)

print("TC_Tooltip: Module loaded.") 
