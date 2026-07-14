# Nexus Builder Manager

The Nexus-facing workflow has two modes.

## GUI Manager (included pre-built)

Creators download the **Modder Kit** with `RSDWCustomBuildsManager.exe` already built in. Double-click:

```bat
Tools\Run-Manager-GUI.bat
```

On first launch, the GUI opens a **setup wizard** for game path, Unreal 5.6, retoc, and UAssetGUI paths. It saves `Tools\mod.config.ini` for you — no need to run `Setup.bat` or edit the INI by hand. Use **Settings** any time to change paths.

**Publisher note:** build the EXE once before zipping the Modder Kit (`Tools\Build-Manager-Exe.bat` → `Tools\Prepare-NexusRelease.bat`). End users never compile the manager.

The GUI can check setup, scan pieces, import/build a raw `piece.json` folder, install a prebuilt pack, rollback the last install, and show command logs. It also shows a lightweight `piece.json` and icon preview. Accurate 3D/material preview still happens in Unreal or in-game.

## Install Pack

For normal players who download prebuilt packs:

```bat
Tools\Manager.bat install-pack C:\Downloads\SomeRSDWPiecePack
```

The manager checks the game path, backs up the current install, copies the pak trio and shader chunks, and installs the UE4SS runtime folder if the pack includes one.

## Build From Files

For creators or users who have Unreal Engine 5.6 installed:

```bat
Tools\Manager.bat check
Tools\Manager.bat build-from-files C:\MyPieces\MyStoneWall
```

The input folder must contain `piece.json` plus the model/textures it references. The manager imports the model into the UE project, cooks it with Unreal CLI, generates DA/BP/catalogue data, packs IoStore files, creates shader chunks for custom materials, and deploys to the game.

## Common Commands

```bat
Tools\Run-Manager-GUI.bat
Tools\Manager.bat check
Tools\Manager.bat import-piece C:\MyPieces\MyStoneWall
Tools\Manager.bat build MyStoneWall
Tools\Manager.bat build-all
Tools\Manager.bat install-pack C:\Downloads\PackFolder
Tools\Manager.bat rollback
```

## What Gets Backed Up

Before installs and pak deploys, the manager backs up:

- `RSDragonwilds-Z_RSDWCustomBuilds_P.*`
- `pakchunk*-Windows_P.*`
- the UE4SS `RSDWCustomBuilds` mod folder

Backups are stored under `Build/_install_backups/`.
