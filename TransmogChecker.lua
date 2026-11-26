local addonName = ...

TC = TC or {}

-- Persistent config with defaults
local defaults = {
    hideCollectedAlts = true,            -- Hide alt sources when appearance is already collected
    filterBlizzNotCollectedLine = true,  -- Strip Blizzard's "not collected" line
    skipPoorAndCommon = true,            -- Don't annotate grey/white (non-moggable) items
    debug = false,
}

-- The client loads TransmogCheckerDB after this file has run, so the config
-- is bound once ADDON_LOADED says the saved table is in place.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedAddon)
    if loadedAddon ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    TransmogCheckerDB = TransmogCheckerDB or {}
    for k, v in pairs(defaults) do
        if TransmogCheckerDB[k] == nil then
            TransmogCheckerDB[k] = v
        end
    end

    TC.Config = TransmogCheckerDB

    -- the appearance browser's four remembered choices, in their own table
    -- (TC_BrowserState checks each value)
    if type(TransmogCheckerDB.browser) ~= "table" then TransmogCheckerDB.browser = {} end
    if TC.BrowserState and TC.BrowserState.Bind then TC.BrowserState.Bind(TransmogCheckerDB.browser) end
end)

local function statusLabel(flag)
    return flag and "ON" or "OFF"
end

local function printConfig()
    print("|cFF9D9D9DTC:|r Settings - hide alts when collected:", statusLabel(TC.Config.hideCollectedAlts),
        "filter Blizzard line:", statusLabel(TC.Config.filterBlizzNotCollectedLine),
        "skip grey/white:", statusLabel(TC.Config.skipPoorAndCommon),
        "debug:", statusLabel(TC.Config.debug))
end

-- Slash command handling
SLASH_TC1 = "/tc"
SlashCmdList["TC"] = function(msg)
    local cmd = (msg or ""):match("^%s*(%S+)")
    cmd = cmd and cmd:lower() or ""

    if cmd == "debug" then
        TC.Config.debug = not TC.Config.debug
        print("|cFF9D9D9DTC:|r Debug mode " .. (TC.Config.debug and "enabled" or "disabled"))
    elseif cmd == "alts" or cmd == "hidealts" then
        TC.Config.hideCollectedAlts = not TC.Config.hideCollectedAlts
        print("|cFF9D9D9DTC:|r Hide alt sources when collected " .. (TC.Config.hideCollectedAlts and "enabled" or "disabled"))
    elseif cmd == "filter" or cmd == "blizz" then
        TC.Config.filterBlizzNotCollectedLine = not TC.Config.filterBlizzNotCollectedLine
        print("|cFF9D9D9DTC:|r Filter Blizzard 'not collected' line " .. (TC.Config.filterBlizzNotCollectedLine and "enabled" or "disabled"))
    elseif cmd == "skipgreys" or cmd == "greys" or cmd == "grays" then
        TC.Config.skipPoorAndCommon = not TC.Config.skipPoorAndCommon
        print("|cFF9D9D9DTC:|r Skip grey/white items " .. (TC.Config.skipPoorAndCommon and "enabled" or "disabled"))
    else
        print("|cFF9D9D9DTC:|r Commands - /tc debug, /tc alts, /tc blizz, /tc skipgreys")
        printConfig()
    end
end

print("TransmogChecker: Addon loaded.")
