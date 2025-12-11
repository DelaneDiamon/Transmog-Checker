if not TC_ItemChecker then
    print("TC_Tooltip: Missing dependency TC_ItemChecker!")
    return
end
GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        local status, eligible, altSources = TC_ItemChecker:GetTransmogStatus(itemLink)

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
            elseif status == TC.STATUS.NO_INFO_YET then
                tooltip:AddLine("|c" .. TC.COLORS.PREFIX .. "TC:|r |c" .. (TC.COLORS.STATUS.NO_INFO) .. "No transmog info yet|r")
            end

            TC_ItemChecker:Debug('Showing alternatives %s', altSources)

            -- Show alternative sources for statuses 1, 2, 3, and 4
            if (status == TC.STATUS.EXACT_COLLECTED or status == TC.STATUS.MODEL_COLLECTED or status == TC.STATUS.MODEL_NOT_COLLECTED or status == TC.STATUS.NOT_COLLECTABLE_BY_CLASS) and altSources then
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
            
            tooltip:Show()
        end
    end
end)

print("TC_Tooltip: Module loaded.") 
