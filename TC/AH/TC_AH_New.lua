TC_AH_New = TC_AH_New or {}

function TC_AH_New:Init()
    if not AuctionHouseFrame or not AuctionHouseFrame.Tabs then
        print("TC_AH_New: AuctionHouseFrame.Tabs not available. Aborting new AH init.")
        return
    end

    -- Create our main collector frame
    self.collectorFrame = CreateFrame("Frame", "TC_CollectorFrame_New", AuctionHouseFrame)
    self.collectorFrame:SetAllPoints(AuctionHouseFrame)
    self.collectorFrame:Hide()

    -- Create our custom UI elements
    self:CreateSearchBar()
    self:CreateEquipmentSlotFilters()
    self:CreateAppearanceGrid()
    self:CreateTab()
end

function TC_AH_New:CreateSearchBar()
    -- Create search bar
    self.searchBox = CreateFrame("EditBox", nil, self.collectorFrame, "SearchBoxTemplate")
    self.searchBox:SetSize(250, 25)
    -- Center the search box horizontally and place it near the top
    self.searchBox:SetPoint("TOP", self.collectorFrame, "TOP", -45, -35)  -- -45 to account for the button width
    self.searchBox:SetAutoFocus(false)

    -- Create search button
    self.searchButton = CreateFrame("Button", nil, self.collectorFrame, "UIPanelButtonTemplate")
    self.searchButton:SetSize(80, 25)
    self.searchButton:SetPoint("LEFT", self.searchBox, "RIGHT", 5, 0)
    self.searchButton:SetText("Search")
    self.searchButton:SetScript("OnClick", function()
        local searchText = self.searchBox:GetText()
        print("TC_AH_New: Search for:", searchText)
        -- Search logic will go here
    end)
end

function TC_AH_New:CreateEquipmentSlotFilters()
    -- Create a container frame for the slot filters
    self.filterFrame = CreateFrame("Frame", nil, self.collectorFrame)
    self.filterFrame:SetSize(600, 50)
    self.filterFrame:SetPoint("TOP", self.searchBox, "BOTTOM", 0, -20)

    -- Define equipment slots and their icons
    local slots = {
        { id = "HEAD", icon = 133071 },        -- inv_helmet_04 (T-visor plate helmet)
        { id = "SHOULDER", icon = 135049 },    -- inv_shoulder_01
        { id = "CHEST", icon = 132737 },       -- inv_chest_plate_01
        { id = "WAIST", icon = 132510 },       -- inv_belt_01
        { id = "LEGS", icon = 132624 },        -- inv_pants_01
        { id = "FEET", icon = 132606 },        -- inv_boots_01
        { id = "WRIST", icon = 132492 },       -- inv_bracer_01
        { id = "HANDS", icon = 132938 },       -- inv_gauntlets_01
        { id = "BACK", icon = 133762 },        -- inv_misc_cape_01
        { id = "MAINHAND", icon = 135271 },    -- inv_sword_01
        { id = "OFFHAND", icon = 134950 },     -- inv_shield_01
    }

    -- Create filter buttons
    self.filterButtons = {}
    local buttonSize = 45
    local spacing = 8
    local totalWidth = (#slots * (buttonSize + spacing)) - spacing
    local startX = -totalWidth/2

    for i, slot in ipairs(slots) do
        local button = CreateFrame("Button", nil, self.filterFrame)
        button:SetSize(buttonSize, buttonSize)
        button:SetPoint("LEFT", self.filterFrame, "CENTER", startX + ((i-1) * (buttonSize + spacing)), 0)
        
        -- Dark background
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\UI-Quickslot")
        bg:SetAllPoints()
        bg:SetVertexColor(0.1, 0.1, 0.1, 1)
        
        -- Icon (desaturated by default)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(buttonSize-12, buttonSize-12)
        icon:SetPoint("CENTER")
        icon:SetTexture(slot.icon)
        icon:SetDesaturated(true)
        
        -- White border
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        border:SetBlendMode("ADD")
        border:SetPoint("CENTER")
        border:SetSize(buttonSize+15, buttonSize+15)
        border:SetVertexColor(0.7, 0.7, 0.7, 0.9)

        -- Glow effect for hover and selection
        local glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
        glow:SetTexture("Interface\\Buttons\\CheckButtonGlow")
        glow:SetPoint("CENTER")
        glow:SetSize(buttonSize+20, buttonSize+20)
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(0.4, 0.6, 1, 0.3)  -- Desaturated blue glow
        glow:Hide()

        -- Store references
        button.bg = bg
        button.icon = icon
        button.border = border
        button.glow = glow
        button.slotID = slot.id
        button.selected = false

        -- Mouse events
        button:SetScript("OnEnter", function(self)
            if not self.selected then
                self.icon:SetDesaturated(false)
                self.border:SetVertexColor(1, 1, 1, 1)
                self.glow:Show()
            end
        end)

        button:SetScript("OnLeave", function(self)
            if not self.selected then
                self.icon:SetDesaturated(true)
                self.border:SetVertexColor(0.7, 0.7, 0.7, 0.9)
                self.glow:Hide()
            end
        end)

        button:SetScript("OnClick", function(self)
            -- Deselect all buttons
            for _, btn in pairs(TC_AH_New.filterButtons) do
                if btn ~= self then
                    btn.selected = false
                    btn.icon:SetDesaturated(true)
                    btn.border:SetVertexColor(0.7, 0.7, 0.7, 0.9)
                    btn.glow:Hide()
                    btn.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
                end
            end
            
            -- Select this button
            self.selected = true
            self.icon:SetDesaturated(false)
            self.border:SetVertexColor(1, 0.8, 0, 1)
            self.glow:SetVertexColor(1, 0.8, 0, 0.4)
            self.glow:Show()
            self.bg:SetVertexColor(0.3, 0.3, 0.3, 1)
            
            TC_AH_New:FilterBySlot(self.slotID)
        end)

        table.insert(self.filterButtons, button)
    end
end

function TC_AH_New:CreateAppearanceGrid()
    -- Create the scroll frame
    self.scrollFrame = CreateFrame("ScrollFrame", nil, self.collectorFrame, "ScrollFrameTemplate")
    self.scrollFrame:SetPoint("TOPLEFT", self.filterFrame, "BOTTOMLEFT", 10, -10)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.collectorFrame, "BOTTOMRIGHT", -30, 10)

    -- Create the content frame
    self.gridFrame = CreateFrame("Frame", nil, self.scrollFrame)
    self.gridFrame:SetSize(self.scrollFrame:GetWidth(), 800) -- Height will be adjusted as needed
    self.scrollFrame:SetScrollChild(self.gridFrame)

    -- Initialize empty grid
    self.appearanceCards = {}
