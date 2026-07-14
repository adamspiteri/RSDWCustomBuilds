"""Headless UE task: generate DA_<PieceId> (UBuildingPieceData) — UE-only backend.

Run via Invoke-UnrealPython.ps1; task JSON at $env:RSDW_UE_TASK_CONFIG:

  {
    "piece_id":       "Woodwall",
    "display_name":   "Wood Wall",
    "description":    "Simple wall used to create structures.",
    "persistence_id": "RSDWBuilds_Woodwall_v1",
    "da_pkg":         "/Game/Gameplay/BaseBuilding_New/BuildingPieces/RSDWBuilds/Woodwall",
    "da_name":        "DA_Woodwall",
    "mesh_path":      "/Game/RSDWBuilds/Woodwall/SM_Woodwall.SM_Woodwall",
    "bp_class_path":  "/Game/RSDWBuilds/Woodwall/BP_Woodwall.BP_Woodwall_C",
    "icon_path":      "/Game/RSDWBuilds/Woodwall/T_Icon_Woodwall.T_Icon_Woodwall",
    "piece_tag":      "BaseBuilding.PieceType.Base",
    "stability_row":  "Tier1_Base",
    "xp_row":         "Build_Wall_Tier1",
    "requirements":   [],          # v1: cost not supported on UE backend (free build)
    "force":          true
  }

Uses the /Script/Dominion stub class UBuildingPieceData (partial mirror of the game's
class; property names/types verified against the 0.12 archive). The pak MUST be cooked
with bUseUnversionedProperties=False so the game's full class loads our tagged subset.

DataTable hard refs (stability + XP row handles) point at editor-only placeholder
DataTables created at the GAME paths; at runtime the import paths resolve to the game's
real tables. Placeholders are never staged into the pak.

Prints RSDW_TASK_OK on success.
"""
import json
import os
import sys

import unreal

DT_STABILITY_PKG = "/Game/Gameplay/BaseBuilding_New"
DT_STABILITY_NAME = "DT_StabilityProfile"
DT_XP_PKG = "/Game/Gameplay/Progress/XPEventTables"
DT_XP_NAME = "DT_XPEvents_Building"

at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary


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


def ensure_datatable_stub(pkg, name):
    """Editor-only DataTable placeholder at the game path (hard row-handle refs)."""
    full = pkg + "/" + name
    if eal.does_asset_exist(full):
        dt = eal.load_asset(full)
        if dt is None:
            fail("existing placeholder failed to load: " + full)
        return dt
    factory = unreal.DataTableFactory()
    factory.set_editor_property("struct", unreal.StabilityProfile.static_struct())
    dt = at.create_asset(name, pkg, unreal.DataTable, factory)
    if dt is None:
        fail("failed to create DataTable placeholder " + full)
    eal.save_loaded_asset(dt)
    log("created DataTable placeholder: " + full)
    return dt


def make_row_handle(dt, row_name):
    handle = unreal.DataTableRowHandle()
    handle.set_editor_property("data_table", dt)
    handle.set_editor_property("row_name", row_name)
    return handle


def make_gameplay_tag(tag_name):
    """UE python cannot construct FGameplayTag natively; use our C++ helper
    (URSDWEditorTools::RSDWMakeTag in Source/Dominion). Tag must be registered in
    Config/DefaultGameplayTags.ini or the result is the empty tag."""
    try:
        tag = unreal.RSDWEditorTools.rsdw_make_tag(unreal.Name(tag_name))
    except Exception as e:  # noqa: BLE001
        fail("RSDWMakeTag helper unavailable (recompile Source/Dominion): %s" % e)
    if str(tag.to_string() if hasattr(tag, "to_string") else tag) in ("", "None"):
        fail("GameplayTag '%s' not registered - add it to DefaultGameplayTags.ini" % tag_name)
    return tag


def set_prop(obj, prop, value):
    try:
        obj.set_editor_property(prop, value)
    except Exception as e:  # noqa: BLE001
        fail("set %s failed: %s" % (prop, e))


def soft_obj_ref(path):
    """TSoftObjectPtr value for a possibly-unloaded asset path (game assets aren't in
    the project, so plain SoftObjectPath does not nativize into SoftObjectProperty)."""
    return unreal.SystemLibrary.conv_soft_obj_path_to_soft_obj_ref(unreal.SoftObjectPath(path))


def soft_class_ref(path):
    return unreal.SystemLibrary.conv_soft_class_path_to_soft_class_ref(unreal.SoftClassPath(path))




