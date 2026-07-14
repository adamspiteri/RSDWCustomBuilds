# Naming conventions

Follow these exactly so **`Build-Piece.bat`** can find your assets without extra config.

---

## Piece folder name

| Rule | Example |
|------|---------|
| PascalCase, letters + digits only | `StoneWall`, `LumbridgeCastle`, `MyRoom01` |
| Folder path | `Content/RSDWBuilds/StoneWall/` |
| Do **not** start with `_` | `_Test` is ignored by build |

The folder name = **PieceId** used everywhere (`SM_`, `DA_`, pak paths).

---

## Required files

| Asset | Name | Notes |
|-------|------|-------|
| Config | `piece.ini` | Display name + donor template |
| Static mesh | `SM_<PieceId>` | One mesh per placeable piece |
| Data (generated) | `DA_<PieceId>` | Created by build tool — do not hand-edit |
| Blueprint (generated) | `BP_<PieceId>` | Created by build tool |

---

## Optional files

| Asset | Name | Notes |
|-------|------|-------|
| Icon | `T_Icon_<PieceId>` | 256×256-ish; defaults to grey placeholder |
| Material instance | `MI_<PieceId>_<SlotLabel>` | e.g. `MI_StoneWall_Walls`, `MI_StoneWall_Roof` |
| Color texture | `T_<Label>` | e.g. `T_Walls`, `T_Roof` |
| Normal map | `T_<Label>_N` | Compression = **Normalmap** in UE |

Assign **Material Instances on the static mesh slots** in the Static Mesh Editor before building.

---

## Material slots

- Slot **index** = order on the mesh (Element 0, 1, 2…).
- Slot **label** in the MI name is for humans only (`MI_MyCastle_Roof` → slot using roof MI).
- For vanilla look without custom textures, assign shipped kit MIs:
  - `/Game/Art/Env/Base_Building/BuildingKit/Tier1/Materials/MI_Modular_Set_Tier1_Wall`
  - `MI_Modular_Set_Tier1_Roof`, `MI_Modular_Set_Tier1_Floor`, `MI_Modular_Set_Tier_Trim`

Parent shader for custom MIs: **`M_Standard_Env_MR_Building`**

---

## `piece.ini` format

```ini
[ piece ]
display_name = Stone Wall
donor = foundation_large
persistence_id = auto
cost_wood = 0
menu_category = foundations
```

### `donor` values (clone vanilla snap/collision behaviour)

| Value | Vanilla source | Footprint |
|-------|----------------|-----------|
| `foundation_large` | `DA_T1_Foundation_Large` | 300×300 cm |
| `foundation_med` | `DA_T1_Foundation_Med` | 150×150 cm |
| `wall_large` | `DA_T1_Wall_Large` | wall panel |
| `floor_large` | `DA_T1_Floor_Large` | floor tile |
| `prop` | foundation donor, snaps optional | large meshes / castles |

Use **`prop`** for whole-castle or oversized meshes (weak snapping, single persistence blob).

### `persistence_id`

- `auto` → build tool writes `RSDWBuilds_<PieceId>_v1`
- Must stay **unique** per piece; bump `_v2` if you change save identity

---

## Game paths (after pack)

All assets mount under:

```
/Game/RSDWBuilds/<PieceId>/SM_<PieceId>
/Game/RSDWBuilds/<PieceId>/DA_<PieceId>
```

Pak file: **`RSDragonwilds-Z_RSDWCustomBuilds_P`** (`.pak` + `.utoc` + `.ucas`)

---

## Checklist before Build-Piece

- [ ] Mesh pivot **bottom-center**, base on Z=0
- [ ] Collision box on static mesh
- [ ] Every material slot has an **MI** assigned (not default grey)
- [ ] `piece.ini` present
- [ ] Saved all assets in UE (Ctrl+Shift+S)
