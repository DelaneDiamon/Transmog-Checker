TC = TC or {}

-- Shared colors
TC.COLORS = {
	PREFIX = "FF9D9D9D",
	STATUS = {
		EXACT = "FF00FF00",
		MODEL = "FF00FF00",
		MODEL_NOT = "FFFF7F00",
	},
}

-- Source type descriptions (extend as needed per client)
TC.SOURCE_TYPES = {
	[1] = "Boss Drop",
	[2] = "Quest",
	[3] = "Vendor",
	[4] = "World Drop",
	[5] = "Achievement",
	[6] = "Profession",
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


print("TC_Constants: Loaded constants.")