end

function TC_AH_New:FilterBySlot(slotID)
    -- Clear existing cards
    for _, card in pairs(self.appearanceCards) do
        card:Hide()
    end
    wipe(self.appearanceCards)

    -- Create appearance cards grid
    local cardSize = 140     -- Reduced from 180 to match collection UI
    local padding = 8        -- Reduced padding for tighter grid
    local cardsPerRow = 4    -- Changed to 4 cards per row to match UI
    
    -- Create test cards
    for i = 1, 16 do  -- 4x4 grid
        local row = math.floor((i-1) / cardsPerRow)
        local col = (i-1) % cardsPerRow
        
        local card = CreateFrame("Frame", nil, self.gridFrame)
        card:SetSize(cardSize, cardSize)
        card:SetPoint("TOPLEFT", self.gridFrame, "TOPLEFT", 
            col * (cardSize + padding) + padding,
            -row * (cardSize + padding) - padding)

        -- Black background
        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 1)

        -- Create model view (placeholder for now)
        local model = CreateFrame("DressUpModel", nil, card)
        model:SetPoint("TOPLEFT", 5, -5)
        model:SetPoint("BOTTOMRIGHT", -5, 5)
        model:SetCustomCamera(1)

        table.insert(self.appearanceCards, card)
    end

    -- Adjust grid frame height
    local rows = math.ceil(#self.appearanceCards / cardsPerRow)
    self.gridFrame:SetHeight(rows * (cardSize + padding) + padding)
end

function TC_AH_New:CreateTab()
    local numTabs = #AuctionHouseFrame.Tabs
    local tabID = numTabs + 1

    -- Create a tab button using the correct template
    local tab = CreateFrame("Button", "TC_TransmogTab_New", AuctionHouseFrame, "AuctionHouseFrameTabTemplate")
    tab:SetID(tabID)
    tab:SetText("Transmog")
    tab:SetPoint("LEFT", AuctionHouseFrame.Tabs[numTabs], "RIGHT", -15, 0)

    -- Add tab to AuctionHouseFrame's tab array
    table.insert(AuctionHouseFrame.Tabs, tab)
    PanelTemplates_SetNumTabs(AuctionHouseFrame, tabID)
    PanelTemplates_EnableTab(AuctionHouseFrame, tabID)

    tab:SetScript("OnClick", function()
        PanelTemplates_SetTab(AuctionHouseFrame, tabID)
        
        -- Hide all known frames that could be visible
        local framesToHide = {
            AuctionHouseFrame.BrowseResultsFrame,
            AuctionHouseFrame.CategoriesList,
            AuctionHouseFrame.SearchBar,
            AuctionHouseFrame.ItemBuyFrame,
            AuctionHouseFrame.ItemSellFrame,
            AuctionHouseFrame.CommoditiesBuyFrame,
            AuctionHouseFrame.CommoditiesSellFrame,
            AuctionHouseFrame.WoWTokenResults,
            AuctionHouseFrame.AuctionsFrame
        }
        
        for _, frame in ipairs(framesToHide) do
            if frame and frame:IsShown() then
                frame:Hide()
            end
        end
        
        -- Show our frame
        self.collectorFrame:Show()
    end)

    print("TC_AH_New: Transmog tab created in new AH UI.")
end

print("TC_AH_New: Module loaded.") 