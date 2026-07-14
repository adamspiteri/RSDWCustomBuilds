# RSDW Custom Builds — Nexus modder kit

Lean modder kit for **Dragonwilds** custom building pieces. Uses the **UE backend** only: no UAssetGUI, no RSDWArchive, no `.usmap`.

## What you need (all public downloads)

| Requirement | Where |
|-------------|--------|
| **Dragonwilds** (Steam) | Your game install folder (`…/RSDragonwilds/RSDragonwilds`) |
| **UE4SS** | [UE4SS releases](https://github.com/UE4SS-RE/RE-UE4SS/releases) — install into the game `Binaries/Win64` folder |
| **Unreal Engine 5.6** | [Epic Games Launcher](https://www.unrealengine.com/) — install **UE 5.6** (free) |
| **retoc** | [retoc releases](https://github.com/trumank/retoc/releases) or `cargo install retoc` |
| **Python 3** | [python.org](https://www.python.org/) — used by catalogue patch scripts |

You do **not** need UAssetGUI, RSDWArchive, or game mappings.

## First run

1. Extract the modder kit anywhere (e.g. `C:\Mods\RSDWCustomBuilds`).
2. Run `Tools\RSDWCustomBuildsManager.exe` (or `Tools\Run-Manager-GUI.bat`).
3. Complete **Setup**: game folder, UE 5.6, retoc, builds folder.
4. Click **Check Setup** — all build rows should show OK.

## Create your first piece

1. In Unreal, open `RSDWCustomBuilds.uproject` (UE 5.6).
2. Create a piece folder under `Builds\<PieceId>\` (or use **New-Piece.bat** / Manager workflow).
3. Each piece folder needs at least:
   - `piece.ini`
   - `SM_<PieceId>.uasset` (static mesh authored in UE)
4. Click **Build All & Install** in the Manager (or `Tools\Build-All.bat`).

The pipeline will generate blueprint + data assets in-editor, patch the vanilla catalogue with retoc, cook, pack, deploy the pak, and install **RSDWBlankMenu** (vanilla build menu binding).

## Folder layout

```
RSDWCustomBuilds/
  Builds/           ← drop piece folders here (empty to start)
  Content/          ← synced from Builds on build
  Mod/              ← manifest (pieces.json); runtime uses RSDWBlankMenu
  RSDWBlankMenu/    ← UE4SS mod (deployed automatically)
  Tools/            ← scripts + Manager EXE
  Templates/        ← piece.ini template
```

## More docs

- `Docs/MODDER_GUIDE.md` — full workflow
- `Docs/PIECE_JSON.md` — piece metadata
- `Docs/NAMING.md` — naming rules
- `Docs/UE_ONLY_BACKEND.md` — how UE backend differs from CLI

## Troubleshooting

- **Setup blocked**: confirm UE 5.6 path ends in `UE_5.6`, retoc runs from cmd, game path contains `Content\Paks`.
- **No pieces found**: add `SM_*` under `Builds\<Id>\` and run sync/build.
- **Catalogue / fatal load**: close the game fully before deploy; check Manager log for `[cat-retoc] OK`.
- **Menu does not show pieces**: ensure UE4SS is installed and Manager ran deploy (RSDWBlankMenu).
