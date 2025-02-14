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

    -- Register tab visibility handler
    self:RegisterTabEvents()
    
    -- Register cleanup handler for AH close
    AuctionHouseFrame:HookScript("OnHide", function()
        -- Only clean up if we're on our tab
        if AuctionHouseFrame.selectedTab == self.tabID then
            self:ClearAppearanceCards()
        end
    end)
end

function TC_AH_New:RegisterTabEvents()
    if AuctionHouseFrame then
        -- Hook into the SetDisplayMode function which is called when tabs change
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(frame, displayMode)
            -- Check if our elements exist
            if self.filterFrame then
                self.filterFrame:SetShown(frame.selectedTab == self.tabID)
            end
            if self.searchButton then
                self.searchButton:SetShown(frame.selectedTab == self.tabID)
            end
            if self.searchBox then
                self.searchBox:SetShown(frame.selectedTab == self.tabID)
            end
            if self.gridFrame then
                self.gridFrame:SetShown(frame.selectedTab == self.tabID)
            end
            -- Clear the grid when switching away from our tab
            if frame.selectedTab ~= self.tabID then
                self:ClearAppearanceCards()
            end
        end)
    end
end

function TC_AH_New:ClearAppearanceCards()
    if self.appearanceCards then
        for _, card in pairs(self.appearanceCards) do
            if card.model then
                card.model:ClearModel()
            end
            card:Hide()
            card:SetParent(nil)
        end
        wipe(self.appearanceCards)
    end
    
    -- Clear filter selection
    if self.filterButtons then
        for _, btn in pairs(self.filterButtons) do
            btn.selected = false
            btn.icon:SetDesaturated(true)
            btn.border:SetVertexColor(0.7, 0.7, 0.7, 0.9)
            btn.glow:Hide()
            btn.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
        end
    end
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
    self.filterFrame:SetFrameStrata("HIGH")  -- Set filter frame to HIGH strata

    -- Define equipment slots and their icons (updated with standard base icons)
    local slots = {
        { id = "HEAD", icon = 133136 },        -- inv_helmet_01
        { id = "SHOULDER", icon = 135040 },    -- inv_shoulder_01
        { id = "BACK", icon = 133763 },        -- inv_misc_cape_01
        { id = "CHEST", icon = 132644 },       -- inv_chest_01
        { id = "TABARD", icon = 135027 },      -- inv_shirt_01
        { id = "SHIRT", icon = 135022 },       -- inv_shirt_01
        { id = "WRIST", icon = 132602 },       -- inv_bracer_01
        { id = "HANDS", icon = 132939 },       -- inv_gauntlets_01
        { id = "WAIST", icon = 132514 },       -- inv_belt_01
        { id = "LEGS", icon = 134586 },        -- inv_pants_01
        { id = "FEET", icon = 132537 },        -- inv_boots_01
        { id = "MAINHAND", icon = 135274 },    -- inv_sword_01
        { id = "OFFHAND", icon = 134955 },     -- inv_shield_01
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
    -- Create the grid frame
    self.gridFrame = CreateFrame("Frame", nil, self.collectorFrame)
    self.gridFrame:SetPoint("TOPLEFT", self.filterFrame, "BOTTOMLEFT", 10, -10)
    self.gridFrame:SetPoint("BOTTOMRIGHT", self.collectorFrame, "BOTTOMRIGHT", -30, 40)  -- Leave space for pagination
    
    -- Create pagination controls
    self.paginationFrame = CreateFrame("Frame", nil, self.collectorFrame)
    self.paginationFrame:SetSize(200, 30)
    self.paginationFrame:SetPoint("BOTTOM", self.collectorFrame, "BOTTOM", 0, 10)
    
    -- Previous page button
    self.prevButton = CreateFrame("Button", nil, self.paginationFrame, "UIPanelButtonTemplate")
    self.prevButton:SetSize(30, 25)
    self.prevButton:SetPoint("RIGHT", self.paginationFrame, "CENTER", -10, 0)
    self.prevButton:SetText("<")
    self.prevButton:SetScript("OnClick", function() self:ChangePage(-1) end)
    
    -- Next page button
    self.nextButton = CreateFrame("Button", nil, self.paginationFrame, "UIPanelButtonTemplate")
    self.nextButton:SetSize(30, 25)
    self.nextButton:SetPoint("LEFT", self.paginationFrame, "CENTER", 10, 0)
    self.nextButton:SetText(">")
    self.nextButton:SetScript("OnClick", function() self:ChangePage(1) end)
    
    -- Page text
    self.pageText = self.paginationFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.pageText:SetPoint("CENTER", self.paginationFrame, "CENTER", 0, 0)
    self.pageText:SetText("0/0")
    
    -- Initialize variables
    self.currentPage = 1
    self.itemsPerPage = 12  -- 3x4 grid
    self.appearanceCards = {}
end

function TC_AH_New:ChangePage(delta)
    if not self.allAppearances then return end
    
    local totalPages = math.ceil(#self.allAppearances / self.itemsPerPage)
    self.currentPage = math.min(math.max(1, self.currentPage + delta), totalPages)
    
    self:UpdatePageDisplay()
    self:DisplayCurrentPage()
end

function TC_AH_New:UpdatePageDisplay()
    if not self.allAppearances then return end
    
    local totalPages = math.ceil(#self.allAppearances / self.itemsPerPage)
    self.pageText:SetText(string.format("%d/%d", self.currentPage, totalPages))
    
    -- Update button states
    self.prevButton:SetEnabled(self.currentPage > 1)
    self.nextButton:SetEnabled(self.currentPage < totalPages)
end

function TC_AH_New:DisplayCurrentPage()
    -- Clear existing cards
    self:ClearAppearanceCards()
    
    if not self.allAppearances then return end
    
    -- Calculate which items to show
    local startIndex = (self.currentPage - 1) * self.itemsPerPage + 1
    local endIndex = math.min(startIndex + self.itemsPerPage - 1, #self.allAppearances)
    
    -- Create subset of appearances for current page
    local pageAppearances = {}
    for i = startIndex, endIndex do
        table.insert(pageAppearances, self.allAppearances[i])
    end
    
    -- Display the current page
    self:CreateAppearanceCards(pageAppearances)
end

function TC_AH_New:FilterBySlot(slotID)
    -- Convert our slot ID to inventory type
    local slotToInvType = {
        HEAD = "INVTYPE_HEAD",
        SHOULDER = "INVTYPE_SHOULDER",
        BACK = "INVTYPE_CLOAK",
        CHEST = "INVTYPE_CHEST",
        WRIST = "INVTYPE_WRIST",
        HANDS = "INVTYPE_HAND",
        WAIST = "INVTYPE_WAIST",
        LEGS = "INVTYPE_LEGS",
        FEET = "INVTYPE_FEET",
        MAINHAND = "INVTYPE_WEAPON",
        OFFHAND = "INVTYPE_WEAPON",
    }

    local invType = slotToInvType[slotID]
    if not invType then return end

    print("TC: Filtering for slot:", slotID, "invType:", invType)

    -- Clear existing results
    if self.gridFrame then
        self:ClearAppearanceCards()
    end

    -- Create the browse query following the documentation
    local query = {
        searchString = "",
        sorts = {
            {sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false},
            {sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false},
        },
        filters = {
            Enum.AuctionHouseFilter.UncommonQuality,
            Enum.AuctionHouseFilter.RareQuality,
            Enum.AuctionHouseFilter.EpicQuality,
        }
    }

    print("TC: Sending browse query:", query)

    -- Set up the event handler
    if not self.searchEventFrame then
        self.searchEventFrame = CreateFrame("Frame")
        self.searchEventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
        self.searchEventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        print("TC: Created new search event frame")
    end

    self.searchEventFrame:SetScript("OnEvent", function(frame, event)
        print("TC: Received event:", event)
        
        if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
            local results = C_AuctionHouse.GetBrowseResults()
            print("TC: Got results:", results and #results or "nil")
            
            if results then
                local appearances = {}
                print("TC: Processing", #results, "auction results")
                
                -- Process each result
                for _, result in ipairs(results) do
                    local itemKey = result.itemKey
                    local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
                    if itemKeyInfo then
                        local _, itemLink, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemKeyInfo.itemID)
                        print("TC: Found item:", itemKeyInfo.itemID, "EquipLoc:", itemEquipLoc, "Link:", itemLink)
                        if itemEquipLoc == invType then
                            print("TC: Adding matching item:", itemKeyInfo.itemID)
                            table.insert(appearances, {
                                visualID = itemKeyInfo.itemID,
                                itemLink = itemLink  -- Store the item link
                            })
                        end
                    end
                end
                print("TC: Found", #appearances, "matching appearances")
                
                -- Store all appearances and display first page
                self.allAppearances = appearances
                self.currentPage = 1
                self:UpdatePageDisplay()
                self:DisplayCurrentPage()
            end
        end
    end)

    -- Start the browse query with only the query parameter
    C_AuctionHouse.SendBrowseQuery(query)
    print("TC: Browse query sent")
end

function TC_AH_New:GetCameraConfigForSlot(slotID)
    local configs = {
        FEET = {
            modelPosition = { x = 0, y = 0, z = 0.69733393192291 },
            modelScale = 1.0,
            position = { x = 1.5532778501511, y = 0.010369626805186, z = 0.71548467874527 },
            facing = 24.784032821655,
            distance = 1.5,
            target = { x = -0.041362285614014, y = 0.011449351906776, z = 0.70138305425644 }
        },
        HEAD = {
            modelPosition = { x = 0, y = 0, z = 0 },
            modelScale = 1.0,
            position = { x = 0, y = 0, z = 1 },
            facing = 0,
            distance = 0.3,
            target = { x = 0, y = 0, z = 0 }
        },
        CHEST = {
            modelPosition = { x = 0, y = 0, z = 1.5 },
            modelScale = 1.2,
            position = { x = 0, y = 0, z = 0 },
            facing = 0,
            distance = 0.7,
            target = { x = 0, y = 0, z = 0 }
        },
        LEGS = {
            modelPosition = { x = 0, y = 0, z = 3 },
            modelScale = 1.3,
            position = { x = 0, y = 0, z = -0.5 },
            facing = 0,
            distance = 0.8,
            target = { x = 0, y = 0, z = 0 }
        }
    }
    
    return configs[slotID] or {
        modelPosition = { x = 0, y = 0, z = 0 },
        modelScale = 1.0,
        position = { x = 0, y = 0, z = 0 },
        facing = 0,
        distance = 1,
        target = { x = 0, y = 0, z = 0 }
    }
end

function TC_AH_New:CreateAppearanceCards(appearances)
    if not appearances or #appearances == 0 then return end
    
    local cardSize = 140
    local padding = 8
    local cardsPerRow = 4
    
    for i, appearance in ipairs(appearances) do
        local row = math.floor((i-1) / cardsPerRow)
        local col = (i-1) % cardsPerRow
        
        -- Main card frame
        local card = CreateFrame("Frame", nil, self.gridFrame)
        card:SetSize(cardSize, cardSize)
        card:SetPoint("TOPLEFT", (col * (cardSize + padding)), -(row * (cardSize + padding)))
        
        -- Create a background for the card
        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 1)
        
        -- Create the mask frame
        local maskFrame = CreateFrame("Frame", nil, card)
        maskFrame:SetSize(cardSize - 10, cardSize - 10)
        maskFrame:SetPoint("CENTER")
        maskFrame:SetClipsChildren(true)
        
        -- Create the model
        local model = CreateFrame("DressUpModel", nil, maskFrame)
        model:SetAllPoints(maskFrame)
        model:SetUnit("player")
        model:Undress()
        
        -- Try to set the appearance
        if appearance.visualID and appearance.itemLink then
            model:TryOn(appearance.itemLink)
            
            -- Apply camera settings for the slot
            local cameraConfig = self:GetCameraConfigForSlot("FEET")
            model:SetPosition(cameraConfig.modelPosition.x, cameraConfig.modelPosition.y, cameraConfig.modelPosition.z)
            model:SetModelScale(cameraConfig.modelScale)
            model:SetCustomCamera(1)
            model:SetCameraPosition(cameraConfig.position.x, cameraConfig.position.y, cameraConfig.position.z)
            model:SetCameraTarget(cameraConfig.target.x, cameraConfig.target.y, cameraConfig.target.z)
            model:SetCameraDistance(cameraConfig.distance)
            model:SetFacing(cameraConfig.facing)
        end
        
        -- Store model reference in card for cleanup
        card.model = model
        
        table.insert(self.appearanceCards, card)
        
        local neededHeight = (row + 1) * (cardSize + padding)
        if neededHeight > self.gridFrame:GetHeight() then
            self.gridFrame:SetHeight(neededHeight)
        end
    end
end

function TC_AH_New:CreateTab()
    local numTabs = #AuctionHouseFrame.Tabs
    local tabID = numTabs + 1

    -- Create a tab button using the correct template
    local tab = CreateFrame("Button", "TC_TransmogTab_New", AuctionHouseFrame, "AuctionHouseFrameTabTemplate")
    tab:SetID(tabID)
    tab:SetText("Transmog")
    tab:SetPoint("LEFT", AuctionHouseFrame.Tabs[numTabs], "RIGHT", -15, 0)

    -- Store tabID for visibility handling
    self.tabID = tabID

    -- Add tab to AuctionHouseFrame's tab array
    table.insert(AuctionHouseFrame.Tabs, tab)
    PanelTemplates_SetNumTabs(AuctionHouseFrame, tabID)
    PanelTemplates_EnableTab(AuctionHouseFrame, tabID)

    tab:SetScript("OnClick", function()
        PanelTemplates_SetTab(AuctionHouseFrame, tabID)
        
        -- Hide all standard AH frames
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
        
        -- Show our collector frame and its elements
        self.collectorFrame:Show()
        if self.filterFrame then self.filterFrame:Show() end
        if self.searchButton then self.searchButton:Show() end
        if self.searchBox then self.searchBox:Show() end
        if self.gridFrame then self.gridFrame:Show() end
    end)

    print("TC_AH_New: Transmog tab created in new AH UI.")
end

function TC_AH_New:CreateTestModel()
    -- Create a frame for testing
    local testFrame = CreateFrame("Frame", "TC_TestFrame", UIParent)
    testFrame:SetSize(300, 300)
    testFrame:SetPoint("CENTER")
    testFrame:SetFrameStrata("HIGH")
    
    -- Add a background
    local bg = testFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    
    -- Create the model
    local model = CreateFrame("DressUpModel", nil, testFrame)
    model:SetAllPoints()
    model:SetUnit("player")
    model:SetCustomCamera(1)
    
    -- Try on boots (you can change this ID)
    model:TryOn("item:86769")
    
    -- Function to print all current settings
    local function PrintAllSettings()
        print("Current Settings:")
        print("Model Position:", model:GetPosition())
        print("Model Scale:", model:GetModelScale())
        print("Camera Position:", model:GetCameraPosition())
        print("Camera Distance:", model:GetCameraDistance())
        print("Camera Target:", model:GetCameraTarget())
        print("Facing:", model:GetFacing())
        print("------------------------")
    end
    
    -- Make frame draggable
    testFrame:SetMovable(true)
    testFrame:EnableMouse(true)
    testFrame:RegisterForDrag("LeftButton")
    testFrame:SetScript("OnDragStart", testFrame.StartMoving)
    testFrame:SetScript("OnDragStop", testFrame.StopMovingOrSizing)
    
    -- Add mouse wheel zoom
    testFrame:EnableMouseWheel(true)
    testFrame:SetScript("OnMouseWheel", function(self, delta)
        local distance = model:GetCameraDistance()
        distance = distance - (delta * 0.1)
        model:SetCameraDistance(distance)
        PrintAllSettings()
    end)
    
    -- Initialize mouse position tracking
    local isRotating = false
    local isMoving = false
    local lastX, lastY

    testFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isRotating = true
            lastX, lastY = GetCursorPosition()
        elseif button == "RightButton" then
            isMoving = true
            lastX, lastY = GetCursorPosition()
        end
    end)
    
    testFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            isRotating = false
            PrintAllSettings()
        elseif button == "RightButton" then
            isMoving = false
            PrintAllSettings()
        end
    end)
    
    testFrame:SetScript("OnUpdate", function(self, elapsed)
        if isRotating or isMoving then
            local x, y = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            x = x / scale
            y = y / scale
            
            if lastX and lastY then  -- Only adjust if we have previous coordinates
                if isRotating then
                    -- Adjust model facing (reduced sensitivity)
                    local facing = model:GetFacing()
                    facing = facing + (x - lastX) * 0.005
                    model:SetFacing(facing)
                end
                
                if isMoving then
                    -- Adjust model position instead of camera
                    local px, py, pz = model:GetPosition()
                    pz = pz + (y - lastY) * 0.005  -- Vertical movement only
                    model:SetPosition(px, py, pz)
                end
            end
            
            lastX, lastY = x, y
        end
    end)
    
    -- Add close button
    local closeButton = CreateFrame("Button", nil, testFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT")
    
    -- Print initial settings
    print("Initial Settings:")
    PrintAllSettings()
    
    self.testModel = model
    self.testFrame = testFrame
end

-- Add new cleanup function
function TC_AH_New:CleanupModels()
    if self.appearanceCards then
        for _, card in pairs(self.appearanceCards) do
            if card.model then
                card.model:ClearModel()
                card.model:SetCustomCamera(1)
                card.model:SetUnit("player")
                card.model:Undress()
            end
        end
    end
end

print("TC_AH_New: Module loaded.") 