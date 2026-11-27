local addonName = ...

TC = TC or {}

-- The item tooltip's settings (addon-settings v1, section "Item tooltip"),
-- each with its default and its values; a stored value that is not one of
-- them loads as the default. Labels: Show on item tooltips, Style, Not
-- collected color, Other items, Lowest price, Grey and white items (the
-- inverse of skipPoorAndCommon, kept from before); debug stays /tc debug.
local BOOLEAN = { [true] = true, [false] = true }
local SETTINGS = {
    tooltipShow = { default = true, values = BOOLEAN },
    tooltipStyle = { default = "full", values = { full = true, compact = true } },
    notCollectedColor = { default = "orange", values = { orange = true, lightBlue = true, white = true } },
    otherItems = { default = "notCollected", values = { notCollected = true, always = true, off = true } },
    lowestPrice = { default = true, values = BOOLEAN },
    skipPoorAndCommon = { default = true, values = BOOLEAN },
    debug = { default = false, values = BOOLEAN },
}

local function valid(key, value)
    return value ~= nil and SETTINGS[key].values[value] == true
end

-- A setting's value: the stored one, else its default (also before the
-- saved table is loaded).
function TC.Setting(key)
    local value = TC.Config and TC.Config[key]
    if valid(key, value) then return value end
    return SETTINGS[key].default
end

-- Stores a setting (the settings panel's call); answers whether the value
-- was taken. The next tooltip shown uses it.
function TC.SetSetting(key, value)
    if not (SETTINGS[key] and TC.Config and valid(key, value)) then return false end
    TC.Config[key] = value
    return true
end

-- The client loads TransmogCheckerDB after this file has run, so the config
-- is bound once ADDON_LOADED says the saved table is in place.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedAddon)
    if loadedAddon ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    if type(TransmogCheckerDB) ~= "table" then TransmogCheckerDB = {} end
    -- the old "hide alts when collected" (left on disk) becomes Other items
    if TransmogCheckerDB.otherItems == nil and type(TransmogCheckerDB.hideCollectedAlts) == "boolean" then
        TransmogCheckerDB.otherItems = TransmogCheckerDB.hideCollectedAlts and "notCollected" or "always"
    end
    for key, setting in pairs(SETTINGS) do
        if not valid(key, TransmogCheckerDB[key]) then TransmogCheckerDB[key] = setting.default end
    end

    TC.Config = TransmogCheckerDB

    -- the appearance browser's four remembered choices, in their own table
    -- (TC_BrowserState checks each value)
    if type(TransmogCheckerDB.browser) ~= "table" then TransmogCheckerDB.browser = {} end
    if TC.BrowserState and TC.BrowserState.Bind then TC.BrowserState.Bind(TransmogCheckerDB.browser) end
end)

local function say(text)
    print("|cFF9D9D9DTC:|r " .. text)
end

local HELP = { "/tc lists these commands.", "/tc help lists these commands.", "/tc debug turns debug output on or off." }

-- Slash command handling: alts and skipgreys are shortcuts to their
-- settings until the settings panel exists.
SLASH_TC1 = "/tc"
SlashCmdList["TC"] = function(msg)
    local cmd = (msg or ""):match("^%s*(%S+)")
    cmd = cmd and cmd:lower() or ""

    if cmd == "debug" then
        TC.Config.debug = not TC.Config.debug
        print("|cFF9D9D9DTC:|r Debug mode " .. (TC.Config.debug and "enabled" or "disabled"))
    elseif cmd == "alts" or cmd == "hidealts" then
        TC.SetSetting("otherItems", TC.Setting("otherItems") == "always" and "notCollected" or "always")
        say("Other items on item tooltips: " .. (TC.Setting("otherItems") == "always" and "always" or "when not collected"))
    elseif cmd == "filter" or cmd == "blizz" then
        say("Blizzard's \"not collected\" line is now always hidden while TransmogChecker's lines show.")
    elseif cmd == "skipgreys" or cmd == "greys" or cmd == "grays" then
        TC.SetSetting("skipPoorAndCommon", not TC.Setting("skipPoorAndCommon"))
        say("Skip grey/white items " .. (TC.Setting("skipPoorAndCommon") and "enabled" or "disabled"))
    else
        for _, line in ipairs(HELP) do say(line) end
    end
end

print("TransmogChecker: Addon loaded.")
