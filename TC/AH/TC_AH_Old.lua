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
            if status == 1 or status == 2 then  -- Model or exact is collected: bright green
                button.transmogOverlay:SetColorTexture(0, 1, 0, 0.3)
                button.transmogOverlay:Show()
            elseif status == 4 or status == 5 then  -- Class invalid: red
                button.transmogOverlay:SetColorTexture(1, 0, 0, 0.3)
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
    toggleButton:SetSize(24, 24)
    toggleButton:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 540, -36)
    toggleButton.tooltip = "Hide items that are either already collected or not eligible for transmog."

    local checkboxText = toggleButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    checkboxText:SetPoint("LEFT", toggleButton, "RIGHT", 5, 0)
    checkboxText:SetText("Not collected for transmog")
    checkboxText:SetTextColor(1, 0, 0, 1)

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