# Flags

The flag of each language in the settings page's Language dropdown, one file per locale code.

- Source: flagcdn.com (a service of Flagpedia.net), the PNGs 160 wide, `https://flagcdn.com/w160/<country>.png` for us, de, es, mx, fr, it, kr, br, ru, cn and tw. Fetched 2026-11-27.
- Licence: public domain. Flagpedia.net's terms (https://flagpedia.net/terms), "Intellectual Property Rights": "The flag images provided on our website are in the public domain and can be used freely without restriction." No notice is required.
- Conversion: `dev/media/flags_tga.py` (standard library only). Each flag is scaled to 32 high at its own aspect by area averaging and centred on a 64 x 32 transparent canvas, written as an uncompressed 32-bit TGA with alpha, bottom-left origin, as `Media/wheel.tga`. To rebuild, download the PNGs into a folder of their own and run `python3 -I dev/media/flags_tga.py <that folder>` from the repo root.
