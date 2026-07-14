# Changelog

## v1.0.3

### Native piece registration (major)
Custom pieces are now registered by the GAME ITSELF at boot, exactly like vanilla
content. The kit ships a small `AssetRegistry.bin` (deployed automatically to
`RSDragonwilds/Plugins/Amd/FSR/`) that the engine merges into its asset registry;
the game's AssetManager then discovers and indexes the pieces natively.

What this means for players:
- Pieces load, place, snap and save through pure game code.
- Pieces keep working even if UE4SS breaks after a game update — the Lua mod is
  now only a helper (menu unlock + recovery), not a life-support system.
- Installing a creator pak = pak trio + the AssetRegistry.bin (see PLAYER_INSTALL).

### Piece journal + automatic restore
The mod keeps a per-save journal of placed custom pieces (written on placement,
demolish and game save). If the mod is removed, placed pieces degrade to plain
walls; when the mod is reinstalled, the journal automatically respawns the custom
pieces natively at their original spots — no lost builds.

### Manager
- Rebuilt as a normal multi-file .NET app with full version metadata and an
  application icon (fixes antivirus false-positive quarantines on Nexus).
- Requires the .NET 8 Desktop Runtime (unchanged).

### Known issues
- After a remove-mod / reinstall-mod cycle, leftover VANILLA wall "twins" can
  appear overlapping the restored custom pieces. They are cosmetic (the restored
  custom pieces are real and persistent). The mod hunts them down automatically
  in the background; any that survive can simply be hammer-demolished — they are
  ordinary vanilla walls and will not return once demolished.
- Building pieces damaged during the removed-mod period may show broken visuals;
  hammer-demolish and rebuild the affected piece.

## v1.0.1
Initial public release: one-folder-per-piece workflow, Manager GUI, UE-only
build backend (no external asset tools), vanilla build menu integration,
donor-grade snapping, build costs, auto-fit and auto-material for imported
meshes.
