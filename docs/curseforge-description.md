TransmogChecker shows, for the WoW: Forever client, which appearances you have collected: on item tooltips and in an Appearances tab on the auction house window.

[Screenshot 1: an item tooltip in the Full style]

## On item tooltips

Hover any item that has an appearance. TransmogChecker adds a line that says "Collected" or "Not collected".

In the **Full** style you also see how the item is obtained, a note when the item binds when equipped, the lowest auction price the Appearances tab has seen for that look this session, and the other items that give the same appearance, with where each comes from.

In the **Compact** style the status sits on the right of the item's name line, with the number of other items, and the tooltip stays short.

If an item in your bags, or one you just bought, would add a look you do not have yet, the tooltip tells you how to collect it: equip it or sell it to a vendor. The game's own "not collected" line is hidden while TransmogChecker's lines show. Grey and white items get no lines unless you turn that on.

[Screenshot 2: the Compact style on a tooltip]

## The Appearances tab

Open the auction house and click its **Appearances** tab. It shows every appearance of one slot as tiles, like the game's Collections window, and which of them are for sale right now.

A typical visit:

1. Open the tab. It starts on the looks you have not collected, sorted by price, low to high, for your own class, and scans the slot.
2. Pick a slot in the slot row: Head, Shoulder, Back, Chest, Shirt, Tabard, Wrist, Hands, Waist, Legs, Feet, Main hand, Off hand or Ranged.
3. Hover a tile to see its lowest price and where its items come from.
4. Click a tile to check the auction house for that look. Click it again to see the items for sale.
5. Click **Buy** on a row. A small dialog finds the cheapest auction and buys it at its buyout when you confirm.

[Screenshot 3: the Appearances tab]

[Screenshot 4: a tile's list of items for sale]

The **Filter** button holds the filters and the sort:

- Show: All, Collected or Not collected.
- For sale only.
- Source: how the items are obtained, as the game names it.
- Class: your class, another class, or All classes.
- Sort: Collections order, Price: low to high, Price: high to low.
- Reset filters, and Settings….

Weapon slots also have a weapon type dropdown, and the Search box narrows the tiles by item name. **Scan slot** reads the slot again whenever you want fresh prices.

[Screenshot 5: the Filter menu]

## Settings

Open Options > AddOns > TransmogChecker, type `/tc`, or use the addon list on the minimap. The page starts with a preview of the tooltip that follows your choices.

- Show collection status
- Tooltip style: Full or Compact
- "Not collected" text color: Orange, Light blue or White
- Other items with this look: Only when not collected, Always or Never
- Lowest auction price (Full style only)
- Include grey & white items
- Scan prices when tab opens

[Screenshot 6: the settings page]

## Slash commands

- `/tc` opens the settings page.
- `/tc help` lists the commands.
- `/tc debug` turns debug output on or off.

## Compatibility and limits

- Made for WoW: Forever only. Releases up to 0.0.21 were for Mists of Pandaria Classic and get no new work.
- Opening the settings page closes the auction house window, because the game's Options window does.
- The game reports no boss-drop sources, so the Source filter lists only the source types the game knows; the rest are under Other.
- Prices are what the last scan or check saw. The lowest price on tooltips lasts for the session and is gone after a reload or logout.
- In combat, the settings page opens once combat ends.

## Problems and suggestions

Please report problems on the GitHub issues page: https://github.com/DelaneDiamon/Transmog-Checker/issues
