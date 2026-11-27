TC = TC or {}

-- The item tooltip's colors (item-tooltip v3): the game's GREEN, NORMAL,
-- GRAY and HIGHLIGHT_FONT_COLOR and Collections' red for a name not loaded,
-- as TC_BrowserState.lua's fallbacks give them; "Not collected" in the
-- setting's presets (orange is the colour of the old "MODEL NOT COLLECTED",
-- light blue LIGHTBLUE_FONT_COLOR's fallback .53, .67, 1).
TC.COLORS = {
	COLLECTED = "FF19FF19",
	GOLD = "FFFFD100",
	GREY = "FF808080",
	WHITE = "FFFFFFFF",
	RETRIEVING = "FFFF2020",
	NOT_COLLECTED = { orange = "FFFF7F00", lightBlue = "FF87ABFF", white = "FFFFFFFF" },
}

-- Source type descriptions (extend as needed per client): each name's
-- locale key, read where the client names no source type
TC.SOURCE_TYPES = {
	[1] = { nameKey = "SOURCE_BOSS_DROP" },
	[2] = { nameKey = "SOURCE_QUEST" },
	[3] = { nameKey = "SOURCE_VENDOR" },
	[4] = { nameKey = "SOURCE_WORLD_DROP" },
	[5] = { nameKey = "SOURCE_ACHIEVEMENT" },
	[6] = { nameKey = "SOURCE_PROFESSION" },
}

-- Valid equipment locations for transmoggable gear
TC.VALID_EQUIP_LOCS = {
	["INVTYPE_HEAD"] = true,
	["INVTYPE_SHOULDER"] = true,
	["INVTYPE_BODY"] = true,
	["INVTYPE_CHEST"] = true,
	["INVTYPE_ROBE"] = true,
	["INVTYPE_WAIST"] = true,
	["INVTYPE_LEGS"] = true,
	["INVTYPE_FEET"] = true,
	["INVTYPE_WRIST"] = true,
	["INVTYPE_HAND"] = true,
	["INVTYPE_CLOAK"] = true,
	["INVTYPE_WEAPON"] = true,
	["INVTYPE_SHIELD"] = true,
	["INVTYPE_2HWEAPON"] = true,
	["INVTYPE_WEAPONMAINHAND"] = true,
	["INVTYPE_WEAPONOFFHAND"] = true,
	["INVTYPE_HOLDABLE"] = true,
	["INVTYPE_TABARD"] = true,
	["INVTYPE_RANGED"] = true,
	["INVTYPE_RANGEDRIGHT"] = true,
}


print(TC.L.LOADED_CONSTANTS)
