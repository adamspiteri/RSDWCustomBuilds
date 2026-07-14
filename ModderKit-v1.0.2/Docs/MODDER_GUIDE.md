# Modder guide — UE to Dragonwilds

End-to-end workflow for **RSDW Custom Builds**. No Lua, no UAssetGUI manual steps for normal pieces.

---

## 1. Install prerequisites

| Tool | Purpose |
|------|---------|
| Unreal Engine **5.6** | Author meshes + material instances |
| **retoc** | Pack IoStore `.pak` trio |
| **UAssetGUI** | Generate `DA_*` / `BP_*` from templates (automated) |
| **UE4SS** | Runtime mod loader (game + your `Mod/` folder) |

Run **`Tools\Setup.bat`** once and set paths in `Tools\mod.config.ini`.

Optional: set `RSDW_UASSETGUI_EXE` if UAssetGUI is not on PATH (see `RSDWArchive/tools/rsdw-asset.ps1`).

Run this any time to check whether install/build features are available:

```bat
Tools\Manager.bat check
```

---

## 2. Create a piece in Unreal

1. Open **`RSDWCustomBuilds.uproject`**.
2. Run (outside UE):

   ```bat
   Tools\New-Piece.bat MyPieceName
   ```

   Optional: `Tools\New-Piece.bat LumbridgeCastle "Lumbridge Castle" prop`

3. Reopen or refresh Content Browser → **`Content/RSDWBuilds/MyPieceName`** (folder + `piece.ini` created).
4. Import FBX or model in-editor → save as **`SM_MyPieceName`**.
5. Import textures as **Texture2D**; create **Material Instances** parented to `M_Standard_Env_MR_Building`.
6. Open **`SM_MyPieceName`** → assign MIs to each **Material Slot**.
7. Add **collision** on the static mesh (box or complex-as-simple).
8. **Save All**.

You do **not** need to find `BP_T1_Foundation_Large` in the Content Browser — that blueprint lives in the **game paks**, not this project. **`Build-Piece.bat`** auto-generates **`BP_<PieceId>`** from the donor (same snap/collision behaviour, mesh swapped to your `SM_*`).

See [`NAMING.md`](NAMING.md) for exact names.

---

## 3. Build and deploy

```bat
Tools\Build-Piece.bat MyPieceName
```

The script:

1. Validates folder + `piece.ini` + `SM_*`
2. Generates **`BP_*`** from game donor blueprint (if missing)
3. Generates `DA_*` (UAssetGUI) with BuildableActor → your BP
4. Patches vanilla **catalogue slot 651** (native spawn index — no runtime catalogue Lua)
5. Cooks UE content (mesh, materials, BP)
6. Writes **`Mod/pieces.json`** manifest
7. Packs **`RSDragonwilds-Z_RSDWCustomBuilds_P.*`** (includes `Gameplay/.../DA_BuildPieceCatalogue_Default`)
8. Copies pak to game `Content/Paks/` and refreshes UE4SS mod

Runtime mod: **F7 menu + unlock only**. Preview and placed pieces come from the pak (no mesh swap on load).

### Raw-file shortcut

If you have a folder with `piece.json`, `model.fbx`, and textures, you can skip manual UE importing:

```bat
Tools\Manager.bat build-from-files C:\MyPieces\MyStoneWall
```

See `Docs\PIECE_JSON.md` for the folder format.

---

## 4. Test in game

1. Full restart of Dragonwilds (pak mount on boot).
2. Unlock T1 building (crafting bench) if testing foundation donors.
3. **F7** build mode → find piece by `display_name` from `piece.ini`.
4. Place → exit to menu or save → reload → piece should **still exist**.

---

## 5. Ship on Nexus

**For players (runtime only):**

```
YourPack_v1/
  Mod/                          ← from this repo Mod/ + your pieces.json
  Paks/
    RSDragonwilds-Z_RSDWCustomBuilds_P.pak
    RSDragonwilds-Z_RSDWCustomBuilds_P.utoc
    RSDragonwilds-Z_RSDWCustomBuilds_P.ucas
  README.txt                    ← link PLAYER_INSTALL.md
```

**Hard dependency:** players install base **RSDW Custom Builds** UE4SS mod (or bundle it).

---

## Multi-texture castles (one piece)

1. Merge castle in Blender with **named materials** (Stone, Roof, Trim…).
2. Import one **`SM_LumbridgeCastle`** with multiple slots.
3. One **`MI_LumbridgeCastle_Stone`** per slot; assign on mesh in UE.
4. `piece.ini` → `donor = prop`
5. `Build-Piece.bat LumbridgeCastle`

Persistence = one building piece ID. Textures survive reload because they are **baked on the mesh**, not applied by Lua.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Grey mesh in game | Assign MIs on mesh slots in UE; rebuild |
| Piece not in menu | Check `Mod/pieces.json`; UE4SS log for `[RSDWBuilds]` |
| Pak not loading | All **3** IoStore files in `Content/Paks/`; full game restart |
| Unstable / red ghost | Match donor footprint or use `donor = prop`; fix collision |
| UAssetGUI error | Set `RSDW_UASSETGUI_EXE`; export donor DA from FModel if needed |

---

## Advanced: CLI

```powershell
Tools\rsdw-builds.ps1 scan
Tools\rsdw-builds.ps1 check
Tools\rsdw-builds.ps1 build-from-files C:\MyPieces\MyStoneWall
Tools\rsdw-builds.ps1 build MyPieceName
Tools\rsdw-builds.ps1 build-all
Tools\rsdw-builds.ps1 install-pack C:\Downloads\SomePack
Tools\rsdw-builds.ps1 rollback
Tools\rsdw-builds.ps1 deploy
```
