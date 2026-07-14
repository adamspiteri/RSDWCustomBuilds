# RSDW Custom Builds

**Persistent custom building pieces for RuneScape: Dragonwilds** — no Lua coding required for modders.

Ship a mesh + textures from Unreal Engine → run one build script → get a pak + in-game build menu entry.

For Nexus users, `Tools\Manager.bat` also supports raw `piece.json` folders and prebuilt pack installs.

---

## Two packages (Nexus)

| Download | Who | Contains |
|----------|-----|----------|
| **RSDW Custom Builds — Modder Kit** | Creators | UE project, `Tools/` (with pre-built Manager GUI), docs |
| **RSDW Custom Builds — Runtime** | Players | `Mod/` + `.pak` only (no UE needed) |

Players need **UE4SS** and the base **RSDW Custom Builds** runtime mod. Modders additionally need **UE 5.6**, **retoc**, and **UAssetGUI** (for piece data generation).

---

## Modder quick start

1. **First time:** double-click **`Tools\Run-Manager-GUI.bat`** → complete the setup wizard (game path, UE path, retoc).
2. Open **`RSDWCustomBuilds.uproject`** in Unreal **5.6**.
3. Create a piece folder:

   ```
   Tools\New-Piece.bat StoneWall
   ```

   Or with a custom name / donor: `Tools\New-Piece.bat LumbridgeCastle "Lumbridge Castle" prop`

4. Save mesh + material instances in UE, then run:

   ```
   Tools\Build-Piece.bat MyPieceName
   ```

5. Launch the game → **Build mode (F7)** → place your piece → **save world** → reload to confirm persistence.

---

## Piece folder convention

```
Content/RSDWBuilds/MyPieceName/
  piece.ini              ← display name, donor type (required)
  SM_MyPieceName         ← static mesh (required)
  T_Icon_MyPieceName     ← build menu icon (optional)
  MI_MyPieceName_Stone   ← material instance on mesh slot 0 (recommended)
  MI_MyPieceName_Roof    ← slot 1 …
  T_Stone, T_Stone_N     ← textures referenced by MIs
```

**Textures are baked on the mesh in UE** (Material Instances). No runtime Lua texture hacks.

---

## Tooling overview

| Script | Purpose |
|--------|---------|
| `Setup.bat` | Create `mod.config.ini` from template |
| `Build-Manager-Exe.bat` | Publish the Windows GUI manager EXE |
| `Run-Manager-GUI.bat` | Launch the GUI manager |
| `Manager.bat check` | Validate game, UE4SS, Unreal, retoc, UAssetGUI |
| `Manager.bat build-from-files <Folder>` | Import raw `piece.json` + model/textures, cook, pack, deploy |
| `Manager.bat install-pack <Folder>` | Install a prebuilt Nexus pack with backup |
| `Manager.bat rollback` | Restore the last install backup |
| `Build-Piece.bat <Name>` | Validate → cook → generate DA → pack → deploy |
| `Build-All.bat` | Build every folder under `Content/RSDWBuilds/` |
| `rsdw-builds.ps1` | PowerShell CLI (same commands) |

The GUI manager is a wrapper over the same PowerShell pipeline, so the CLI remains the source of truth.

UAssetGUI is invoked automatically by the build script (same CLI as `RSDWArchive/tools/rsdw-asset.ps1`).

---

## Docs

- [`Docs/MODDER_GUIDE.md`](Docs/MODDER_GUIDE.md) — full UE → game workflow
- [`Docs/NEXUS_MANAGER.md`](Docs/NEXUS_MANAGER.md) — player/creator manager commands
- [`Docs/PIECE_JSON.md`](Docs/PIECE_JSON.md) — raw model/texture folder format
- [`Docs/NAMING.md`](Docs/NAMING.md) — file names, donors, materials
- [`Docs/PLAYER_INSTALL.md`](Docs/PLAYER_INSTALL.md) — Nexus player instructions

---

## Requirements

- RuneScape: Dragonwilds (Steam)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) installed in game `Binaries/Win64/`
- Modder: Unreal Engine **5.6**, [retoc](https://github.com/trumank/retoc), [UAssetGUI](https://github.com/atenfyr/UAssetGUI) (or RSDW fork)

---

## License / attribution

Game assets remain Jagex property. For personal installs you own only.
