local addonName = ...

TC = TC or {}

-- The item tooltip's settings (addon-settings v1, section "Item tooltip"),
-- each with its default and its values; a stored value that is not one of
-- them loads as the default. Labels: Show collection status, Tooltip
-- style, "Not collected" text color, Other items with this look, Lowest
-- auction price, Include grey & white items (the inverse of
-- skipPoorAndCommon, kept from before); debug stays /tc debug. language:
-- "auto" (the game's) or a code with a locale file (Locales/), whose values
-- are the registered ones, so a function answers for them.
local BOOLEAN = { [true] = true, [false] = true }
local function isLanguage(value)
    return value == "auto" or (type(value) == "string" and TC.Locales[value] ~= nil)
end
local SETTINGS = {
    tooltipShow = { default = true, values = BOOLEAN },
    tooltipStyle = { default = "full", values = { full = true, compact = true } },
    notCollectedColor = { default = "orange", values = { orange = true, lightBlue = true, white = true } },
    otherItems = { default = "notCollected", values = { notCollected = true, always = true, off = true } },
    lowestPrice = { default = true, values = BOOLEAN },
    skipPoorAndCommon = { default = true, values = BOOLEAN },
    debug = { default = false, values = BOOLEAN },
    language = { default = "auto", values = isLanguage },
}

local function valid(key, value)
    local values = SETTINGS[key].values
    if type(values) == "function" then return values(value) end
    return value ~= nil and values[value] == true
end

-- A setting's value: the stored one, else its default (also before the
-- saved table is loaded).
function TC.Setting(key)
    local value = TC.Config and TC.Config[key]
    if valid(key, value) then return value end
    return SETTINGS[key].default
end

-- A setting's default (the settings page registers each with it).
function TC.SettingDefault(key)
    return SETTINGS[key].default
end

-- Who is told of a changed value (the settings page): fn(key). The browser
-- state tells of Scan when shown the same way.
local watchers = {}
function TC.WatchSettings(fn)
    watchers[#watchers + 1] = fn
end
function TC.SettingChanged(key)
    for _, fn in ipairs(watchers) do fn(key) end
end

-- Stores a setting (the settings page's call and the slash shortcuts');
-- answers whether the value was taken. The next tooltip shown uses it.
function TC.SetSetting(key, value)
    if not (SETTINGS[key] and TC.Config and valid(key, value)) then return false end
    local changed = TC.Config[key] ~= value
    TC.Config[key] = value
    if changed then TC.SettingChanged(key) end
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
    -- the language every string is read in from now on; a change on the
    -- settings page applies after a reload, as windows are built once
    TC.SetLanguage(TC.Setting("language"))

    -- the appearance browser's six remembered choices, in their own table
    -- (TC_BrowserState checks each value)
    if type(TransmogCheckerDB.browser) ~= "table" then TransmogCheckerDB.browser = {} end
    if TC.BrowserState and TC.BrowserState.Bind then TC.BrowserState.Bind(TransmogCheckerDB.browser) end

    -- the page in the game's Options > AddOns, on a client that has it
    if TC.Settings then TC.Settings.Register() end
end)

local function say(text)
    print("|cFF9D9D9DTC:|r " .. text)
end

-- The help; with the settings page, the page's two lines (addon-settings v1, Entry points).
local L = TC.L
local function help()
    local lines = TC.Settings and TC.Settings.Available() and { L.SLASH_HELP_OPENS, L.SLASH_HELP_DEBUG }
        or { L.SLASH_HELP_LIST, L.SLASH_HELP_HELP, L.SLASH_HELP_DEBUG }
    for _, line in ipairs(lines) do say(line) end
end

-- The minimap's addon list calls this (## AddonCompartmentFunc in the .toc):
-- the settings page, else the help.
function TransmogChecker_OpenSettings()
    if not (TC.Settings and TC.Settings.Open()) then help() end
end

-- Slash command handling: /tc alone opens the settings page (the help
-- without it); alts and skipgreys stay shortcuts to their settings.
SLASH_TC1 = "/tc"
SlashCmdList["TC"] = function(msg)
    local cmd = (msg or ""):match("^%s*(%S+)")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" then
        TransmogChecker_OpenSettings()
    elseif cmd == "debug" then
        TC.Config.debug = not TC.Config.debug
        say(TC.Config.debug and L.DEBUG_ON or L.DEBUG_OFF)
    elseif cmd == "alts" or cmd == "hidealts" then
        TC.SetSetting("otherItems", TC.Setting("otherItems") == "always" and "notCollected" or "always")
        say(TC.Setting("otherItems") == "always" and L.SLASH_ALTS_ALWAYS or L.SLASH_ALTS_NOT_COLLECTED)
    elseif cmd == "filter" or cmd == "blizz" then
        say(L.SLASH_FILTER)
    elseif cmd == "skipgreys" or cmd == "greys" or cmd == "grays" then
        TC.SetSetting("skipPoorAndCommon", not TC.Setting("skipPoorAndCommon"))
        say(TC.Setting("skipPoorAndCommon") and L.SLASH_GREYS_OFF or L.SLASH_GREYS_ON)
    else
        help()
    end
end

print(L.LOADED_ADDON)
