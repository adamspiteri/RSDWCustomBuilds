Custom menu icons
=================

Drop a PNG (or JPG) here named after the piece id to use it as the
tile image in the F7 "Custom Building" menu.

  Icons\Stonewall.png      <- used for the "Stonewall" piece

Rules:
- File name (minus extension) must match the piece "id" exactly, e.g.
  Stonewall.png for id = "Stonewall". Case matters on some setups.
- Square images look best (e.g. 256x256 or 512x512).
- Supported: .png, .jpg, .jpeg, .bmp (PNG recommended).

The image is loaded at runtime via UE's ImportFileAsTexture2D, so you do
NOT need to re-cook or repack anything -- just drop the file and reopen
the menu (F7).

If no matching file is found here, the menu falls back to the cooked
icon, then to the stone wall texture.

This folder is merge-copied on deploy (existing files are never deleted),
so an icon you drop into the live mod folder survives future deploys.