def ensure_item_stub(pkg_path, asset_name, class_name):
    """Editor-only item-asset placeholder at the GAME path so Requirements can hard-ref
    it; at runtime the import resolves to the game's real item. Never staged."""
    # pkg_path IS the full package path (/Game/dir/AssetName) per game convention.
    full = pkg_path
    if eal.does_asset_exist(full):
        item = eal.load_asset(full)
        if item is None:
            fail("existing item placeholder failed to load: " + full)
        return item
    cls = getattr(unreal, class_name, None)
    if cls is None:
        fail("stub class unreal.%s missing (recompile Source/Dominion)" % class_name)
    factory = unreal.DataAssetFactory()
    factory.set_editor_property("data_asset_class", cls)
    # create_asset takes the CONTAINING FOLDER; pkg_path is the full package path
    # (folder + asset name) matching the game convention.
    folder = pkg_path.rsplit("/", 1)[0] if pkg_path.endswith("/" + asset_name) else pkg_path
    item = at.create_asset(asset_name, folder, cls, factory)
    if item is None:
        fail("failed to create item placeholder " + full)
    eal.save_loaded_asset(item)
    log("created item placeholder: %s (%s)" % (full, class_name))
    return item


def build_requirements(task):
    reqs = []
    for spec in task.get("requirements", []) or []:
        item = ensure_item_stub(spec["item_pkg"], spec["item_name"], spec["item_class"])
        r = unreal.ResourceRequirement()
        r.set_editor_property("amount", int(spec["amount"]))
        r.set_editor_property("item_data", item)
        reqs.append(r)
    return reqs



def _geometry_script_api():
    """UE 5.6 Python exposes GeometryScript BP libraries by ScriptName, not C++ class name."""
    assets = getattr(unreal, "GeometryScript_AssetUtils", None)
    queries = getattr(unreal, "GeometryScript_MeshQueries", None)
    transforms = getattr(unreal, "GeometryScript_MeshTransforms", None)
    if assets and queries and transforms:
        return assets, queries, transforms
    fail("auto_fit: GeometryScripting plugin not loaded (enable GeometryScripting in .uproject)")


def _outcome_ok(outcome):
    for enum_name in ("EGeometryScriptOutcomePins", "GeometryScriptOutcomePins"):
        enum_cls = getattr(unreal, enum_name, None)
        if enum_cls is not None and outcome == enum_cls.SUCCESS:
            return True
    return str(outcome).endswith("SUCCESS")


def _box_min_max(box):
    mn = box.min
    mx = box.max
    return (mn.x, mn.y, mn.z), (mx.x, mx.y, mx.z)


def _sm_subsystem():
    try:
        return unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
    except Exception:  # noqa: BLE001
        return None


def fix_mesh_collision(sm, dyn=None):
    """copy_mesh_to_static_mesh (auto_fit) strips BodySetup collision. Regenerate from the
    fitted mesh (box/hull) via GeometryScript, with editor-subsystem fallbacks."""
    if dyn is not None:
        collision = getattr(unreal, "GeometryScript_Collision", None)
        if collision is not None:
            opts = unreal.GeometryScriptCollisionFromMeshOptions(
                auto_detect_spheres=False,
                auto_detect_capsules=False,
                auto_detect_boxes=True,
            )
            sm_opts = unreal.GeometryScriptSetStaticMeshCollisionOptions(
                mark_as_customized=True,
            )
            collision.set_static_mesh_collision_from_mesh(dyn, sm, opts, sm_opts)
            n = 0
            try:
                sc = collision.get_simple_collision_from_static_mesh(sm)
                n = collision.get_simple_collision_shape_count(sc)
            except Exception:  # noqa: BLE001
                pass
            log("auto_collision: %s -> %d shape(s) (GeometryScript)" % (sm.get_name(), n))
            eal.save_loaded_asset(sm)
            return

    sms = _sm_subsystem()
    if sms is not None:
        sms.remove_collisions(sm)
        shape = unreal.EScriptCollisionShapeType.BOX
        n = sms.add_simple_collisions(sm, shape)
        log("auto_collision: %s -> box (%d primitive(s))" % (sm.get_name(), n))
        eal.save_loaded_asset(sm)
        return

    lib = getattr(unreal, "EditorStaticMeshLibrary", None)
    if lib is not None:
        lib.remove_collisions(sm)
        shape = unreal.EScriptCollisionShapeType.BOX
        n = lib.add_simple_collisions(sm, shape)
        log("auto_collision: %s -> box (%d primitive(s), legacy lib)" % (sm.get_name(), n))
        eal.save_loaded_asset(sm)
        return

    log("WARNING: auto_collision: no collision API available in this UE session")


