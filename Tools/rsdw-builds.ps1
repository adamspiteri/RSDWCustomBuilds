param(
    [Parameter(Position = 0)]
    [string]$Command = "help",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = "Stop"
$Lib = Join-Path $PSScriptRoot "lib"

function Get-Cfg {
    return & "$Lib\Read-Config.ps1"
}

function Invoke-GenerateCatalogue {
    param([string]$PieceName)
    $cfg = Get-Cfg
    if ($cfg.BuildBackend -eq "ue") {
        & "$Lib\Generate-Catalogue-Retoc.ps1" -ConfigPath $cfg.ConfigPath -PieceName $PieceName
    } else {
        & "$Lib\Generate-Catalogue012.ps1" -PieceName $PieceName
    }
}

function Invoke-GenerateBP {
    # Backend switch: [build] backend = ue -> in-editor Python; anything else -> RSDWAssetCli path.
    param([string]$PieceName)
    $cfg = Get-Cfg
    if ($cfg.BuildBackend -eq "ue") {
        & "$Lib\Generate-PieceBlueprint-UE.ps1" -PieceName $PieceName
    } else {
        & "$Lib\Generate-PieceBlueprint.ps1" -PieceName $PieceName
    }
}

function Invoke-GenerateDA {
    param([string]$PieceName)
    $cfg = Get-Cfg
    if ($cfg.BuildBackend -eq "ue") {
        & "$Lib\Generate-PieceData-UE.ps1" -PieceName $PieceName
        # Donor-behavior BP clone (snapping/colliders/stability). Regenerated EVERY build:
        # the editor BP (generic base parent) can neither snap nor pass placement checks;
        # the PakRaw clone replaces it at staging.
        & "$Lib\Generate-PieceBlueprint-Retoc.ps1" -PieceName $PieceName
    } else {
        & "$Lib\Generate-PieceData.ps1" -PieceName $PieceName
    }
}

function Get-StonewallMaterialMode {
    $mode = $env:RSDW_STONEWALL_MATERIAL_MODE
    if ([string]::IsNullOrWhiteSpace($mode)) { return "Custom" }
    if ($mode -notin @("Vanilla", "Custom")) {
        throw "Invalid RSDW_STONEWALL_MATERIAL_MODE=$mode (expected Vanilla or Custom)"
    }
    return $mode
}

function Write-RsdwProgress {
    param(
        [ValidateRange(0, 100)]
        [int]$Percent,
        [string]$Message
    )
    Write-Output ("RSDW_PROGRESS|{0}|{1}" -f $Percent, $Message)
}

function Invoke-BuildPackDeploy {
    param([string]$PieceName = "")

    Write-RsdwProgress 45 "Updating build catalogue"
    Invoke-GenerateCatalogue -PieceName $PieceName

    # Native piece registration: export the filtered premade AssetRegistry so the
    # game's own AssetManager scan registers the pieces (no Lua). UE backend only:
    # CLI-made DAs live in PakRaw, not the editor project, so there is nothing to
    # export there (those builds keep relying on the Lua runtime registration).
    $cfg = Get-Cfg
    if ($cfg.BuildBackend -eq "ue") {
        Write-RsdwProgress 47 "Exporting asset registry (native registration)"
        & "$Lib\Generate-AssetRegistry.ps1" -ConfigPath $cfg.ConfigPath
    }

    Write-RsdwProgress 48 "Cooking assets (slowest step — please wait)"
    & "$Lib\Cook-Windows.ps1"

    $matMode = Get-StonewallMaterialMode
    Write-RsdwProgress 72 "Applying materials"
    if ($PieceName) {
        & "$Lib\Patch-CookedStonewallMaterial.ps1" -PieceName $PieceName -MaterialMode $matMode
    } else {
        & "$Lib\Patch-CookedStonewallMaterial.ps1" -MaterialMode $matMode
    }

    Write-RsdwProgress 76 "Writing manifest"
    & "$Lib\Write-Manifest.ps1"

    Write-RsdwProgress 80 "Packing mod files"
    if ($PieceName) {
        & "$Lib\Pack-IoStore.ps1" -PieceName $PieceName
    } else {
        & "$Lib\Pack-IoStore.ps1"
    }

    if ($matMode -eq "Custom") {
        Write-RsdwProgress 88 "Packing shader chunk"
        & "$Lib\Pack-ShaderChunk.ps1" -ChunkId 651
    }

    Write-RsdwProgress 92 "Deploying pak to game"
    Deploy-Pak

    Write-RsdwProgress 96 "Deploying runtime mod"
    & "$Lib\Deploy-BlankMenu.ps1"

    Write-RsdwProgress 100 "Build complete"
}

function Show-Help {
    $cfgPath = Join-Path $PSScriptRoot "mod.config.ini"
    @"
RSDW Custom Builds - rsdw-builds.ps1

  setup              Copy mod.config.ini.template if missing
  check              Validate game, UE4SS, Unreal 5.6, retoc, UAssetGUI
  new-piece <Id> [Display Name] [donor]  Create Content/RSDWBuilds/<Id>/ + piece.ini
  import-piece <FolderWithPieceJson>      Import raw FBX/OBJ/textures via Unreal CLI
  build-from-files <FolderWithPieceJson>  Import raw files, build, pack, deploy
  scan               List pieces under builds_folder or Content/RSDWBuilds
  scan-json          Machine-readable piece list (Manager UI)
  sync-builds        Copy builds_folder -> Content/RSDWBuilds
  build <PieceId>    Cook + generate data + pack + deploy one piece
  build-override <PieceId>  Override registered vanilla slot (stable, recommended)
  build-all          Build every valid piece folder
  cook               UE Windows cook only
  pack [PieceId]     Pack cooked content (all or one piece)
  install-pack <Folder> Install a prebuilt Nexus pack
  rollback [BackupDir]  Restore last install backup
  manifest           Regenerate Mod/pieces.json
  deploy             Deploy RSDWBlankMenu (F7 mod) + disable legacy Lua mod
  deploy-pak         Copy pak trio to game Paks

Config: $cfgPath
"@
}

function Ensure-Config {
    $ini = Join-Path $PSScriptRoot "mod.config.ini"
    if (Test-Path $ini) { return }
    $tpl = Join-Path $PSScriptRoot "mod.config.ini.template"
    Copy-Item $tpl $ini
    Write-Host "Created mod.config.ini - edit paths, then re-run."
    exit 0
}

function Deploy-Pak {
    $cfg = Get-Cfg
    $src = $cfg.BuildDir
    $dst = $cfg.GamePaksDir
    $base = $cfg.PakBasename
    & "$Lib\Backup-Install.ps1" -ConfigPath $cfg.ConfigPath -Reason "deploy-pak" | Out-Null
    foreach ($ext in @(".pak", ".utoc", ".ucas")) {
        $f = Join-Path $src "$base$ext"
        if (-not (Test-Path $f)) { throw "Missing $f - run pack first." }
        $dest = Join-Path $dst "$base$ext"
        try {
            Copy-Item $f $dest -Force -ErrorAction Stop
            Write-Host "Copied $base$ext -> Paks/"
        } catch [System.IO.IOException] {
            throw "Could not copy $base$ext to the game Paks folder (file in use). Close Dragonwilds completely, then run Build All again or deploy-pak."
        }
    }
    if ((Get-StonewallMaterialMode) -eq "Custom") {
        Get-ChildItem -Path $src -File -Filter "pakchunk*-Windows_P.*" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dst $_.Name) -Force
            Write-Host "Copied $($_.Name) -> Paks/"
        }
    } else {
        Get-ChildItem -Path $dst -File -Filter "pakchunk651-Windows_P.*" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Host "Removed stale shader chunk $($_.Name)"
        }
    }

    # Native registration: deploy the premade AssetRegistry next to the pak. Hosted in
    # the FSR plugin dir - FSR ships in every install, is always enabled, can contain
    # content, and ships no registry of its own; the engine merges every enabled
    # content plugin's AssetRegistry.bin at boot. MUST travel with the pak: registry
    # without pak = rows pointing at missing packages. Uninstall = delete BOTH.
    $regSrc = Join-Path $src "AssetRegistry.bin"
    if (Test-Path -LiteralPath $regSrc) {
        $regDir = Join-Path $cfg.GameRoot "Plugins\Amd\FSR"
        New-Item -ItemType Directory -Force -Path $regDir | Out-Null
        Copy-Item -LiteralPath $regSrc -Destination (Join-Path $regDir "AssetRegistry.bin") -Force
        Write-Host "Copied AssetRegistry.bin -> Plugins/Amd/FSR/ (native piece registration)"
    }
}

