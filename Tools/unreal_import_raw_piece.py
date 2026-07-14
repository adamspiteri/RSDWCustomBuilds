import json
import os
import sys

import unreal


def fail(message):
    unreal.log_error(message)
    sys.exit(1)


def read_config():
    path = os.environ.get("RSDW_RAW_IMPORT_CONFIG")
    if not path or not os.path.exists(path):
        fail("RSDW_RAW_IMPORT_CONFIG is missing or invalid")
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def import_asset(source, destination_path, destination_name):
    if not source:
        return None
    source = os.path.abspath(source)
    if not os.path.exists(source):
        fail(f"Import source missing: {source}")

    task = unreal.AssetImportTask()
    task.filename = source
    task.destination_path = destination_path
    task.destination_name = destination_name
    task.automated = True
    task.replace_existing = True
    task.save = True

    ext = os.path.splitext(source)[1].lower()
    if ext in (".fbx", ".obj"):
        options = unreal.FbxImportUI()
        options.import_mesh = True
        options.import_as_skeletal = False
        options.import_materials = False
        options.import_textures = False
        options.static_mesh_import_data.combine_meshes = True
        task.options = options

    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    if not task.imported_object_paths:
        fail(f"Unreal imported no objects from {source}")
    return unreal.EditorAssetLibrary.load_asset(task.imported_object_paths[0])


def create_material(folder, piece_id, material_spec, fallback_textures):
    label = material_spec.get("name") or "Main"
    safe_label = "".join(ch for ch in label if ch.isalnum()) or "Main"
    material_name = f"M_{piece_id}_{safe_label}"
    material_path = f"{folder}/{material_name}.{material_name}"

    material = unreal.EditorAssetLibrary.load_asset(material_path)
    if not material:
        material = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
            material_name,
            folder,
            unreal.Material,
            unreal.MaterialFactoryNew(),
        )
    if not material:
        fail(f"Could not create material {material_path}")

    def texture_path(key, suffix):
        rel = material_spec.get(key) or fallback_textures.get(key)
        if not rel:
            return None
        tex_name = f"T_{piece_id}_{safe_label}_{suffix}"
        return rel, tex_name

    tex_assets = {}
    for key, suffix in (("baseColor", "BaseColor"), ("normal", "Normal"), ("roughness", "Roughness")):
        item = texture_path(key, suffix)
        if item:
            tex_assets[key] = import_asset(item[0], folder, item[1])

    mel = unreal.MaterialEditingLibrary
    mel.delete_all_material_expressions(material)

    if tex_assets.get("baseColor"):
        sample = mel.create_material_expression(material, unreal.MaterialExpressionTextureSample, -500, 0)
        sample.texture = tex_assets["baseColor"]
        sample.sampler_type = unreal.MaterialSamplerType.SAMPLERTYPE_COLOR
        mel.connect_material_property(sample, "RGB", unreal.MaterialProperty.MP_BASE_COLOR)

    if tex_assets.get("normal"):
        sample = mel.create_material_expression(material, unreal.MaterialExpressionTextureSample, -500, 220)
        sample.texture = tex_assets["normal"]
        sample.sampler_type = unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL
        mel.connect_material_property(sample, "RGB", unreal.MaterialProperty.MP_NORMAL)

    if tex_assets.get("roughness"):
        sample = mel.create_material_expression(material, unreal.MaterialExpressionTextureSample, -500, 440)
        sample.texture = tex_assets["roughness"]
        sample.sampler_type = unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR
        mel.connect_material_property(sample, "R", unreal.MaterialProperty.MP_ROUGHNESS)
    else:
        roughness = mel.create_material_expression(material, unreal.MaterialExpressionConstant, -220, 440)
        roughness.r = 0.8
        mel.connect_material_property(roughness, "", unreal.MaterialProperty.MP_ROUGHNESS)

    usage = getattr(unreal.MaterialUsage, "MATUSAGE_INSTANCED_STATIC_MESHES", None)
    if usage is None:
        usage = getattr(unreal.MaterialUsage, "INSTANCED_STATIC_MESHES", None)
    if usage is not None:
        unreal.MaterialEditingLibrary.set_material_usage(material, usage)

    mel.layout_material_expressions(material)
    mel.recompile_material(material)
    unreal.EditorAssetLibrary.save_loaded_asset(material, False)
    return material


def main():
    cfg = read_config()
    piece = cfg["piece"]
    piece_id = piece["id"]
    folder = f"/Game/RSDWBuilds/{piece_id}"
    raw_root = cfg["rawRoot"]

    unreal.EditorAssetLibrary.make_directory(folder)

    model_path = os.path.join(raw_root, piece["model"])
    mesh = import_asset(model_path, folder, f"SM_{piece_id}")
    if not mesh:
        fail("Static mesh import failed")

    scale = float(piece.get("scale") or 1.0)
    if scale != 1.0:
        unreal.log_warning("Scale is recorded in piece.json but mesh import-time scaling is not applied yet; scale in DCC/UE if needed.")

    textures = piece.get("textures") or {}
    materials = piece.get("materials") or [{"slot": 0, "name": "Main"}]
    for mat_spec in materials:
        material = create_material(folder, piece_id, mat_spec, textures)
        slot = int(mat_spec.get("slot", 0))
        mesh.set_material(slot, material)

    icon = textures.get("icon")
    if icon:
        import_asset(os.path.join(raw_root, icon), folder, f"T_Icon_{piece_id}")

    unreal.EditorAssetLibrary.save_loaded_asset(mesh, False)
    unreal.EditorAssetLibrary.save_directory(folder, only_if_is_dirty=False, recursive=True)
    unreal.log(f"Imported raw RSDW piece {piece_id} into {folder}")


if __name__ == "__main__":
    main()