def set_mi_opaque(mi, two_sided=False):
    """Force OPAQUE blend on the MI. The game building master defaults to Opaque, but an
    arbitrary photoscan BaseColor texture can carry an alpha channel that a masked branch
    of the master interprets as opacity -> the piece renders transparent/torn. Forcing
    Opaque (matching how vanilla walls read) guarantees a solid surface regardless of the
    texture's alpha. Vanilla only sets OpacityMaskClipValue, so we mirror that too."""
    ov = unreal.MaterialInstanceBasePropertyOverrides()
    ov.set_editor_property("override_blend_mode", True)
    ov.set_editor_property("blend_mode", unreal.BlendMode.BLEND_OPAQUE)
    ov.set_editor_property("override_opacity_mask_clip_value", True)
    ov.set_editor_property("opacity_mask_clip_value", 0.3333)
    if two_sided:
        ov.set_editor_property("override_two_sided", True)
        ov.set_editor_property("two_sided", True)
    mi.set_editor_property("base_property_overrides", ov)


def _write_dyn_to_sm(dyn, sm, assets, recompute_normals=True, recompute_tangents=True):
    """Write DynamicMesh back to StaticMesh. Do NOT auto_repair_normals — open Fab photoscans
    are not closed meshes and repair corrupts them."""
    out_opts = unreal.GeometryScriptCopyMeshToAssetOptions()
    out_opts.set_editor_property("enable_recompute_normals", recompute_normals)
    out_opts.set_editor_property("enable_recompute_tangents", recompute_tangents)
    out_opts.set_editor_property("replace_materials", False)
    target_lod = unreal.GeometryScriptMeshWriteLOD()
    _, outcome = assets.copy_mesh_to_static_mesh(dyn, sm, out_opts, target_lod)
    if not _outcome_ok(outcome):
        fail("auto_fit: copy_mesh_to_static_mesh failed (%s)" % outcome)


def strip_photoscan_vertex_colors(dyn):
    """Game building master multiplies vertex color into BaseColor. Fab photoscans bake dark
    AO into vertex colors — replace the whole overlay with white (not blend)."""
    vc = getattr(unreal, "GeometryScript_VertexColors", None)
    if vc is None:
        log("WARNING: auto_fit: GeometryScript_VertexColors unavailable")
        return False
    white = unreal.LinearColor(1.0, 1.0, 1.0, 1.0)
    flags = unreal.GeometryScriptColorFlags()
    # b_clear_existing must be True — False only blends with existing Fab AO colors.
    vc.set_mesh_constant_vertex_color(dyn, white, flags, True)
    log("auto_fit: reset vertex colors to white")
    return True


def _log_sm_vertex_colors(sm):
    sms = _sm_subsystem()
    if sms is None:
        return
    try:
        if sms.has_vertex_colors(sm):
            log("WARNING: auto_fit: mesh still reports vertex colors after white reset")
        else:
            log("auto_fit: mesh has no vertex-color channel (OK for game building master)")
    except Exception:  # noqa: BLE001
        pass


def restore_source_mesh(task):
    """One-shot: duplicate source_mesh (Fab original) over SM_<Id>, then auto_fit runs."""
    if not task.get("restore_mesh"):
        return
    source = task.get("source_mesh", "")
    if not source:
        fail("restore_mesh: set source_mesh in piece.ini")
    source_pkg = source.rsplit(".", 1)[0]
    if not eal.does_asset_exist(source_pkg):
        fail("restore_mesh: source not found: %s" % source_pkg)
    mesh_pkg = task["mesh_path"].rsplit(".", 1)[0]
    if eal.does_asset_exist(mesh_pkg):
        eal.delete_asset(mesh_pkg)
    dup = eal.duplicate_asset(source, mesh_pkg)
    if not dup:
        fail("restore_mesh: duplicate_asset failed for %s" % source_pkg)
    log("restore_mesh: %s -> %s (clear restore_mesh in piece.ini after build)" % (source_pkg, mesh_pkg))


