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

    local function NewAuctionFrameBrowse_Update()
        -- Call original update first so that the browse buttons are refreshed.
        orig_AuctionFrameBrowse_Update()

        local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame)
        
        if applyTransmogFilter then 
            for i = 1, NUM_BROWSE_TO_DISPLAY do
                local index = offset + i
                local button = _G["BrowseButton" .. i .. "Item"]
                if button then
                    if not button.transmogOverlay then
                        button.transmogOverlay = button:CreateTexture(nil, "OVERLAY")
                        button.transmogOverlay:SetAllPoints(true)
                    end

                    local itemLink = GetAuctionItemLink("list", index)
                    if itemLink then
                        -- Use the shared function from TC_ItemChecker instead of duplicating logic.
                        local appearanceCollected, isExactKnown = TC_ItemChecker:IsTransmogCollected(itemLink)
                        if appearanceCollected or isExactKnown then
                            button.transmogOverlay:SetColorTexture(0, 1, 0, 0.3) -- Green for collected
                        elseif appearanceCollected == nil then
                            button.transmogOverlay:SetColorTexture(1, 0, 0, 0.3) -- Red if not eligible
                        else
                            button.transmogOverlay:SetColorTexture(0, 0, 0, 0)   -- Transparent for uncollected
                        end
                    end
                end
            end
        else 
            -- Remove (or hide) the highlight when the filter is off.
            for i = 1, NUM_BROWSE_TO_DISPLAY do
                local button = _G["BrowseButton" .. i .. "Item"]
                if button and button.transmogOverlay then
                    button.transmogOverlay:SetColorTexture(0, 0, 0, 0)
                end
            end
        end
    end

    -- Override the browse update function with our custom version.
    AuctionFrameBrowse_Update = NewAuctionFrameBrowse_Update

    -- Create the checkbox (using Blizzard's ChatConfigCheckButtonTemplate).
    local toggleButton = CreateFrame("CheckButton", nil, AuctionFrame, "ChatConfigCheckButtonTemplate")
    toggleButton:SetSize(24, 24)
    toggleButton:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 540, -36)
    toggleButton.tooltip = "Hide items that are either already collected or not eligible for transmog."

    local checkboxText = toggleButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    checkboxText:SetPoint("LEFT", toggleButton, "RIGHT", 5, 0)
    checkboxText:SetText("Not collected for transmog")
    checkboxText:SetTextColor(1, 0, 0, 1)

    -- Show the checkbox only when the "Browse" tab is selected.
    AuctionFrame:HookScript("OnUpdate", function()
        if PanelTemplates_GetSelectedTab(AuctionFrame) == 1 then
            toggleButton:Show()
        else
            toggleButton:Hide()
        end
    end)

    -- Toggle the filtering flag when the checkbox is clicked.
    toggleButton:SetScript("OnClick", function(self)
        applyTransmogFilter = not applyTransmogFilter
        AuctionFrameBrowse_Update()
    end)

    print("TC_AH_Old: Legacy Auction House filter logic loaded.")
end

print("TC_AH_Old: Module loaded.") 