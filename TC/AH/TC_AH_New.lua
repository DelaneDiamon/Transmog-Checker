TC_AH_New = TC_AH_New or {}

function TC_AH_New:Init()
    if not AuctionHouseFrame or not AuctionHouseFrame.Tabs then
        print("TC_AH_New: AuctionHouseFrame.Tabs not available. Aborting new AH init.")
        return
    end

    -- Create the main frame for the Transmog Collector UI.
    self.collectorFrame = CreateFrame("Frame", "TC_CollectorFrame_New", AuctionHouseFrame)
    self.collectorFrame:SetAllPoints(AuctionHouseFrame)
    self.collectorFrame:Hide()  -- Hide by default

    -- Create a "Search" button inside the collector frame.
    local searchButton = CreateFrame("Button", nil, self.collectorFrame, "UIPanelButtonTemplate")
    searchButton:SetSize(120, 22)
    searchButton:SetPoint("TOPLEFT", self.collectorFrame, "TOPLEFT", 20, -20)
    searchButton:SetText("Search")
    searchButton:SetScript("OnClick", function()
        print("TC_AH_New: Search button clicked!")
        -- New AH-specific search logic can go here.
    end)
    self.searchButton = searchButton

    self:CreateTab()
end

function TC_AH_New:CreateTab()
    local numTabs = #AuctionHouseFrame.Tabs
    local tabID = numTabs + 1

    local tab = CreateFrame("Button", "TC_TransmogTab_New", AuctionHouseFrame, "AuctionHouseFrameTabTemplate")
    tab:SetID(tabID)
    tab:SetText("Transmog")
    tab:SetPoint("LEFT", AuctionHouseFrame.Tabs[numTabs], "RIGHT", -15, 0)

    table.insert(AuctionHouseFrame.Tabs, tab)
    PanelTemplates_SetNumTabs(AuctionHouseFrame, tabID)
    PanelTemplates_EnableTab(AuctionHouseFrame, tabID)

    tab:SetScript("OnClick", function()
        PanelTemplates_SetTab(AuctionHouseFrame, tabID)
        -- Hide Blizzard's default panes if they are shown.
        if AuctionHouseFrame.BrowseResultsFrame and AuctionHouseFrame.BrowseResultsFrame:IsShown() then
            AuctionHouseFrame.BrowseResultsFrame:Hide()
        end
        if AuctionHouseFrame.CategoriesList and AuctionHouseFrame.CategoriesList:IsShown() then
            AuctionHouseFrame.CategoriesList:Hide()
        end
        self.collectorFrame:Show()
    end)

    print("TC_AH_New: Transmog tab created in new AH UI.")
end

print("TC_AH_New: Module loaded.") 