def fit_mesh_to_donor(task):
    """Auto-fit: bake scale+translation into the piece mesh so its bounding box exactly
    fills the DONOR mesh box (per-axis). Fixes both size AND pivot in one pass - the
    donor-clone BP snap sockets are positioned for the donor box, so a fitted mesh
    snaps like the vanilla piece regardless of how the source was authored/scanned.
    Idempotent: skips when bounds already match (2 uu tolerance). Requires the
    GeometryScripting plugin."""
    if not task.get("auto_fit", False):
        return
    fit = task.get("fit_box")
    if not fit:
        return
    mesh_pkg = task["mesh_path"].rsplit(".", 1)[0]
    sm = eal.load_asset(mesh_pkg)
    if sm is None:
        fail("auto_fit: mesh not found: " + mesh_pkg)

    tgt_min = fit["min"]
    tgt_max = fit["max"]

    assets, queries, transforms = _geometry_script_api()
    dyn = unreal.DynamicMesh()
    opts = unreal.GeometryScriptCopyMeshFromAssetOptions()
    lod = unreal.GeometryScriptMeshReadLOD()
    dyn, outcome = assets.copy_mesh_from_static_mesh(sm, dyn, opts, lod)
    if not _outcome_ok(outcome):
        fail("auto_fit: copy_mesh_from_static_mesh failed (%s)" % outcome)

    box = queries.get_mesh_bounding_box(dyn)
    cur_min, cur_max = _box_min_max(box)
    size = [cur_max[i] - cur_min[i] for i in range(3)]
    tgt_size = [tgt_max[i] - tgt_min[i] for i in range(3)]
    if min(size) <= 0.01:
        fail("auto_fit: degenerate mesh bounds")

    mesh_changed = False
    if task.get("auto_material", False):
        mesh_changed = strip_photoscan_vertex_colors(dyn)
    tol = 2.0
    needs_transform = not all(
        abs(cur_min[i] - tgt_min[i]) < tol and abs(cur_max[i] - tgt_max[i]) < tol for i in range(3))
    if needs_transform:
        scale = [tgt_size[i] / size[i] for i in range(3)]
        trans = [tgt_min[i] - cur_min[i] * scale[i] for i in range(3)]
        scale_vec = unreal.Vector(scale[0], scale[1], scale[2])
        trans_vec = unreal.Vector(trans[0], trans[1], trans[2])
        transforms.scale_mesh(dyn, scale_vec, unreal.Vector(0, 0, 0))
        transforms.translate_mesh(dyn, trans_vec)
        mesh_changed = True
        log("auto_fit: %s scaled (%.2f, %.2f, %.2f), moved (%.0f, %.0f, %.0f) -> donor box" % (
            mesh_pkg, scale[0], scale[1], scale[2], trans[0], trans[1], trans[2]))
    elif mesh_changed:
        log("auto_fit: vertex-color fix only (bounds already match donor box)")

    if mesh_changed:
        _write_dyn_to_sm(dyn, sm, assets, recompute_normals=False, recompute_tangents=False)
        if task.get("auto_material", False):
            _log_sm_vertex_colors(sm)
        eal.save_loaded_asset(sm)
    else:
        log("auto_fit: bounds already match donor box - skipping transform")
    fix_mesh_collision(sm, dyn)


MASTER_STUB_PKG = "/Game/Materials/Environment"
MASTER_STUB_NAME = "M_Standard_Env_MR_Building"


def ensure_master_stub():
    """Editor-only stub of the game building master material. Piece MIs parent to it;
    at runtime the path resolves to the game REAL master (full lighting). The stub
    cooks as a dependency but is never staged."""
    full = MASTER_STUB_PKG + "/" + MASTER_STUB_NAME
    if eal.does_asset_exist(full):
        # v1 stubs left the Normal sampler on the engine's color DefaultTexture, which
        # fails material compile (null shadermap -> black in-game). Rebuild those.
        mat = eal.load_asset(full)
        norm_ok = False
        try:
            tex = unreal.MaterialEditingLibrary.get_material_default_texture_parameter_value(mat, "Normal")
            norm_ok = tex is not None and "FlatNormal" in tex.get_path_name()
        except Exception:  # noqa: BLE001
            pass
        if norm_ok:
            return mat
        log("master stub has broken Normal default - recreating")
        eal.delete_asset(full)
    mel = unreal.MaterialEditingLibrary
    mat = at.create_asset(MASTER_STUB_NAME, MASTER_STUB_PKG, unreal.Material, unreal.MaterialFactoryNew())
    if mat is None:
        fail("failed to create master stub " + full)
    base = mel.create_material_expression(mat, unreal.MaterialExpressionTextureSampleParameter2D, -500, -100)
    base.set_editor_property("parameter_name", "BaseColor")
    mel.connect_material_property(base, "RGB", unreal.MaterialProperty.MP_BASE_COLOR)
    norm = mel.create_material_expression(mat, unreal.MaterialExpressionTextureSampleParameter2D, -500, 200)
    norm.set_editor_property("parameter_name", "Normal")
    # Default texture MUST be a normal map or the whole material fails to compile
    # ("Sampler type is Normal, should be Color for DefaultTexture") -> null shadermap
    # -> every MI in the hierarchy renders BLACK in-game.
    flat_normal = unreal.load_asset("/Engine/EngineMaterials/FlatNormal")
    if flat_normal is not None:
        norm.set_editor_property("texture", flat_normal)
    norm.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL)
    mel.connect_material_property(norm, "RGB", unreal.MaterialProperty.MP_NORMAL)
    mel.recompile_material(mat)
    eal.save_loaded_asset(mat)
    log("created master material stub: " + full)
    return mat


