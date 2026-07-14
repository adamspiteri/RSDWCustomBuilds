param(

    [string]$ConfigPath,

    [string]$PieceName

)



$ErrorActionPreference = "Stop"

if ($ConfigPath) {

    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath

} else {

    $cfg = & "$PSScriptRoot\Read-Config.ps1"

}



if (-not (Test-Path $cfg.Retoc)) { throw "retoc not found: $($cfg.Retoc)" }



$cookedDir = Join-Path $cfg.CookedContent $cfg.CookFolder

if (-not (Test-Path $cookedDir)) {

    throw "Cooked folder missing: $cookedDir`nRun cook first."

}



$shipBasename = $cfg.PakBasename

$utocOut = Join-Path $cfg.BuildDir "$shipBasename.utoc"

$stageRoot = Join-Path $cfg.BuildDir "_RetocStage"

$contentStage = Join-Path $stageRoot "$($cfg.ContentMount)\Content"



New-Item -ItemType Directory -Force -Path $cfg.BuildDir | Out-Null

if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }

New-Item -ItemType Directory -Force -Path $contentStage | Out-Null



$total = 0



function Stage-Tree {

    param([string]$SourceRoot, [string]$DestUnderContent)

    if (-not (Test-Path $SourceRoot)) { return 0 }

    $n = 0

    Get-ChildItem -Path $SourceRoot -Recurse -File | ForEach-Object {

        $rel = $_.FullName.Substring((Resolve-Path $SourceRoot).Path.Length).TrimStart('\', '/')

        $dest = Join-Path $contentStage (Join-Path $DestUnderContent $rel)

        $parent = Split-Path -Parent $dest

        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force

        $n++

    }

    return $n

}



# Cooked piece assets (SM, BP, materials, icons).
# ALWAYS stage the WHOLE cooked tree: the pak is shared by all pieces, so a single-piece
# build must never evict other pieces' cooked assets. (Staging only the target piece made
# previously built pieces INVISIBLE in-game while their PakRaw DA kept them in the menu.)

if ($PieceName) {

    $pieceCooked = Join-Path $cookedDir $PieceName

    if (-not (Test-Path $pieceCooked)) {

        throw "Cooked piece folder missing: $pieceCooked"

    }

}

$total += Stage-Tree -SourceRoot $cookedDir -DestUnderContent $cfg.CookFolder

# UE-backend DAs cook into the game's AssetManager scan tree. Stage ONLY the RSDWBuilds
# subtree - the editor-only stubs (BP_T1_BasePiece at Tier1_Brynmoor, DT placeholders at
# BaseBuilding_New/ and Progress/) also cook as dependencies but must NEVER ship, or they
# would override the game's real assets.
$daCookedRel = "Gameplay\BaseBuilding_New\BuildingPieces\$($cfg.CookFolder)"
$daCooked = Join-Path $cfg.CookedContent $daCookedRel
if (Test-Path -LiteralPath $daCooked) {
    $total += Stage-Tree -SourceRoot $daCooked -DestUnderContent ($daCookedRel -replace '\\', '/')
    Write-Host "Staged cooked UE-backend DAs: $daCookedRel"
}

# Small cooked BPs used to be dropped as "stubs" so PakRaw donor clones could stage instead.
# A UE-authored piece BP (one owned SCS mesh component) legitimately cooks to ~3-4 KB, so a
# size threshold alone is wrong: ONLY drop a cooked BP when a PakRaw replacement actually
# exists. With no replacement, dropping it ships a pak whose DA points at a missing class
# (the piece shows as pure vanilla / cannot spawn).
$minBpBytes = 8192
$stagedCookRoot = Join-Path $contentStage $cfg.CookFolder
if (Test-Path $stagedCookRoot) {
    Get-ChildItem -Path $stagedCookRoot -Recurse -Filter "BP_*.uasset" -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Length -ge $minBpBytes) { return }
        $rel = $_.FullName.Substring($stagedCookRoot.Length).TrimStart('\', '/')
        $pakRawBp = Join-Path (Join-Path $cfg.PakRawRoot $cfg.CookFolder) $rel
        if (-not (Test-Path -LiteralPath $pakRawBp)) {
            Write-Host "Keeping small cooked BP ($($_.Length) b, no PakRaw replacement): $($_.Name)"
            return
        }
        Write-Host "Removing stub cooked BP ($($_.Length) b) - PakRaw clone will stage: $($_.Name)"
        Remove-Item -LiteralPath $_.FullName -Force
        $stubUexp = $_.FullName -replace '\.uasset$', '.uexp'
        if (Test-Path -LiteralPath $stubUexp) { Remove-Item -LiteralPath $stubUexp -Force }
    }
}



