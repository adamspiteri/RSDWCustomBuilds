# Player install — RSDW Custom Builds

No Unreal Engine required.

---

## Requirements

- RuneScape: Dragonwilds (Steam)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) installed for your game version

---

## Install base mod (once)

1. Extract to game folder:

   ```
   <Dragonwilds>/RSDragonwilds/Binaries/Win64/ue4ss/Mods/RSDWBlankMenu/
   ```

2. Add **`RSDWBlankMenu : 1`** to `ue4ss/Mods/mods.txt` if not auto-enabled.

---

## Install a creator pak

Copy the pak trio to:

```
<Dragonwilds>/RSDragonwilds/Content/Paks/
```

- `RSDragonwilds-Z_RSDWCustomBuilds_P.pak`
- `RSDragonwilds-Z_RSDWCustomBuilds_P.utoc`
- `RSDragonwilds-Z_RSDWCustomBuilds_P.ucas`

And the registration file to:

```
<Dragonwilds>/RSDragonwilds/Plugins/Amd/FSR/AssetRegistry.bin
```

The registration file is what makes the game load the pieces **natively** at boot
(they keep working even if UE4SS breaks after a game update).

If the creator shipped a **separate pak name**, copy their trio instead — only one should use the same basename unless the creator documents overrides.

---

## Uninstall

Remove **both together**: the pak trio AND `Plugins/Amd/FSR/AssetRegistry.bin`.
Placed custom pieces turn into plain walls on the next load. If you reinstall the
mod later, the mod restores your custom pieces automatically (piece journal).

---

## In game

1. **Full restart** after installing paks.
2. Progress to **Tier 1 building** (crafting bench unlock).
3. Open the game's normal build mode → new pieces appear in the **vanilla build menu**.

Pieces **persist** in your base save like vanilla building blocks.

---

## Multiplayer / dedicated server

Server and every client need the **same pak trio** and UE4SS mod folder.
