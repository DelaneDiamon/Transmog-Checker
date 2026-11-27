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
The choice of one class whose wearable armor and usable weapons the appearance browser is narrowed to, or All classes. It starts on the current character's class; All classes, once chosen, is kept between visits and sessions.
_Avoid_: Armor type filter, usable filter, wearable filter

**Slot**:
The place on a character where an appearance is worn or held, such as chest, feet or main hand.
_Avoid_: Category, type

**Appearance browser**:
The tab on the auction house window that lists the game's appearances for a slot, narrowed by its filters and ordered by its sort, and tells the player which of them are for sale.
_Avoid_: AH view, transmog browser, catalogue, sweep view

**Tile**:
One cell of the appearance browser: a model showing a single appearance, with the lowest price it is for sale at once that is known.
_Avoid_: Card, cell, model

**For sale only**:
The appearance browser's filter that keeps only appearances with a known price, from the slot's scan or a check of this visit.
_Avoid_: Available, on AH, collectable mode, For sale mode

**Source filter**:
The appearance browser's filter by how an appearance's items are obtained, one entry per source type the game names and Other; an appearance passes when any of its items comes from a ticked type.
_Avoid_: Origin filter, drop filter

**Scan when shown**:
The appearance browser's setting that scans the slot when the tab is shown or the slot is selected, unless the slot has a scan from this visit. Off, only a click reads the auction house.
_Avoid_: Auto-scan, auto-refresh

**Check**:
One lookup of the auction house for the items that carry a single appearance, started by a click on its tile.
_Avoid_: Search, lookup, query

**Scan**:
One read of the auction house for a single slot, which finds the appearances for sale in it.
_Avoid_: Browse, full scan, refresh

**Tooltip style**:
How the item tooltip shows an appearance's status: Full adds lines under the game's (the status, how to collect it, the session's lowest price and the other items), Compact writes the status on the right of the item's name line.
_Avoid_: Mode, layout, view

**Settings page**:
The addon's page in the game's Options > AddOns: a preview of the item tooltip and the settings of the item tooltip and the appearance browser. `/tc`, the funnel's "Settings…" and the minimap's addon list open it.
_Avoid_: Options panel, config, settings window

**Session price**:
The lowest price the appearance browser saw for an appearance in this session, from its latest scan or check, and when; it outlives the auction house visit and is gone after a reload. The item tooltip shows it as "Lowest price".
_Avoid_: Cached price, last price, AH price
