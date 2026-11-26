# TransmogChecker

A WoW: Forever addon that tells the player which looks they have collected: on item tooltips, and in a browser of what the auction house has for sale.

## Language

**Appearance**:
One look that a model can show. Several items can carry the same appearance.
_Avoid_: Look, skin, visual, transmog

**Item**:
One thing a player can hold that carries an appearance, identified by its item id.
_Avoid_: Source

**Item variant**:
One random-suffix or item-level version of an item, such as "of the Owl". Every variant of an item carries the same appearance, and the auction house prices each variant separately.
_Avoid_: Suffix, version

**Collected**:
An appearance is collected when the account has it from any item. It is a property of the appearance, never of a single item.
_Avoid_: Owned, known, learned, unlocked

**Collectable**:
An appearance is collectable when the account is able to add it to its collection, whether or not the current character can wear it.
_Avoid_: Learnable, usable, wearable

**Class filter**:
The choice of one class whose wearable armor and usable weapons the appearance browser is narrowed to. It starts on the current character's class.
_Avoid_: Armor type filter, usable filter, wearable filter

**Slot**:
The place on a character where an appearance is worn or held, such as chest, feet or main hand.
_Avoid_: Category, type

**Appearance browser**:
The tab on the auction house window that lists the game's appearances for a slot and tells the player which of them are for sale.
_Avoid_: AH view, transmog browser, catalogue

**Tile**:
One cell of the appearance browser: a model showing a single appearance, with the lowest price it is for sale at once that is known.
_Avoid_: Card, cell, model

**All**:
The appearance browser's default mode: every appearance the game lists for the slot, with nothing read from the auction house until a tile is clicked.
_Avoid_: Catalogue, browse mode

**For sale**:
The appearance browser's mode that keeps only appearances that are not collected and have an item on the auction house now, cheapest first.
_Avoid_: Available, on AH, collectable mode

**Check**:
One lookup of the auction house for the items that carry a single appearance, started by a click on its tile.
_Avoid_: Search, lookup, query

**Scan**:
One read of the auction house for a single slot, which finds the appearances for sale in it.
_Avoid_: Browse, full scan, refresh
