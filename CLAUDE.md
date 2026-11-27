# TransmogChecker

WoW addon that annotates item tooltips with transmog collection status and with alternative sources of the same appearance.

## Clients

- The addon targets WoW: Forever (client 1.60.1, launched 2026-11-04): `## Interface: 16001` in `TransmogChecker.toc`.
- MoP Classic is served by releases up to `0.0.21` and gets no new work. The MoP code paths still in the source (global `GetItemInfo`, the `OnTooltipSetItem` hook) are untested since the Forever port.
- WoW is installed at `C:\Games\World of Warcraft`; Forever is the `_forever_` client.
- WoW: Forever postdates model training. Take each API fact from a live source and name it: Blizzard's UI source for the installed build (the `forever` branch of `Gethe/wow-ui-source`), warcraft.wiki.gg, or the probe below.
- Forever is a mainline-family client: item functions live under `C_Item` (the globals `GetItemInfo` and `GetItemInfoInstant` are nil), item tooltips report through `TooltipDataProcessor`, and the auction house is `C_AuctionHouse` only.
- Client-specific APIs are reached through feature detection (`if C_TransmogCollection and C_TransmogCollection.GetSourceInfo then`). Write new API calls in that form.

## Verifying a change

`dev/browser-harness/run.lua` runs the addon's files against a fake client outside the game (in WSL: `lua5.1 dev/browser-harness/run.lua` from the repo root); it must end with 0 failed. It does not replace the in-game check, which happens in the game client with the results read back from disk.

1. Copy `TransmogChecker.toc`, `TransmogChecker.lua`, `TC/`, `Libs/` and `Media/` into `C:\Games\World of Warcraft\_forever_\Interface\AddOns\TransmogChecker`.
2. The user types `/reload`; a reload also picks up a brand-new addon folder. Desktop control cannot target the game window, so every in-game step is the user's.
3. The user hovers the items the change affects. Grey and white items stay silent until `/tc skipgreys` turns that filter off.
4. A second `/reload` writes SavedVariables to `_forever_\WTF\Account\<account>\SavedVariables\`. Read `!BugGrabber.lua` there for Lua errors and `TransmogChecker.lua` for the saved settings.
5. Done when the user reports the expected tooltip lines and the error log holds nothing from the addon. Until then, report the change as written and unverified in game.

`dev/TCProbe` is a dev-only addon that records API availability and per-tooltip results into `TCProbe.lua` in the same SavedVariables folder. When a question needs an in-game fact, extend the probe and install it the same way.

## Releasing

Every push to `main` publishes a GitHub release with the next patch tag, never below the workflow's `MIN_VERSION` (`1.0.0`), and the top `CHANGELOG.md` entry as its notes (`.github/workflows/release-on-push.yml`), and a GitHub webhook has CurseForge package that tag. Treat a push to `main` as a release: get the user's go-ahead first, after the in-game check has passed. A `.pkgmeta` at the repo root keeps `dev/`, `docs/`, `CLAUDE.md`, `GLOSSARY.md` and `CHANGELOG.md` out of the CurseForge package; the GitHub release still carries GitHub's own source archive of the whole tree.
