# piece.json

`piece.json` is the raw-file input format for the Nexus Builder Manager.

Place it beside a model file and optional textures:

```text
Pieces/MyStoneWall/
  piece.json
  model.fbx
  textures/
    basecolor.png
    normal.png
    roughness.png
    icon.png
```

Minimal example:

```json
{
  "id": "MyStoneWall",
  "displayName": "My Stone Wall",
  "donor": "foundation_large",
  "autoCatalogueIndex": true,
  "model": "model.fbx",
  "textures": {
    "baseColor": "textures/basecolor.png",
    "normal": "textures/normal.png",
    "roughness": "textures/roughness.png"
  }
}
```

Important fields:

- `id`: PascalCase asset id. The tool creates `/Game/RSDWBuilds/<id>`.
- `donor`: placement/snap behavior to clone: `foundation_large`, `foundation_med`, `wall_large`, `floor_large`, or `prop`.
- `autoCatalogueIndex`: recommended. The manager assigns the next free index starting at `651`.
- `materialMode`: `custom` uses cooked custom shaders and the generated `pakchunk` shader library.
- `model`: relative path to `.fbx` or `.obj`.
- `textures`: relative paths to optional texture files.
- `materials`: optional per-slot texture mapping for multi-material meshes.

The JSON schema lives at `Templates/piece.schema.json`, and a full sample lives at `Templates/piece.example.json`.