# Cooked material shader library files live at Content/ root, not under the piece folder.
# Without these, custom cooked materials can load in-game but render as flat fallback shaders.
Get-ChildItem -Path $cfg.CookedContent -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like "ShaderArchive-$($cfg.ProjectLeaf)-*" -or
    $_.Name -like "ShaderAssetInfo-$($cfg.ProjectLeaf)-*" -or
    $_.Name -like "ShaderTypeInfo-$($cfg.ProjectLeaf)-*"
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $contentStage $_.Name) -Force
    $total++
    Write-Host "Staged shader library: $($_.Name)"

}



# PakRaw: DA + catalogue (UAssetGUI output, not UE-cooked)

$pakRawBase = $cfg.PakRawRoot

$rawRoots = @($cfg.CookFolder)

if ($cfg.PakRawRoots -and $cfg.PakRawRoots.Count -gt 0) {

    $rawRoots = @($cfg.PakRawRoots)

}

foreach ($root in $rawRoots) {

    $rawDir = Join-Path $pakRawBase $root

    if (-not (Test-Path $rawDir)) {

        Write-Warning "PakRaw missing (skipped): $rawDir"

        continue

    }

    Get-ChildItem -Path $rawDir -Recurse -File | Where-Object {

        $_.Extension -in '.uasset', '.uexp', '.ubulk'

    } | ForEach-Object {

        $rel = $_.FullName.Substring((Resolve-Path $rawDir).Path.Length).TrimStart('\', '/')

        if ($PieceName -and $root -eq $cfg.CookFolder) {

            if ($rel -notmatch "^$PieceName[\\/]" -and $rel -notmatch "^DA_" -and $rel -notmatch "^$PieceName\.") {

                # root-level catalogue still staged below

            }

        }

        $dest = Join-Path $contentStage (Join-Path $root $rel)

        # Cooked/editor BP beats PakRaw UAssetGUI clone when dest already has a real BP.
        if ($root -eq $cfg.CookFolder -and $rel -match '(?i)[\\/]BP_[^\\/]+\.uasset$' -and (Test-Path -LiteralPath $dest)) {
            $destSize = (Get-Item -LiteralPath $dest).Length
            if ($destSize -ge 8192) {
                Write-Host "Skip PakRaw (staged BP already $destSize b): $root/$rel"
                return
            }
        }

        $parent = Split-Path -Parent $dest

        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force

        $total++

    }

    Write-Host "Staged PakRaw: $root"

}



Write-Host "Staged $total file(s) under Content/"



foreach ($g in @("global.utoc", "global.ucas")) {

    $gp = Join-Path $cfg.GamePaksDir $g

    if (Test-Path -LiteralPath $gp) {

        Copy-Item -LiteralPath $gp -Destination (Join-Path $stageRoot $g) -Force

        Write-Host "Staged $g"

    }

}



Get-ChildItem $cfg.BuildDir -File -ErrorAction SilentlyContinue |

    Where-Object { $_.Extension -in '.pak', '.utoc', '.ucas' } |

    Remove-Item -Force



Write-Host "retoc to-zen -> $utocOut"
& $cfg.Retoc `
    '--override-toc-version' 'ReplaceIoChunkHashWithIoHash' `
    '--override-container-header-version' 'SoftPackageReferencesOffset' `
    'to-zen' '--version' $cfg.UERetocVersion $stageRoot $utocOut

if ($LASTEXITCODE -ne 0) { throw "retoc to-zen failed: $LASTEXITCODE" }



$ucasOut = Join-Path $cfg.BuildDir "$shipBasename.ucas"

if (-not (Test-Path -LiteralPath $ucasOut)) { throw "Missing $ucasOut after retoc" }

$ucasSize = (Get-Item -LiteralPath $ucasOut).Length

if ($ucasSize -lt 8000) { throw "Packed ucas only $ucasSize bytes (staging or retoc failed)" }

Write-Host "Packed ucas: $ucasSize bytes"



Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Pak trio written to $($cfg.BuildDir)"

