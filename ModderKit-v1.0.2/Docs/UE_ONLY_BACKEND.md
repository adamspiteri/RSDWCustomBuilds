# UE-only build backend (no UAssetGUI / RSDWAssetCli / usmap / archive)

Goal: a Nexus-shippable modder kit where users need only the game install, this kit,
UE 5.6, and retoc. Asset generation (BP, DA, eventually catalogue) happens inside the
Unreal editor via headless Python instead of GPL asset tooling.

Switch: `Tools\mod.config.ini` → `[build] backend = ue` (default `cli` until proven).
`rsdw-builds.ps1` routes generate-bp / generate-da through the selected backend;
everything else (sync, cook, catalogue*, pack, deploy) is shared. *Catalogue is still
CLI (Phase 3).

## How it works

| Piece | CLI backend (today) | UE backend |
|---|---|---|
| BP_<Id> | UAssetGUI clone of donor BP → PakRaw | `unreal_generate_bp.py`: child of editor-only `BP_T1_BasePiece` stub (game path) with an OWNED SCS mesh component → Content, cooked |
| DA_<Id> | retoc donor extract → UAssetGUI json patch → PakRaw | `unreal_generate_da.py`: fresh `UBuildingPieceData` (stub class in `Source\Dominion`) with donor constants baked into `Generate-PieceData-UE.ps1` → `Content\Gameplay\...\RSDWBuilds\<Id>\`, cooked + staged |
| Catalogue | `Generate-Catalogue012.ps1` (RSDWAssetCli + usmap) | **In progress** — `Generate-Catalogue-UE.ps1` blocked (see below) |

Runner: `Tools\lib\Invoke-UnrealPython.ps1` (UnrealEditor-Cmd `-run=pythonscript`,
task JSON via `RSDW_UE_TASK_CONFIG` env var, requires `RSDW_TASK_OK` in output).

### Catalogue Phase 3 blocker (2026-07-07)

`DA_BuildPieceCatalogue_Default` uses **unversioned** property serialization (positional layout),
unlike UE-backend DAs which use tagged names. The modder project's `/Script/Dominion.BuildPieceCatalogue`
stub cannot deserialize the vanilla or RSDWAssetCli-rebuilt catalogue in UnrealEditor-Cmd — FName /
UnversionedPropertySerialization assertions. Mounting base-game IoStore in the editor (`-pak`) also
did not expose the asset to `EditorAssetLibrary` in headless tests.

**Working catalogue path today:** `retoc to-legacy` → UAssetGUI `tojson` → `patch_catalogue_012.py`
→ UAssetGUI `fromjson` (`Generate-Catalogue012.ps1`). Only the `tojson`/`fromjson` steps need
RSDWAssetCli; retoc + Python patch are GPL-free.

**Planned GPL-free replacement:** binary patch on the retoc legacy extract (same name-map boundary
fix documented in `Docs/HANDOFF_0.12.md` / `Tools/zen_patch_catalogue.py`), avoiding JSON round-trip.

## Critical mechanics (do not break)

1. **Tagged property serialization is mandatory**: `DefaultGame.ini` sets
   `bUseUnversionedProperties=False`. Our `/Script/Dominion` stubs are PARTIAL mirrors
   of the game's classes; with unversioned (positional) properties the game would read
   garbage. Tagged (name-based) lets the game's full class load our subset safely.
   **The ini alone is NOT enough**: UAT BuildCookRun passes `-unversioned` by default and
   UE 5.6 defines `SAVE_Unversioned = SAVE_Unversioned_Native | SAVE_Unversioned_Properties`
   (ObjectMacros.h), overriding the setting. `Cook-Windows.ps1` therefore passes
   **`-VersionCookedContent`** to UAT. Verify after any cook change: the cooked
   `DA_<Id>.uasset` must contain the literal string `PersistenceID` (property names in the
   name map = tagged).
2. **Editor-only stubs must never ship**: `BP_T1_BasePiece`
   (`/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/`), placeholder
   DataTables `DT_StabilityProfile` (`/Game/Gameplay/BaseBuilding_New/`) and
   `DT_XPEvents_Building` (`/Game/Gameplay/Progress/XPEventTables/`). They cook as
   dependencies, but `Pack-IoStore.ps1` stages only the `.../BuildingPieces/RSDWBuilds`
   subtree of Gameplay — check this whenever staging changes.
3. **Stub classes carry NO native subobjects** (`BaseBuildingActor.h` comment): a
   CreateDefaultSubobject in a stub becomes a phantom template in cooked children and
   crashes at runtime ("Could not find template object"). Piece BPs use owned SCS
   components only.
4. **Donor constants** (piece tag, stability row, XP row, fallback icon) are baked into
   `Generate-PieceData-UE.ps1`, verified against 0.12.0.0 vanilla donors:
   wall=Base/Tier1_Base/Build_Wall_Tier1; floor=Foundation/Tier1_Base/Build_Foundation_Tier1;
   foundation_large=Foundation/Tier1_Foundation/Build_Foundation_Tier1;
   foundation_med=Foundation/Tier1_Foundation/Build_Beam_Tier1_Med;
   roof=Base/Tier1_Base/Build_Roof_Tier1. **Re-verify after each game update.**
5. Gameplay tags used by pieces are declared in `Config\DefaultGameplayTags.ini`
   (`BaseBuilding.PieceType.Base`, `.Foundation`).

## Known limitations (v1)

- **Build costs**: `Requirements` needs a hard object ref to a game item asset, which
  the editor cannot load. UE-backend pieces are FREE to build (`cost_wood` warns).
  Fix candidates: item-asset stubs at game paths (like the DT placeholders).
- `SelectionPlayerHooks` from donors are not replicated (piece may lack the donor's
  selection sound).
- Catalogue patching still requires RSDWAssetCli for `tojson`/`fromjson` even when `backend=ue`
  (see "Catalogue Phase 3 blocker" above). Binary legacy patch is the planned GPL-free replacement.
- Compiling `Source\Dominion` requires the editor to be CLOSED (Live Coding lock) and
  can trip Windows Smart App Control on the first UBT rules-DLL compile (retry passes).

## Verify a backend switch

1. `rsdw-builds.ps1 generate-bp <Id>` → `Content\RSDWBuilds\<Id>\BP_<Id>.uasset` (~35 KB)
2. `rsdw-builds.ps1 generate-da <Id>` → `Content\Gameplay\...\RSDWBuilds\<Id>\DA_<Id>.uasset`
3. `rsdw-builds.ps1 build-all` → `[cat012]` lists the piece; pak contains the cooked DA
   (retoc list) and NOT the stubs (`BP_T1_BasePiece`, `DT_*` must be absent!)
4. In game: piece in vanilla menu, `registered <Id> at NetId slot ...` in UE4SS.log,
   named placement bar, placeable, persists.
