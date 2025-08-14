TC_AH_Old = TC_AH_Old or {}

function TC_AH_Old:Init()
    if not AuctionFrame then
        print("TC_AH_Old: AuctionFrame not found. Aborting old AH init.")
        return
    end

    if not AuctionFrameBrowse_Update then
        print("TC_AH_Old: AuctionFrameBrowse_Update not found!")
        return
    end

    local applyTransmogFilter = false 
    local orig_AuctionFrameBrowse_Update = AuctionFrameBrowse_Update

    local function UpdateButtonOverlay(button, index)
        if not button then return end
        
        if not button.transmogOverlay then
            button.transmogOverlay = button:CreateTexture(nil, "OVERLAY")
            button.transmogOverlay:SetAllPoints(true)
        end
        
        local itemLink = GetAuctionItemLink("list", index)
        if itemLink then
            local status, eligible, altSources = TC_ItemChecker:GetTransmogStatus(itemLink)
            if status == TC.STATUS.EXACT_COLLECTED or status == TC.STATUS.MODEL_COLLECTED then  -- collected
                button.transmogOverlay:SetColorTexture(unpack(TC.UI_COLORS.OLD_AH.OVERLAY_COLLECTED))
                button.transmogOverlay:Show()
            elseif status == TC.STATUS.NOT_COLLECTABLE_BY_CLASS then  -- Class invalid
                button.transmogOverlay:SetColorTexture(unpack(TC.UI_COLORS.OLD_AH.OVERLAY_INVALID))
                button.transmogOverlay:Show()
            else
                button.transmogOverlay:Hide()
            end
        else
            button.transmogOverlay:Hide()
        end
    end

    local function CleanupOverlays()
        for i = 1, NUM_BROWSE_TO_DISPLAY do
            local button = _G["BrowseButton" .. i .. "Item"]
            if button and button.transmogOverlay then
                button.transmogOverlay:Hide()
                button.transmogOverlay:SetParent(nil)
                button.transmogOverlay = nil
            end
        end
    end

    local function NewAuctionFrameBrowse_Update()
        orig_AuctionFrameBrowse_Update()
        
        if applyTransmogFilter then 
            local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame)
            for i = 1, NUM_BROWSE_TO_DISPLAY do
                local button = _G["BrowseButton" .. i .. "Item"]
                UpdateButtonOverlay(button, offset + i)
            end
        else
            CleanupOverlays()
        end
    end

    AuctionFrameBrowse_Update = NewAuctionFrameBrowse_Update
    AuctionFrame:HookScript("OnHide", CleanupOverlays)

    function TC_AH_Old:ToggleTransmogFilter()
        applyTransmogFilter = not applyTransmogFilter
        NewAuctionFrameBrowse_Update()
    end

    local toggleButton = CreateFrame("CheckButton", nil, AuctionFrame, "ChatConfigCheckButtonTemplate")
    toggleButton:SetSize(TC.OLD_AH_TOGGLE.WIDTH, TC.OLD_AH_TOGGLE.HEIGHT)
    toggleButton:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", TC.OLD_AH_TOGGLE.POINT.x, TC.OLD_AH_TOGGLE.POINT.y)
    toggleButton.tooltip = TC.OLD_AH_TOGGLE.TOOLTIP

    local checkboxText = toggleButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    checkboxText:SetPoint("LEFT", toggleButton, "RIGHT", 5, 0)
    checkboxText:SetText(TC.OLD_AH_TOGGLE.LABEL)
    checkboxText:SetTextColor(unpack(TC.UI_COLORS.OLD_AH.LABEL_COLOR))

    AuctionFrame:HookScript("OnUpdate", function()
        if PanelTemplates_GetSelectedTab(AuctionFrame) == 1 then
            toggleButton:Show()
        else
            toggleButton:Hide()
        end
    end)

    toggleButton:SetScript("OnClick", function(self)
        applyTransmogFilter = not applyTransmogFilter
        NewAuctionFrameBrowse_Update()
    end)

    print("TC_AH_Old: Legacy Auction House filter logic loaded.")
end

print("TC_AH_Old: Module loaded.") 