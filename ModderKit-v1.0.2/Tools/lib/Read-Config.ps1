param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

function Get-IniValues {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config not found: $Path`nRun Setup.bat first."
    }
    $section = ""
    $data = @{}
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith(";")) { return }
        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1].ToLower()
            if (-not $data.ContainsKey($section)) { $data[$section] = @{} }
            return
        }
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim().ToLower()
            $value = $Matches[2].Trim()
            if ($section -eq "") { return }
            $data[$section][$key] = $value
        }
    }
    return $data
}

function Get-ConfigValue {
    param($Ini, [string]$Section, [string]$Key, [string]$Default = "")
    if ($Ini.ContainsKey($Section) -and $Ini[$Section].ContainsKey($Key)) {
        return $Ini[$Section][$Key]
    }
    return $Default
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    if ($env:RSDW_CONFIG_PATH -and (Test-Path -LiteralPath $env:RSDW_CONFIG_PATH)) {
        $ConfigPath = $env:RSDW_CONFIG_PATH
    } else {
        $toolsDir = Split-Path -Parent $PSScriptRoot
        $ConfigPath = Join-Path $toolsDir "mod.config.ini"
    }
}

$configToolsDir = Split-Path -Parent $PSScriptRoot
$scriptRepoRoot = Split-Path -Parent $configToolsDir
$ini = Get-IniValues -Path $ConfigPath

$modderKit = Get-ConfigValue $ini "paths" "modder_kit"
if ([string]::IsNullOrWhiteSpace($modderKit) -and $env:RSDW_MODDER_KIT) {
    $modderKit = $env:RSDW_MODDER_KIT.Trim()
}

$projectFile = Get-ConfigValue $ini "paths" "project"
if (-not [string]::IsNullOrWhiteSpace($modderKit)) {
    $repoRoot = [IO.Path]::GetFullPath($modderKit)
    if ([string]::IsNullOrWhiteSpace($projectFile)) {
        $projectFile = Join-Path $repoRoot "RSDWCustomBuilds.uproject"
    }
} elseif (-not [string]::IsNullOrWhiteSpace($projectFile)) {
    $repoRoot = Split-Path -Parent ([IO.Path]::GetFullPath($projectFile))
} else {
    $repoRoot = $scriptRepoRoot
    if ([string]::IsNullOrWhiteSpace($projectFile)) {
        $projectFile = Join-Path $repoRoot "RSDWCustomBuilds.uproject"
    }
}
$projectRoot = Split-Path -Parent $projectFile
$projectLeaf = [System.IO.Path]::GetFileNameWithoutExtension($projectFile)

$gameRoot = Get-ConfigValue $ini "paths" "game_root"
$buildsFolder = Get-ConfigValue $ini "paths" "builds_folder"
$gamePaksDir = Get-ConfigValue $ini "deploy" "game_paks_dir"
if ([string]::IsNullOrWhiteSpace($gamePaksDir)) {
    $gamePaksDir = Join-Path $gameRoot "Content\Paks"
}

$modSource = Get-ConfigValue $ini "mod" "mod_source" "Mod"
if (-not [System.IO.Path]::IsPathRooted($modSource)) {
    $modSource = Join-Path $repoRoot $modSource
}

function Split-ConfigList {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }
    return @($Raw -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

$packRoots = Split-ConfigList (Get-ConfigValue $ini "pack" "pack_roots" "")
$pakRawRoots = Split-ConfigList (Get-ConfigValue $ini "pack" "pak_raw_roots" "")
if ($pakRawRoots.Count -eq 0) {
    $cookFolder = Get-ConfigValue $ini "pack" "cook_folder" "RSDWBuilds"
    $pakRawRoots = @($cookFolder, "Gameplay/BaseBuilding_New/BuildingPieces")
}

[PSCustomObject]@{
    ConfigPath      = (Resolve-Path -LiteralPath $ConfigPath).Path
    ToolsDir        = $configToolsDir
    ModderKitRoot   = $repoRoot
    RepoRoot        = $repoRoot
    ProjectRoot     = $projectRoot
    ProjectFile     = $projectFile
    ProjectLeaf     = $projectLeaf
    GameRoot        = $gameRoot
    BuildsFolder    = $buildsFolder
    UERoot          = Get-ConfigValue $ini "paths" "ue_root"
    Retoc           = Get-ConfigValue $ini "paths" "retoc"
    PakBasename     = Get-ConfigValue $ini "deploy" "pak_basename" "RSDragonwilds-Z_RSDWCustomBuilds_P"
    GamePaksDir     = $gamePaksDir
    ModFolder       = Get-ConfigValue $ini "mod" "mod_folder" "RSDWCustomBuilds"
    ModSource       = $modSource
    UERetocVersion  = Get-ConfigValue $ini "pack" "ue_retoc_version" "UE5_6"
    ContentMount    = Get-ConfigValue $ini "pack" "content_mount" "RSDragonwilds"
    CookFolder      = Get-ConfigValue $ini "pack" "cook_folder" "RSDWBuilds"
    BuildDir        = Join-Path $repoRoot "Build"
    CookedContent   = Join-Path $projectRoot "Saved\Cooked\Windows\$projectLeaf\Content"
    ContentRoot     = Join-Path $projectRoot "Content\$((Get-ConfigValue $ini 'pack' 'cook_folder' 'RSDWBuilds'))"
    PakRawRoot      = Join-Path $repoRoot "PakRaw"
    LoaderRoot      = Join-Path $gameRoot "Binaries\Win64\ue4ss\Mods\$((Get-ConfigValue $ini 'mod' 'mod_folder' 'RSDWCustomBuilds'))"
    UAssetGuiExe    = Get-ConfigValue $ini "uassetgui" "exe"
    ArchiveJsonRoot = Get-ConfigValue $ini "uassetgui" "archive_json"
    MappingsPath    = Get-ConfigValue $ini "uassetgui" "mappings"
    EngineVer       = Get-ConfigValue $ini "uassetgui" "engine_ver" "VER_UE5_6"
    # [build] backend = cli (UAssetGUI/RSDWAssetCli, default) | ue (in-editor Python generation)
    BuildBackend    = (Get-ConfigValue $ini "build" "backend" "cli").ToLower()
    DonorMap        = $ini["donors"]
    PackRoots       = $packRoots
    PakRawRoots     = $pakRawRoots
}
