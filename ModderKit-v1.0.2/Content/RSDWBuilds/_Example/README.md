# Example piece folder

1. Copy `Templates/piece.ini` here and rename the folder to your **PieceId** (PascalCase).
2. In Unreal, create **`SM_<PieceId>`** in this folder.
3. Assign **Material Instances** on mesh slots (see `Docs/NAMING.md`).
4. Run **`Tools\Build-Piece.bat <PieceId>`**.

This `_Example` folder is ignored by the build script (starts with `_`).

Copy this folder as a starting point:

```
Tools\Build-Piece.bat MyNewPiece
```

after creating `Content/RSDWBuilds/MyNewPiece/` with assets saved in UE.
