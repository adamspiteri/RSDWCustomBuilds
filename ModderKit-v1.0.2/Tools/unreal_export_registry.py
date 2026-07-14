"""Headless UE task: export a FILTERED premade AssetRegistry.bin for the mod.

Run via Invoke-UnrealPython.ps1; task JSON at $env:RSDW_UE_TASK_CONFIG:

  {
    "package_paths": ["/Game/RSDWBuilds",
                      "/Game/Gameplay/BaseBuilding_New/BuildingPieces/RSDWBuilds"],
    "output_file":   "C:/.../Build/AssetRegistry.bin"
  }

Why: the game's AssetManager registers building pieces natively by scanning the
ASSET REGISTRY for /Script/Dominion.BuildingPieceData under /Game/Gameplay
(recursive). Mod paks carry no registry rows, so pak DAs are invisible to that
scan - that is the only reason the Lua runtime registration exists. The engine
(AssetRegistry.cpp, LoadPremadeAssetRegistry_Plugins) appends
<EnabledContentPlugin>/AssetRegistry.bin from EVERY enabled content plugin into
the global registry at boot, so shipping this file at such a path makes the
game register our pieces itself.

FILTERED is mandatory: AppendState OVERWRITES rows with duplicate object paths,
so the full cooked registry (which contains rows for our editor-only stubs at
the GAME's paths: DT_StabilityProfile, BP_T1_BasePiece, M_Standard_Env_MR_...)
would clobber vanilla rows. Restricting to our own roots = pure adds.

Prints RSDW_TASK_OK on success.
"""
import json
import os
import sys

import unreal


def log(msg):
    unreal.log_warning("[RSDW] " + str(msg))


def fail(msg):
    unreal.log_error("[RSDW] FAIL: " + str(msg))
    sys.exit(1)


def read_task():
    path = os.environ.get("RSDW_UE_TASK_CONFIG")
    if not path or not os.path.exists(path):
        fail("RSDW_UE_TASK_CONFIG missing or invalid")
    with open(path, "r", encoding="utf-8-sig") as fh:
        return json.load(fh)


def main():
    task = read_task()
    roots = task.get("package_paths") or []
    out = task.get("output_file") or ""
    if not roots or not out:
        fail("package_paths / output_file required")

    # Optional: re-save assets first so their registry rows refresh. Needed when the
    # stub class gains registry-affecting behavior (e.g. UPrimaryDataAsset baking
    # PrimaryAssetType/PrimaryAssetName tags) after the assets were last saved.
    eal = unreal.EditorAssetLibrary
    for asset_path in task.get("resave_assets") or []:
        if not eal.does_asset_exist(asset_path):
            fail("resave target missing: " + asset_path)
        if not eal.save_asset(asset_path, only_if_is_dirty=False):
            fail("could not re-save: " + asset_path)
        log("re-saved " + asset_path)

    out_dir = os.path.dirname(out)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir)

    ok = unreal.RSDWEditorTools.rsdw_save_asset_registry(roots, out)
    if not ok:
        fail("RSDWSaveAssetRegistry returned false (no assets under roots?)")
    if not os.path.exists(out):
        fail("registry file not written: " + out)

    size = os.path.getsize(out)
    log("filtered AssetRegistry saved: {} bytes -> {}".format(size, out))
    print("RSDW_TASK_OK")


main()