switch ($Command.ToLower()) {
    "setup" { Ensure-Config }
    "check" {
        Ensure-Config
        & "$Lib\Test-Setup.ps1" | Out-Null
    }
    "new-piece" {
        Ensure-Config
        if (-not $Rest -or $Rest.Count -eq 0) {
            & "$Lib\New-Piece.ps1" -Interactive
        } else {
            $name = $Rest[0]
            $display = $Rest[1]
            $donor = if ($Rest[2]) { $Rest[2] } else { "foundation_large" }
            & "$Lib\New-Piece.ps1" -PieceName $name -DisplayName $display -Donor $donor
        }
    }
    "import-piece" {
        Ensure-Config
        $folder = $Rest[0]
        if (-not $folder) { throw 'Usage: import-piece [FolderWithPieceJson]' }
        & "$Lib\Import-RawPiece.ps1" -PieceFolder $folder
    }
    "build-from-files" {
        Ensure-Config
        $folder = $Rest[0]
        if (-not $folder) { throw 'Usage: build-from-files [FolderWithPieceJson]' }
        $result = & "$Lib\Import-RawPiece.ps1" -PieceFolder $folder
        if (-not $result.Id) { throw "Import did not return a piece id" }
        & "$PSCommandPath" build $result.Id
    }
    "scan" {
        Ensure-Config
        $cfg = Get-Cfg
        $scanRoot = if ($cfg.BuildsFolder) { $cfg.BuildsFolder } else { $cfg.ContentRoot }
        $pieces = & "$Lib\Scan-Pieces.ps1" -ContentRoot $scanRoot
        if ($pieces.Count -eq 0) { Write-Host "No pieces found."; break }
        $pieces | Format-Table Id, DisplayName, Donor, CatalogueIndex, MaterialMode, HasStaticMesh, HasBlueprint -AutoSize
    }
    "scan-json" {
        Ensure-Config
        $cfg = Get-Cfg
        # Manager UI: scan Content/RSDWBuilds where SM_* lives (Builds/ is piece.ini source only).
        & "$Lib\Ensure-PieceConfig.ps1" -Quiet | Out-Null
        $pieces = & "$Lib\Scan-Pieces.ps1" -ContentRoot $cfg.ContentRoot -Quiet
        $rows = @($pieces | Select-Object Id, DisplayName, Donor, CatalogueIndex, HasStaticMesh, HasBlueprint, NativePlacement)
        if ($rows.Count -eq 0) {
            Write-Output '[]'
        } else {
            Write-Output (ConvertTo-Json -InputObject $rows -Compress)
        }
    }
    "sync-builds" {
        Ensure-Config
        & "$Lib\Sync-BuildsFolder.ps1"
    }
    "allocate-indexes" {
        Write-Host "Deprecated: catalogue indexes are assigned at build time by Generate-Catalogue012.ps1"
        Write-Host "from the actual AllPiecesInCatalogue append position (see piece.meta.json)."
        Write-Host "Keep 'catalogue_index = auto' in piece.ini; never hardcode a slot."
    }
    "cook" {
        Ensure-Config
        & "$Lib\Cook-Windows.ps1"
    }
    "manifest" {
        Ensure-Config
        & "$Lib\Write-Manifest.ps1"
    }
    "generate-da" {
        Ensure-Config
        $name = $Rest[0]
        if (-not $name) { throw 'Usage: generate-da [PieceId]' }
        Invoke-GenerateDA -PieceName $name
    }
    "generate-bp" {
        Ensure-Config
        $name = $Rest[0]
        if (-not $name) { throw 'Usage: generate-bp [PieceId]' }
        Invoke-GenerateBP -PieceName $name
    }
    "pack" {
        Ensure-Config
        $name = if ($Rest -and $Rest.Count -gt 0) { $Rest[0] } else { $null }
        & "$Lib\Pack-IoStore.ps1" -PieceName $name
        if ((Get-StonewallMaterialMode) -eq "Custom") {
            & "$Lib\Pack-ShaderChunk.ps1" -ChunkId 651
        }
        Deploy-Pak
    }
    "install-pack" {
        Ensure-Config
        $folder = $Rest[0]
        if (-not $folder) { throw 'Usage: install-pack [Folder]' }
        & "$Lib\Install-Pack.ps1" -PackFolder $folder
    }
    "rollback" {
        Ensure-Config
        $backup = $Rest[0]
        & "$Lib\Rollback-Install.ps1" -BackupDir $backup
    }
    "deploy" {
        Ensure-Config
        & "$Lib\Deploy-BlankMenu.ps1"
    }
    "deploy-pak" {
        Ensure-Config
        Deploy-Pak
    }
    "build-override" {
        Ensure-Config
        $name = $Rest[0]
        if (-not $name) { throw 'Usage: build-override [PieceId]' }
        Write-Host "=== Build-override piece: $name (repurpose registered vanilla slot) ==="
        & "$Lib\Scan-Pieces.ps1" -Strict | Out-Null
        $pieces = & "$Lib\Scan-Pieces.ps1"
        $piece = $pieces | Where-Object { $_.Id -eq $name } | Select-Object -First 1
        if (-not $piece) { throw "Piece not found: $name" }
        if (-not $piece.HasStaticMesh) { throw "$name missing SM_$name.uasset" }
        if (-not $piece.HasBlueprint) {
            Write-Host "${name} missing BP - generating..."
            Invoke-GenerateBP -PieceName $name
        }
        $donor = $piece.Donor
        if (-not $donor) { $donor = "wall_large" }
        & "$Lib\Generate-WallOverride.ps1" -PieceName $name -DonorKey $donor
        & "$Lib\Generate-CatalogueOverride.ps1" -PieceName $name -DonorKey $donor
        & "$Lib\Cook-Windows.ps1"
        & "$Lib\Patch-CookedStonewallMaterial.ps1" -PieceName $name -MaterialMode (Get-StonewallMaterialMode)
        & "$Lib\Write-Manifest.ps1"
        & "$Lib\Pack-IoStore.ps1" -PieceName $name
        if ((Get-StonewallMaterialMode) -eq "Custom") {
            & "$Lib\Pack-ShaderChunk.ps1" -ChunkId 651
        }
        Deploy-Pak
        & "$Lib\Deploy-BlankMenu.ps1"
        Write-Host 'Done. Full game restart - piece replaces donor slot in native build menu.'
    }
    "build" {
        Ensure-Config
        $name = $Rest[0]
        if (-not $name) { throw 'Usage: build [PieceId]' }
        Write-Host "=== Build piece: $name (native pak path) ==="
        Write-RsdwProgress 1 "Preparing build"
        & "$Lib\Ensure-PieceConfig.ps1" | Out-Null
        & "$Lib\Sync-BuildsFolder.ps1"
        & "$Lib\Scan-Pieces.ps1" -Strict | Out-Null
        Write-RsdwProgress 5 "Syncing and validating"
        $pieces = & "$Lib\Scan-Pieces.ps1"
        $piece = $pieces | Where-Object { $_.Id -eq $name } | Select-Object -First 1
        if (-not $piece) { throw "Piece not found: $name" }
        if (-not $piece.HasStaticMesh) { throw "$name missing SM_$name.uasset in UE project" }
        if (-not $piece.HasBlueprint) {
            Write-Host "${name} missing BP_${name}.uasset - generating..."
            Write-RsdwProgress 10 "Generating blueprint"
            Invoke-GenerateBP -PieceName $name
            $pieces = & "$Lib\Scan-Pieces.ps1"
            $piece = $pieces | Where-Object { $_.Id -eq $name } | Select-Object -First 1
            if (-not $piece.HasBlueprint) { throw "Failed to generate BP_${name}.uasset" }
        } else {
            Write-RsdwProgress 20 "Blueprint ready"
        }
        Write-RsdwProgress 25 "Generating piece data"
        Invoke-GenerateDA -PieceName $name
        Invoke-BuildPackDeploy -PieceName $name
        Write-Host 'Done. Full game restart, then open native build menu.'
    }
    "build-all" {
        Ensure-Config
        Write-RsdwProgress 1 "Preparing build"
        & "$Lib\Ensure-PieceConfig.ps1" | Out-Null
        & "$Lib\Sync-BuildsFolder.ps1"
        & "$Lib\Scan-Pieces.ps1" -Strict | Out-Null
        Write-RsdwProgress 3 "Scanning pieces"
        $pieces = & "$Lib\Scan-Pieces.ps1" | Where-Object { $_.HasStaticMesh }
        if ($pieces.Count -eq 0) { throw "No buildable pieces (need SM_* in each folder)." }
        $bpNeed = @($pieces | Where-Object { -not $_.HasBlueprint })
        $bpTotal = [Math]::Max(1, $bpNeed.Count)
        $bpIndex = 0
        foreach ($p in $bpNeed) {
            Write-Host "$($p.Id) missing BP_$($p.Id).uasset - generating..."
            Invoke-GenerateBP -PieceName $p.Id
            $bpIndex++
            if ($bpNeed.Count -gt 0) {
                $pct = 3 + [int](17 * $bpIndex / $bpTotal)
                Write-RsdwProgress $pct "Blueprint: $($p.Id)"
            }
        }
        if ($bpNeed.Count -eq 0) {
            Write-RsdwProgress 20 "Blueprints ready"
        }
        $pieces = @(& "$Lib\Scan-Pieces.ps1" | Where-Object { $_.HasStaticMesh -and $_.HasBlueprint } | Sort-Object Id)
        $daTotal = [Math]::Max(1, $pieces.Count)
        $daIndex = 0
        foreach ($p in $pieces) {
            Invoke-GenerateDA -PieceName $p.Id
            $daIndex++
            $pct = 20 + [int](25 * $daIndex / $daTotal)
            Write-RsdwProgress $pct "Piece data: $($p.Id)"
        }
        Invoke-BuildPackDeploy
        Write-Host "Built $($pieces.Count) piece(s)."
    }
    default { Show-Help }
}