def is_normal_name(n):
    low = n.lower()
    return low.endswith("_n") or "normal" in low or low.endswith("_nrm") or low.endswith("_norm")


def is_orm_name(n):
    low = n.lower()
    return low.endswith("_orm") or low.endswith("_rma") or low.endswith("_arm") or "occlusion" in low


def _is_skip_texture(name, piece_id):
    low = name.lower()
    if name == "T_Icon_" + piece_id:
        return True
    if low.startswith("material"):
        return True
    if "opacity" in low or "mask" in low:
        return True
    return False


def _base_texture_score(name):
    if is_normal_name(name) or is_orm_name(name):
        return -1
    low = name.lower()
    if any(x in low for x in ("rough", "metallic", "spec", "ao", "height", "emissive")):
        return -1
    score = 0
    if any(x in low for x in ("texture_0", "_bc", "albedo", "diffuse", "basecolor", "bcc")):
        score += 10
    if "texture" in low:
        score += 5
    return score


def find_piece_textures(piece_dir, piece_id):
    base_tex = None
    base_score = -1
    norm_tex = None
    orm_tex = None
    for path in eal.list_assets(piece_dir, recursive=True):
        pkg = path.split(".")[0]
        name = pkg.rsplit("/", 1)[-1]
        if _is_skip_texture(name, piece_id):
            continue
        asset = eal.load_asset(pkg)
        if asset is None or not isinstance(asset, unreal.Texture2D):
            continue
        if is_normal_name(name):
            if norm_tex is None:
                norm_tex = asset
            continue
        if is_orm_name(name):
            if orm_tex is None:
                orm_tex = asset
            continue
        score = _base_texture_score(name)
        if score > base_score:
            base_tex = asset
            base_score = score
    return base_tex, norm_tex, orm_tex


def ensure_texture_srgb(tex):
    """Fab glTF imports often leave sRGB off or use normal-map compression on albedo."""
    if tex is None:
        return
    try:
        tex.set_editor_property("srgb", True)
        tex.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_BC7)
    except Exception:  # noqa: BLE001
        try:
            tex.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_DEFAULT)
        except Exception:  # noqa: BLE001
            pass
    try:
        tex.set_editor_property("lod_group", unreal.TextureGroup.TEXTUREGROUP_WORLD)
        tex.set_editor_property("never_stream", False)
        tex.modify()
    except Exception:  # noqa: BLE001
        pass


def _try_set_mi_scalar(mel, mi, name, value):
    try:
        mel.set_material_instance_scalar_parameter_value(mi, name, value)
    except Exception:  # noqa: BLE001
        pass


def configure_building_mi(mi, mel, base_tex, norm_tex, orm_tex):
    """Match a VANILLA building MI exactly (ground truth: MI_DK_Bricks_02_Clean, which
    parents this same master). Vanilla sets ONLY: Metallic Scale=0, AO Multiply=0.516,
    BaseColor, Normal, and OpacityMaskClipValue. It does NOT override two-sided and does
    NOT touch static switches (Support Damage / UseAO) - overriding those changes the
    shader permutation and was rendering the piece transparent/black. We add one thing
    vanilla does not need: an explicit Opaque blend override, because user photoscan
    textures may carry an alpha the master would otherwise read as opacity."""
    ensure_texture_srgb(base_tex)
    set_mi_opaque(mi)  # force Opaque + OpacityMaskClipValue (no two-sided, like vanilla)
    mel.set_material_instance_scalar_parameter_value(mi, "Metallic Scale", 0.0)
    _try_set_mi_scalar(mel, mi, "AO Multiply", 0.516)
    mel.set_material_instance_texture_parameter_value(mi, "BaseColor", base_tex)
    if norm_tex is not None:
        mel.set_material_instance_texture_parameter_value(mi, "Normal", norm_tex)
    else:
        flat = unreal.load_asset("/Engine/EngineMaterials/FlatNormal")
        if flat is not None:
            mel.set_material_instance_texture_parameter_value(mi, "Normal", flat)
    if orm_tex is not None:
        mel.set_material_instance_texture_parameter_value(mi, "ORM", orm_tex)
    mel.update_material_instance(mi)


