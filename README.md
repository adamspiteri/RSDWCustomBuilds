# RSDW Custom Builds — Modder Kit

Add **native custom building pieces** to RuneScape: Dragonwilds. Pieces appear in
the **vanilla build menu**, place/snap/save/load through real game code, and use
your own mesh, textures, icon and build cost. One folder per piece, one build.

- **Download:** grab the packaged zip from [Releases](../../releases) — you do not
  need to clone this repo unless you want to work on the kit itself.
- **Important:** the release zip includes prebuilt editor module binaries
  (`Binaries/Win64/`). A raw clone of this repo does NOT — building from a clone
  requires Visual Studio 2022 with C++ to compile `Source/Dominion` once.
- Also published on Nexus Mods.

## What makes it "native"

The kit ships a premade `AssetRegistry.bin` that the engine merges at boot, so the
**game's own AssetManager registers your pieces** exactly like official content:

- pieces load, place, snap and persist through pure game code;
- they keep working even if UE4SS breaks after a game update;
- no vanilla files are overridden and no GPL tooling is involved anywhere
  (piece data, blueprints and the catalogue are all generated with Unreal
  itself plus a small pure-Python patcher).

A small UE4SS Lua mod handles menu unlocking and a **piece journal** that
automatically restores placed pieces if the mod is removed and later reinstalled.

## Quick start (piece creators)

1. Requirements: RS: Dragonwilds (Steam), **Unreal Engine 5.6**,
   [retoc](https://github.com/trumank/retoc),
   [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), .NET 8 Desktop Runtime.
2. Extract the release zip anywhere and run **`Tools\Run-Manager-GUI.bat`**.
3. First run: point the Manager at your game folder, UE 5.6 and retoc.
4. **New Piece…** → author your mesh/textures in the Unreal project
   (`Content/RSDWBuilds/<PieceId>/`) → **Build All & Install**.
5. Full game restart → your piece is in the vanilla build menu, with snapping,
   stability, and build costs (`cost = wood:4` in `piece.ini`).

Full guides live in [`Docs/`](Docs) — start with `MODDER_GUIDE.md` (creators)
and `PLAYER_INSTALL.md` (players installing a finished pak).

## Repo layout

| Path | What |
|---|---|
| `Tools/` | Build pipeline (PowerShell + UE Python) and the Manager GUI |
| `Source/Dominion/` | Editor-only C++ stubs of the game's piece-data classes |
| `RSDWBlankMenu/` | The UE4SS Lua runtime mod (menu unlock + piece journal) |
| `Content/RSDWBuilds/` | Example piece (SpikeWall) + your authored pieces |
| `Config/`, `Templates/`, `Docs/` | UE project config, piece templates, guides |

## Changelog

See [`Docs/CHANGELOG.md`](Docs/CHANGELOG.md).

## License / attribution

See [LICENSE](LICENSE). Game assets remain Jagex property; this kit generates
and ships only your own content plus generated metadata.
