param(
    [string]$ConfigPath,
    [object[]]$Pieces
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

function Get-DonorIconPath {
    param([string]$DonorKey, $DonorMap, [string]$ArchiveRoot)
    if (-not $DonorKey -or -not $DonorMap -or -not $ArchiveRoot) { return $null }
    $rel = $null
    if ($DonorMap -is [hashtable] -and $DonorMap.ContainsKey($DonorKey)) {
        $rel = $DonorMap[$DonorKey]
    }
    if (-not $rel) { return $null }
    $jsonPath = Join-Path $ArchiveRoot $rel
    if (-not (Test-Path -LiteralPath $jsonPath)) { return $null }
    $arr = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    $entry = if ($arr -is [System.Array]) { $arr[0] } else { $arr }
    $path = [string]$entry.Properties.DisplayIcon.AssetPathName
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return $path
}

if (-not $Pieces -or $Pieces.Count -eq 0) {
    $Pieces = & "$PSScriptRoot\Scan-Pieces.ps1" -ConfigPath $cfg.ConfigPath
}

$manifestPieces = @()
foreach ($p in $Pieces) {
    if (-not $p.HasStaticMesh) { continue }
    $prefix = $p.GamePathPrefix
    $iconPath = "$prefix/T_Icon_$($p.Id).T_Icon_$($p.Id)"
    $iconUasset = Join-Path $cfg.ProjectRoot "Content\$($cfg.CookFolder)\$($p.Id)\T_Icon_$($p.Id).uasset"
    if (-not (Test-Path -LiteralPath $iconUasset)) {
        $donorIcon = Get-DonorIconPath $p.Donor $cfg.DonorMap $cfg.ArchiveJsonRoot
        if ($donorIcon) {
            $iconPath = $donorIcon
            Write-Host "  $($p.Id): menu icon -> donor ($donorIcon)"
        }
    }
    # DA must live under Gameplay/BaseBuilding_New/BuildingPieces so AssetManager registers it.
    $daScanRoot = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/$($cfg.CookFolder)/$($p.Id)"
    $manifestPieces += @{
        id              = $p.Id
        display_name    = $p.DisplayName
        donor           = $p.Donor
        persistence_id  = $p.PersistenceId
        cost_wood       = $p.CostWood
        menu_category   = $p.MenuCategory
        catalogue_index = $p.CatalogueIndex
        da_path         = "$daScanRoot/DA_$($p.Id).DA_$($p.Id)"
        bp_path         = "$prefix/BP_$($p.Id).BP_$($p.Id)_C"
        mesh_path       = "$prefix/SM_$($p.Id).SM_$($p.Id)"
        icon_path       = $iconPath
        pak_first       = $true
    }
}

$manifest = @{
    version     = 1
    pak         = $cfg.PakBasename
    generated   = (Get-Date).ToUniversalTime().ToString("o")
    pieces      = $manifestPieces
}

$outPath = Join-Path $cfg.ModSource "pieces.json"
$json = $manifest | ConvertTo-Json -Depth 6
Set-Content -Path $outPath -Value $json -Encoding UTF8
Write-Host "Wrote manifest: $outPath ($($manifestPieces.Count) piece(s))"

# UE4SS: Lua table avoids json.decode dependency at runtime
$luaLines = @("return {", "  version = 1,", "  pak = `"$($cfg.PakBasename)`",", "  pieces = {")
$i = 0
foreach ($entry in $manifestPieces) {
    $i++
    $comma = if ($i -lt $manifestPieces.Count) { "," } else { "" }
    $luaLines += @(
        "    {",
        "      id = `"$($entry.id)`",",
        "      display_name = `"$($entry.display_name -replace '"','\"')`",",
        "      persistence_id = `"$($entry.persistence_id)`",",
        "      donor = `"$($entry.donor)`",",
        "      catalogue_index = $($entry.catalogue_index),",
        "      da_path = `"$($entry.da_path)`",",
        "      bp_path = `"$($entry.bp_path)`",",
        "      mesh_path = `"$($entry.mesh_path)`",",
        "      icon_path = `"$($entry.icon_path)`",",
        "      pak_first = true",
        "    }$comma"
    )
}
$luaLines += "  }", "}"
$luaPath = Join-Path $cfg.ModSource "Scripts\pieces_data.lua"
Set-Content -Path $luaPath -Value ($luaLines -join "`n") -Encoding UTF8
Write-Host "Wrote Lua manifest: $luaPath"

& "$PSScriptRoot\Write-F7Manifest.ps1" -ConfigPath $cfg.ConfigPath -Pieces $Pieces

return $manifest