def _cleanup_fab_import_materials(piece_dir):
    """Remove Fab import placeholder materials (material0 etc.) so they are not cooked."""
    removed = []
    for path in eal.list_assets(piece_dir, recursive=True):
        pkg = path.split(".")[0]
        name = pkg.rsplit("/", 1)[-1]
        if not name.lower().startswith("material"):
            continue
        if eal.delete_asset(pkg):
            removed.append(name)
    if removed:
        log("auto_material: removed Fab import material(s): %s" % ", ".join(removed))


def _find_fab_import_material(piece_dir):
    """Return the Fab glTF import material (material0, material1, ...) if present."""
    found = []
    for path in eal.list_assets(piece_dir, recursive=False):
        pkg = path.split(".")[0]
        name = pkg.rsplit("/", 1)[-1]
        if not name.lower().startswith("material"):
            continue
        asset = eal.load_asset(pkg)
        if asset is not None:
            found.append((name, asset))
    if not found:
        return None, None
    found.sort(key=lambda item: item[0])
    return found[0][0], found[0][1]


def apply_fab_material(task):
    """Photoscan/Fab imports: keep the imported material on the mesh (auto_material=false).
    The game building master multiplies vertex color into BaseColor, which crushes Fab
    photoscan albedo; the Fab import material renders correctly."""
    if task.get("auto_material", False):
        return
    mesh_pkg = task["mesh_path"].rsplit(".", 1)[0]
    piece_dir = mesh_pkg.rsplit("/", 1)[0]
    sm = eal.load_asset(mesh_pkg)
    if sm is None:
        fail("fab_material: mesh not found: " + mesh_pkg)
    mat_name, fab_mat = _find_fab_import_material(piece_dir)
    if fab_mat is None:
        log("WARNING: fab_material: no material0-style import in %s - mesh keeps current slot(s)" % piece_dir)
        return
    mats = list(sm.get_editor_property("static_materials"))
    if not mats:
        log("WARNING: fab_material: mesh has no material slots")
        return
    replaced = 0
    for m in mats:
        iface = m.get_editor_property("material_interface")
        if iface is not fab_mat:
            replaced += 1
        m.set_editor_property("material_interface", fab_mat)
    sm.set_editor_property("static_materials", mats)
    eal.save_loaded_asset(sm)
    eal.save_loaded_asset(fab_mat)
    log("fab_material: %d slot(s) -> %s (%d replaced)" % (len(mats), mat_name, replaced))


def _get_mi_texture_param(mel, mi, param_name):
    try:
        return mel.get_material_instance_texture_parameter_value(mi, param_name)
    except Exception:  # noqa: BLE001
        return None


def _mi_uses_building_master(mi):
    parent = mi.get_editor_property("parent")
    if parent is None:
        return False
    ppath = parent.get_path_name()
    return MASTER_STUB_NAME in ppath or "M_Standard_Env_MR_Building" in ppath


