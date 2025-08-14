TC = TC or {}

-- Unified status enum for use across the addon
TC.STATUS = {
	EXACT_COLLECTED = 1,
	MODEL_COLLECTED = 2,
	MODEL_NOT_COLLECTED = 3,
	NOT_COLLECTABLE_BY_CLASS = 4,
	NO_INFO_YET = 6,
}

-- Shared colors
TC.COLORS = {
	PREFIX = "FF9D9D9D",
	STATUS = {
		EXACT = "FF00FF00",
		MODEL = "FF00FF00",
		MODEL_NOT = "FFFF7F00",
		NOT_COLLECTABLE = "FFFF5555",
		NO_INFO = "FFAAAAAA",
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

-- Item class IDs
TC.ITEM_CLASS = {
	ARMOR = 4,
	WEAPON = 2,
}

-- Armor subclass IDs
TC.ARMOR_SUBCLASS = {
	CLOTH = 1,
	LEATHER = 2,
	MAIL = 3,
	PLATE = 4,
}

-- Level when some classes upgrade armor proficiency (Classic rules)
TC.CLASS_ARMOR_UPGRADE_LEVEL = 40

-- Allowed armor subclass per class, depending on level
-- If a class entry is a table, use .low before upgrade level and .high at/after it
TC.CLASS_TO_ARMOR = {
	DEATHKNIGHT = TC.ARMOR_SUBCLASS.PLATE,
	WARRIOR = { low = TC.ARMOR_SUBCLASS.MAIL, high = TC.ARMOR_SUBCLASS.PLATE },
	PALADIN = { low = TC.ARMOR_SUBCLASS.MAIL, high = TC.ARMOR_SUBCLASS.PLATE },
	HUNTER = { low = TC.ARMOR_SUBCLASS.LEATHER, high = TC.ARMOR_SUBCLASS.MAIL },
	ROGUE = TC.ARMOR_SUBCLASS.LEATHER,
	PRIEST = TC.ARMOR_SUBCLASS.CLOTH,
	SHAMAN = { low = TC.ARMOR_SUBCLASS.LEATHER, high = TC.ARMOR_SUBCLASS.MAIL },
	MAGE = TC.ARMOR_SUBCLASS.CLOTH,
	WARLOCK = TC.ARMOR_SUBCLASS.CLOTH,
	MONK = TC.ARMOR_SUBCLASS.LEATHER,
	DRUID = TC.ARMOR_SUBCLASS.LEATHER,
	DEMONHUNTER = TC.ARMOR_SUBCLASS.LEATHER,
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

-- Armor slots requiring allowed-armor-type validation
TC.ARMOR_SLOTS_REQUIRE_CHECK = {
	["INVTYPE_HEAD"] = true,
	["INVTYPE_SHOULDER"] = true,
	["INVTYPE_CHEST"] = true,
	["INVTYPE_WRIST"] = true,
	["INVTYPE_HAND"] = true,
	["INVTYPE_WAIST"] = true,
	["INVTYPE_LEGS"] = true,
	["INVTYPE_FEET"] = true,
}


print("TC_Constants: Loaded constants.")

