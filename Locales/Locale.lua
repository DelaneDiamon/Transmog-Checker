-- The locale mechanism: every user-facing string lives in a locale file
-- under an ID key. A locale file registers its language as
-- TC.Locales[code] = { name = "<the language's own name>", strings = {...},
-- plural = function(n) answering "one", "few", "many" or "other" }, the
-- rule optional (English's when absent), and needs no change elsewhere.
-- TC.L.KEY answers the active language's string, else enUS's, else the key
-- itself. The active language is the setting "language" ("auto" for the
-- game's, GetLocale()), set at ADDON_LOADED (TransmogChecker.lua), before
-- any window is built; a code without a locale file, enGB among them, reads
-- enUS. Strings are looked up when they are used, never kept at load.
TC = TC or {}
TC.Locales = TC.Locales or {}

local wanted = "auto"

-- The language the strings are read in: the wanted code, the game's for
-- auto, when it has a locale file, else enUS.
function TC.Language()
    local code = wanted
    if code == "auto" then code = GetLocale and GetLocale() end
    if code and TC.Locales[code] then return code end
    return "enUS"
end

-- Sets the wanted language from a code ("auto" or a registered code).
function TC.SetLanguage(code)
    wanted = code
end

-- The locale of the active language when it has the key, else enUS's.
local function localeOf(key)
    local own = TC.Locales[TC.Language()]
    if own and own.strings and own.strings[key] ~= nil then return own end
    local english = TC.Locales.enUS
    if english and english.strings and english.strings[key] ~= nil then return english end
end

TC.L = setmetatable({}, { __index = function(_, key)
    local locale = localeOf(key)
    if locale then return locale.strings[key] end
    return key
end })

-- English's rule: one for 1, other for every other count.
local function englishPlural(n)
    return n == 1 and "one" or "other"
end

-- The form of a plural entry ({ one = ..., other = ..., and what else its
-- language's rule answers }) for the count n, by the rule of the language
-- that has the entry; its "other" form when it lacks the one asked for.
function TC.Plural(key, n)
    local locale = localeOf(key)
    if not locale then return key end
    local forms = locale.strings[key]
    if type(forms) ~= "table" then return forms end
    local form = (locale.plural or englishPlural)(n)
    return forms[form] or forms.other
end
