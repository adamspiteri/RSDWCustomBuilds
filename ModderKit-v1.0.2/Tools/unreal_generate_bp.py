"""Headless UE task: generate BP_<PieceId> for a building piece (UE-only backend).

Run via Invoke-UnrealPython.ps1; task parameters come from the JSON file at
$env:RSDW_UE_TASK_CONFIG:

  {
    "piece_id":  "Woodwall",
    "mesh_path": "/Game/RSDWBuilds/Woodwall/SM_Woodwall",
    "bp_pkg":    "/Game/RSDWBuilds/Woodwall",
    "bp_name":   "BP_Woodwall",
    "force":     false            # true = regenerate even if BP exists
  }

Design (see make_stonewall_bp.py + Source/Dominion/Public/BaseBuildingActor.h):
- BP_T1_BasePiece: editor-only stub at the GAME path, parent = ABaseBuildingActor
  (our C++ stub with NO native subobjects). Created once, shared by every piece,
  NEVER deleted here (children reference it). Never staged into the pak.
- BP_<PieceId>: child of BP_T1_BasePiece with an OWNED SCS StaticMeshComponent
  ("<PieceId>Mesh") — never an inherited-component override, which is keyed by the
  stub parent's SCS guid and would not bind to the game's real classes at runtime.

Prints RSDW_TASK_OK on success (Invoke-UnrealPython requires it).
"""
import json
import os
import sys

import unreal

BASEPIECE_PKG = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor"
BASEPIECE_NAME = "BP_T1_BasePiece"

at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary
sds = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)


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


def make_blueprint(pkg, name, parent_class):
    factory = unreal.BlueprintFactory()
    factory.set_editor_property("parent_class", parent_class)
    bp = at.create_asset(name, pkg, unreal.Blueprint, factory)
    if bp is None:
        fail("failed to create blueprint %s/%s" % (pkg, name))
    return bp


def add_mesh_component(bp, comp_name):
    handles = sds.k2_gather_subobject_data_for_blueprint(bp)
    root = handles[0]
    params = unreal.AddNewSubobjectParams()
    params.set_editor_property("parent_handle", root)
    params.set_editor_property("new_class", unreal.StaticMeshComponent)
    params.set_editor_property("blueprint_context", bp)
    new_handle, fail_reason = sds.add_new_subobject(params)
    if not fail_reason.is_empty():
        fail("add_new_subobject failed: " + str(fail_reason))
    sds.rename_subobject(new_handle, unreal.Text(comp_name))
    return new_handle


def template_object(handle, bp):
    """The component TEMPLATE serialized in the BP (not a transient instance)."""
    data = sds.k2_find_subobject_data_from_handle(handle)
    obj = unreal.SubobjectDataBlueprintFunctionLibrary.get_object_for_blueprint(data, bp)
    if obj is None:
        obj = unreal.SubobjectDataBlueprintFunctionLibrary.get_object(data)
    return obj


def ensure_base_stub():
    """Shared editor-only parent stub at the game path. Create once, reuse forever."""
    full = BASEPIECE_PKG + "/" + BASEPIECE_NAME
    if eal.does_asset_exist(full):
        bp = eal.load_asset(full)
        cls = bp.generated_class() if bp else None
        if cls is None:
            fail("existing %s failed to load/compile" % full)
        log("base stub exists: %s" % full)
        return cls
    base_bp = make_blueprint(BASEPIECE_PKG, BASEPIECE_NAME, unreal.BaseBuildingActor)
    unreal.BlueprintEditorLibrary.compile_blueprint(base_bp)
    eal.save_loaded_asset(base_bp)
    log("base stub created: %s" % full)
    return base_bp.generated_class()


def main():
    task = read_task()
    piece_id = task["piece_id"]
    mesh_path = task["mesh_path"]
    bp_pkg = task["bp_pkg"]
    bp_name = task["bp_name"]
    force = bool(task.get("force", False))
    bp_full = bp_pkg + "/" + bp_name

    if eal.does_asset_exist(bp_full) and not force:
        log("%s already exists - skipping (force=false)" % bp_full)
        print("RSDW_TASK_OK")
        return

    sm = unreal.load_asset(mesh_path)
    if sm is None:
        fail("mesh not found: %s (save it in the editor first)" % mesh_path)

    base_class = ensure_base_stub()

    if eal.does_asset_exist(bp_full):
        eal.delete_asset(bp_full)

    piece_bp = make_blueprint(bp_pkg, bp_name, base_class)
    unreal.BlueprintEditorLibrary.compile_blueprint(piece_bp)

    comp_name = piece_id + "Mesh"
    handle = add_mesh_component(piece_bp, comp_name)
    comp = template_object(handle, piece_bp)
    comp = unreal.StaticMeshComponent.cast(comp)
    if comp is None:
        fail("%s template is not a StaticMeshComponent" % comp_name)
    comp.set_editor_property("static_mesh", sm)
    log("owned SCS %s.static_mesh = %s" % (comp_name, mesh_path))

    unreal.BlueprintEditorLibrary.compile_blueprint(piece_bp)
    if not eal.save_loaded_asset(piece_bp):
        fail("save failed for " + bp_full)
    log("generated %s (parent %s/%s)" % (bp_full, BASEPIECE_PKG, BASEPIECE_NAME))
    print("RSDW_TASK_OK")


if __name__ == "__main__":
    main()
