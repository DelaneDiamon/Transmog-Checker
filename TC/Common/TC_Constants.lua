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

-- Auction House UI: Slot icons (array preserves UI order)
TC.AH_SLOTS = {
	{ id = "HEAD", icon = 133136 },
	{ id = "SHOULDER", icon = 135040 },
	{ id = "BACK", icon = 133763 },
	{ id = "CHEST", icon = 132644 },
	{ id = "TABARD", icon = 135027 },
	{ id = "SHIRT", icon = 135022 },
	{ id = "WRIST", icon = 132602 },
	{ id = "HANDS", icon = 132939 },
	{ id = "WAIST", icon = 132514 },
	{ id = "LEGS", icon = 134586 },
	{ id = "FEET", icon = 132537 },
	{ id = "MAINHAND", icon = 135274 },
	{ id = "OFFHAND", icon = 134955 },
}

-- Slot-to-inventory-type mapping
TC.SLOT_TO_INVTYPE = {
	HEAD = "INVTYPE_HEAD",
	SHOULDER = "INVTYPE_SHOULDER",
	BACK = "INVTYPE_CLOAK",
	CHEST = "INVTYPE_CHEST",
	TABARD = "INVTYPE_TABARD",
	SHIRT = "INVTYPE_BODY",
	WRIST = "INVTYPE_WRIST",
	HANDS = "INVTYPE_HAND",
	WAIST = "INVTYPE_WAIST",
	LEGS = "INVTYPE_LEGS",
	FEET = "INVTYPE_FEET",
	MAINHAND = "INVTYPE_WEAPON",
	OFFHAND = "INVTYPE_WEAPON",
}

-- Camera presets used by the new AH grid (can be tuned per slot)
TC.CAMERA_CONFIGS = {
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
	},
}

-- Default camera settings fallback
TC.DEFAULT_CAMERA = {
	modelPosition = { x = 0, y = 0, z = 0 },
	modelScale = 1.0,
	position = { x = 0, y = 0, z = 0 },
	facing = 0,
	distance = 1,
	target = { x = 0, y = 0, z = 0 }
}

-- UI literal texts
TC.UI_TEXT = {
	TAB = "Transmog",
	SEARCH = "Search",
	PREV_PAGE = "<",
	NEXT_PAGE = ">",
}

-- UI sizes and layout metrics
TC.UI_SIZES = {
	SEARCH_BOX = { width = 250, height = 25 },
	SEARCH_BUTTON = { width = 80, height = 25 },
	FILTER_FRAME = { width = 600, height = 50 },
	FILTER_BUTTON = { size = 45, spacing = 8 },
	GRID = { cardSize = 140, padding = 8, cardsPerRow = 4 },
	PAGINATION = { width = 200, height = 30, buttonWidth = 30, buttonHeight = 25 },
	ITEMS_PER_PAGE = 12,
}

-- UI positional offsets
TC.UI_OFFSETS = {
	SEARCH_BOX = { x = -45, y = -35 }, -- x accounts for button width
	FILTER_FRAME_Y = -20,
	GRID = { left = 10, top = -10, right = -30, bottom = 40 },
	PAGINATION_Y = 10,
	TAB_BUTTON_X_OFFSET = -15,
}

-- UI color constants (RGBA where applicable)
TC.UI_COLORS = {
	FILTER = {
		BORDER_DEFAULT = { 0.7, 0.7, 0.7, 0.9 },
		BORDER_SELECTED = { 1.0, 0.8, 0.0, 1.0 },
		BG_DEFAULT = { 0.1, 0.1, 0.1, 1.0 },
		BG_SELECTED = { 0.3, 0.3, 0.3, 1.0 },
		GLOW_DEFAULT = { 0.4, 0.6, 1.0, 0.3 },
		GLOW_SELECTED = { 1.0, 0.8, 0.0, 0.4 },
	},
	OLD_AH = {
		OVERLAY_COLLECTED = { 0, 1, 0, 0.3 },
		OVERLAY_INVALID = { 1, 0, 0, 0.3 },
		LABEL_COLOR = { 1, 0, 0, 1 },
	},
}

-- Common UI textures
TC.UI_TEXTURES = {
	QUICKSLOT = "Interface\\Buttons\\UI-Quickslot",
	ACTION_BUTTON_BORDER = "Interface\\Buttons\\UI-ActionButton-Border",
	CHECK_GLOW = "Interface\\Buttons\\CheckButtonGlow",
}

-- Auction House default query parameters for the new AH UI
function TC.BuildAHQuery()
	return {
		sorts = {
			{ sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
			{ sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
		},
		filters = {
			Enum.AuctionHouseFilter.UncommonQuality,
			Enum.AuctionHouseFilter.RareQuality,
			Enum.AuctionHouseFilter.EpicQuality,
		},
	}
end

-- Legacy AH toggle button layout
TC.OLD_AH_TOGGLE = {
	WIDTH = 24,
	HEIGHT = 24,
	POINT = { x = 540, y = -36 },
	TOOLTIP = "Hide items that are either already collected or not eligible for transmog.",
	LABEL = "Not collected for transmog",
}

print("TC_Constants: Loaded constants.")

