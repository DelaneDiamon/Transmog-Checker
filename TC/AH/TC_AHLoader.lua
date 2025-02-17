local loaderFrame = CreateFrame("Frame")
loaderFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
loaderFrame:SetScript("OnEvent", function(self, event)
    if AuctionHouseFrame and AuctionHouseFrame.Tabs then
        -- if TC_AH_New and TC_AH_New.Init then 
        --     TC_AH_New:Init() 
        -- end
        -- self:UnregisterEvent("AUCTION_HOUSE_SHOW")
    elseif AuctionFrame then
        print("TC_AHLoader: Detected old AH UI.")
        if TC_AH_Old and TC_AH_Old.Init then 
            TC_AH_Old:Init() 
        end
        self:UnregisterEvent("AUCTION_HOUSE_SHOW")
    else
        print("TC_AHLoader: No Auction House UI detected.")
    end
end)

print("TC_AHLoader: Module loaded and waiting for AUCTION_HOUSE_SHOW event.") 