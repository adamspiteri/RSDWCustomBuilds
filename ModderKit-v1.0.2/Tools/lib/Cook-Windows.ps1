param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$runUat = Join-Path $cfg.UERoot "Engine\Build\BatchFiles\RunUAT.bat"
if (-not (Test-Path $runUat)) { throw "RunUAT not found: $runUat" }
if (-not (Test-Path $cfg.ProjectFile)) { throw "Project not found: $($cfg.ProjectFile)" }

$contentPieceRoot = Join-Path $cfg.ProjectRoot "Content\$($cfg.CookFolder)"
$cookPackages = @()
if (Test-Path -LiteralPath $contentPieceRoot) {
    Get-ChildItem -Path $contentPieceRoot -Recurse -Filter "*.uasset" -File | ForEach-Object {
        # Piece Blueprints (BP_*) are now cooked natively (UE editor-authored child of the
        # game's BP_T1_BasePiece). Their out-of-folder parent deps cook too but are not staged
        # into the pak, so the game's real base classes are used at runtime.
        $rel = $_.FullName.Substring((Resolve-Path $contentPieceRoot).Path.Length).TrimStart('\', '/')
        if ($rel -match '(?i)(^|[\\/])material[^\\/]*$') { return }
        $relGame = ($rel -replace '\\', '/') -replace '\.uasset$', ''
        $cookPackages += "/Game/$($cfg.CookFolder)/$relGame"
    }
}
if ($cookPackages.Count -eq 0) {
    throw "No cookable assets under Content\$($cfg.CookFolder) (need SM_*, materials, textures; BP_* is PakRaw-only)."
}

Write-Host "Cooking $($cfg.ProjectFile) ..."
Write-Host "Cook packages ($($cookPackages.Count)): BP_* excluded (PakRaw only)"
# -zenstore=false forces loose cooked .uasset/.uexp output (UE 5.6 defaults to the Zen
# package store, which Pack-IoStore can't stage). Piece assets are cooked via
# DirectoriesToAlwaysCook=(/Game/RSDWBuilds) in DefaultGame.ini, since -CookPackages is
# ignored by the cook-by-the-book commandlet (only default maps + AssetManager roots cook).
$cookOpt = "-AdditionalCookerOptions=" + (
    "-zenstore=false -cook.AllowCookedDataInEditorBuilds=true " +
    ($cookPackages | ForEach-Object { "-CookPackages=$_" }) -join ' '
)
Write-Host $cookOpt

$uatArgs = @(
    "BuildCookRun",
    "-nop4", "-utf8output", "-nocompileeditor", "-nocompile", "-installed",
    "-project=$($cfg.ProjectFile)",
    "-clientconfig=Development", "-serverconfig=Development",
    "-cook", "-skipstage", "-platform=Win64", "-unattended",
    # Without this, UAT passes -unversioned to the cooker and UE5.6 forces
    # SAVE_Unversioned_Properties (positional serialization) regardless of
    # bUseUnversionedProperties=False. Our /Script/Dominion stub classes are partial
    # mirrors of the game's classes, so assets MUST cook with tagged (name-based)
    # properties or the game reads garbage.
    "-VersionCookedContent",
    $cookOpt
)
& $runUat @uatArgs

if ($LASTEXITCODE -ne 0) { throw "Cook failed: exit $LASTEXITCODE" }

$cookedDir = Join-Path $cfg.CookedContent $cfg.CookFolder
if (-not (Test-Path -LiteralPath $cookedDir)) {
    throw @"
Cook finished but no cooked assets at:
  $cookedDir

Check that assets exist in Content\$($cfg.CookFolder) in the UE project and Save All, then rebuild.
"@
}
Write-Host "Cook finished. Found: $cookedDir"