def fix_manual_building_materials(task):
    """auto_material=false: reparent each slot MI to the building master stub and
    re-apply vanilla-matching parameters. FBX/phong parents cook with invalid ShaderMaps
    -> checkered ghost + MissingMaterials in-game."""
    if task.get("auto_material", False):
        return
    mesh_pkg = task["mesh_path"].rsplit(".", 1)[0]
    piece_dir = mesh_pkg.rsplit("/", 1)[0]
    piece_id = task["piece_id"]
    sm = eal.load_asset(mesh_pkg)
    if sm is None:
        fail("manual_materials: mesh not found: " + mesh_pkg)

    ensure_master_stub()
    master = eal.load_asset(MASTER_STUB_PKG + "/" + MASTER_STUB_NAME)
    mel = unreal.MaterialEditingLibrary
    mats = list(sm.get_editor_property("static_materials"))
    if not mats:
        log("WARNING: manual_materials: mesh has no material slots")
        return

    fixed = 0
    for idx, m in enumerate(mats):
        iface = m.get_editor_property("material_interface")
        if iface is None:
            log("WARNING: manual_materials: slot %d has no material" % idx)
            continue

        mi = iface if isinstance(iface, unreal.MaterialInstanceConstant) else None
        if mi is None:
            mi_name = "MI_%s_Slot%d" % (piece_id, idx)
            mi_full = piece_dir + "/" + mi_name
            if eal.does_asset_exist(mi_full):
                eal.delete_asset(mi_full)
            mi = at.create_asset(
                mi_name, piece_dir, unreal.MaterialInstanceConstant,
                unreal.MaterialInstanceConstantFactoryNew())
            if mi is None:
                log("WARNING: manual_materials: failed to create %s" % mi_name)
                continue
            mi.set_editor_property("parent", master)
            m.set_editor_property("material_interface", mi)
            fixed += 1
        elif not _mi_uses_building_master(mi):
            mi.set_editor_property("parent", master)
            fixed += 1

        base_tex = _get_mi_texture_param(mel, mi, "BaseColor")
        norm_tex = _get_mi_texture_param(mel, mi, "Normal")
        orm_tex = _get_mi_texture_param(mel, mi, "ORM")
        if base_tex is None:
            log("WARNING: manual_materials: %s slot %d has no BaseColor texture assigned"
                % (mi.get_name(), idx))
            eal.save_loaded_asset(mi)
            continue

        configure_building_mi(mi, mel, base_tex, norm_tex, orm_tex)
        eal.save_loaded_asset(base_tex)
        if norm_tex is not None:
            eal.save_loaded_asset(norm_tex)
        if orm_tex is not None:
            eal.save_loaded_asset(orm_tex)
        eal.save_loaded_asset(mi)
        fixed += 1

    sm.set_editor_property("static_materials", mats)
    eal.save_loaded_asset(sm)
    log("manual_materials: processed %d slot(s), updated %d on %s"
        % (len(mats), fixed, sm.get_name()))


def fix_materials(task):
    """Auto-material: ensure every mesh slot uses an MI parented to the game-master stub
    (custom/imported masters cannot compile game shaders -> black at night). Uses the
    piece folder textures (name *_N/*_Normal = normal map)."""
    if not task.get("auto_material", False):
        return
    mesh_pkg = task["mesh_path"].rsplit(".", 1)[0]
    piece_dir = mesh_pkg.rsplit("/", 1)[0]
    piece_id = task["piece_id"]
    sm = eal.load_asset(mesh_pkg)
    if sm is None:
        fail("auto_material: mesh not found: " + mesh_pkg)

    ensure_master_stub()
    mats = list(sm.get_editor_property("static_materials"))
    if not mats:
        log("WARNING: auto_material: mesh has no material slots")
        return

    base_tex, norm_tex, orm_tex = find_piece_textures(piece_dir, piece_id)
    if base_tex is None:
        log("WARNING: auto_material found no base-color texture in %s - skipping" % piece_dir)
        return

    mel = unreal.MaterialEditingLibrary
    mi_name = "MI_%s_Auto" % piece_id
    mi_full = piece_dir + "/" + mi_name
    # Regenerate FRESH every build: loading and mutating an existing MI leaves stale
    # parameter overrides from prior runs (e.g. two-sided / Hue Shift), which silently
    # change the game master's shader. Delete then recreate so only the vanilla-matching
    # set is present.
    if eal.does_asset_exist(mi_full):
        eal.delete_asset(mi_full)
    mi = at.create_asset(mi_name, piece_dir, unreal.MaterialInstanceConstant,
                         unreal.MaterialInstanceConstantFactoryNew())
    if mi is None:
        fail("failed to create " + mi_full)
    master = eal.load_asset(MASTER_STUB_PKG + "/" + MASTER_STUB_NAME)
    mi.set_editor_property("parent", master)
    configure_building_mi(mi, mel, base_tex, norm_tex, orm_tex)
    eal.save_loaded_asset(base_tex)
    eal.save_loaded_asset(mi)

    replaced = 0
    new_mats = []
    for m in mats:
        iface = m.get_editor_property("material_interface")
        if iface is not mi:
            replaced += 1
        m.set_editor_property("material_interface", mi)
        new_mats.append(m)
    sm.set_editor_property("static_materials", new_mats)
    eal.save_loaded_asset(sm)
    _cleanup_fab_import_materials(piece_dir)
    log("auto_material: %d slot(s) -> %s (%d replaced; BaseColor=%s, Normal=%s, ORM=%s)" % (
        len(new_mats), mi_name, replaced, base_tex.get_name(),
        norm_tex.get_name() if norm_tex else "FlatNormal",
        orm_tex.get_name() if orm_tex else "none"))


