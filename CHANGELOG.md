# Changelog

## 1.0.0 (2026-11-27)

- New: an Appearances tab on the auction house window. It shows every appearance of a slot as tiles and which of them are for sale, with the lowest price on each tile.
- New: Scan slot reads the auction house for the chosen slot; by default it runs when the tab opens.
- New: click a tile to check the auction house for that appearance, click it again to see the items for sale, and buy one at its buyout from a small dialog.
- New: filters and a sort on the tab: Show (All, Collected, Not collected), For sale only, Source, Class, weapon type, Search, and Sort (Collections order, Price: low to high, Price: high to low). The tab starts on Not collected, sorted by price, low to high.
- New: a settings page in Options > AddOns, with a preview of the tooltip. `/tc` and the minimap's addon list open it.
- New: two tooltip styles, Full and Compact, a choice of color for "Not collected", and a choice of when to list the other items with the same look.
- New: tooltips show the lowest auction price the Appearances tab has seen this session, and say how to collect a look from an item you bought or have in your bags.
- Changed: the game's own "not collected" line is now always hidden while TransmogChecker's lines show; `/tc blizz` no longer turns this off.
- Changed: `/tc` opens the settings page instead of printing the settings. `/tc help` lists the commands.
- Your earlier "hide alternatives when collected" choice carries over as Other items with this look.