def resolve_icon(task):
    """Return a LOADED UTexture2D for DisplayIcon (loaded objects always nativize into
    TSoftObjectPtr; unloadable game paths silently serialize as EMPTY - verified on
    ChurchWall). Prefers the piece's own T_Icon_<Id>; else imports the kit's default
    placeholder PNG as T_Icon_<Id> so every piece has a distinguishable menu tile."""
    icon_path = task.get("icon_path", "")
    icon_pkg = icon_path.rsplit(".", 1)[0] if icon_path else ""
    if icon_pkg and eal.does_asset_exist(icon_pkg):
        tex = eal.load_asset(icon_pkg)
        if tex is not None:
            return tex, icon_pkg
    png = task.get("icon_import_png", "")
    if png and os.path.exists(png):
        dest_pkg = task["icon_dest_pkg"]
        dest_name = task["icon_dest_name"]
        imp = unreal.AssetImportTask()
        imp.filename = png
        imp.destination_path = dest_pkg
        imp.destination_name = dest_name
        imp.automated = True
        imp.replace_existing = True
        imp.save = True
        at.import_asset_tasks([imp])
        full = dest_pkg + "/" + dest_name
        tex = eal.load_asset(full)
        if tex is not None:
            log("imported default icon -> %s" % full)
            return tex, full
    log("WARNING: no usable icon (menu tile will have no image)")
    return None, None


def main():
    task = read_task()
    restore_source_mesh(task)
    fit_mesh_to_donor(task)
    apply_fab_material(task)
    fix_manual_building_materials(task)
    fix_materials(task)
    da_pkg = task["da_pkg"]
    da_name = task["da_name"]
    da_full = da_pkg + "/" + da_name
    force = bool(task.get("force", True))

    if eal.does_asset_exist(da_full):
        if not force:
            log("%s exists - skipping (force=false)" % da_full)
            print("RSDW_TASK_OK")
            return
        eal.delete_asset(da_full)

    # BP class must exist (generated in Phase 1 / authored).
    bp_class_path = task["bp_class_path"]
    bp_asset_path = bp_class_path.rsplit(".", 1)[0]
    bp_asset = eal.load_asset(bp_asset_path)
    if bp_asset is None:
        fail("BuildableActor blueprint not found: " + bp_asset_path)
    bp_class = bp_asset.generated_class()
    if bp_class is None:
        fail("blueprint has no generated class: " + bp_asset_path)

    dt_stab = ensure_datatable_stub(DT_STABILITY_PKG, DT_STABILITY_NAME)
    dt_xp = ensure_datatable_stub(DT_XP_PKG, DT_XP_NAME)

    factory = unreal.DataAssetFactory()
    factory.set_editor_property("data_asset_class", unreal.BuildingPieceData)
    da = at.create_asset(da_name, da_pkg, unreal.BuildingPieceData, factory)
    if da is None:
        fail("failed to create " + da_full)

    set_prop(da, "display_name", task["display_name"])
    set_prop(da, "description", task.get("description", ""))
    set_prop(da, "persistence_id", task["persistence_id"])
    icon_tex, icon_full = resolve_icon(task)
    if icon_tex is not None:
        set_prop(da, "display_icon", icon_tex)
    set_prop(da, "piece_tag", make_gameplay_tag(task["piece_tag"]))
    set_prop(da, "building_stability_profile_row_handle",
             make_row_handle(dt_stab, task["stability_row"]))
    set_prop(da, "build_xp_event", make_row_handle(dt_xp, task["xp_row"]))

    proxy = unreal.BuildingPieceProxyData()
    proxy.set_editor_property("proxy_mesh", soft_obj_ref(task["mesh_path"]))
    set_prop(da, "building_piece_proxy_data", proxy)

    try:
        da.set_editor_property("buildable_actor", soft_class_ref(bp_class_path))
    except Exception:  # noqa: BLE001
        set_prop(da, "buildable_actor", bp_class)

    reqs = build_requirements(task)
    set_prop(da, "requirements", reqs)
    if reqs:
        log("requirements: %d entr%s" % (len(reqs), "y" if len(reqs) == 1 else "ies"))

    if not eal.save_loaded_asset(da):
        fail("save failed for " + da_full)

    log("generated %s (BuildableActor=%s, stability=%s, xp=%s, tag=%s)" % (
        da_full, bp_class_path, task["stability_row"], task["xp_row"], task["piece_tag"]))
    print("RSDW_TASK_OK")


if __name__ == "__main__":
    main()
