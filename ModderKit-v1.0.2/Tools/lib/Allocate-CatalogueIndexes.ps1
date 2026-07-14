param(
    [string]$ConfigPath,
    [int]$StartIndex = 651
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$pieces = & "$PSScriptRoot\Scan-Pieces.ps1" -ConfigPath $cfg.ConfigPath
if (-not $pieces -or $pieces.Count -eq 0) {
    Write-Host "No pieces found for catalogue index allocation."
    return @()
}

$used = @{}
foreach ($p in $pieces | Where-Object { $null -ne $_.CatalogueIndex }) {
    $idx = [int]$p.CatalogueIndex
    if ($used.ContainsKey($idx)) {
        throw "Catalogue index collision: $idx used by $($used[$idx]) and $($p.Id)"
    }
    $used[$idx] = $p.Id
}

function Set-PieceIniIndex {
    param([string]$Path, [int]$Index)
    $lines = @()
    if (Test-Path -LiteralPath $Path) {
        $lines = @(Get-Content -LiteralPath $Path)
    } else {
        $lines = @("[ piece ]")
    }
    $found = $false
    $out = foreach ($line in $lines) {
        if ($line -match '^\s*catalogue_index\s*=') {
            $found = $true
            "catalogue_index = $Index"
        } else {
            $line
        }
    }
    if (-not $found) { $out += "catalogue_index = $Index" }
    Set-Content -LiteralPath $Path -Value ($out -join "`n") -Encoding UTF8
}

function Set-PieceJsonIndex {
    param([string]$Path, [int]$Index)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $obj | Add-Member -NotePropertyName catalogueIndex -NotePropertyValue $Index -Force
    $obj | Add-Member -NotePropertyName autoCatalogueIndex -NotePropertyValue $false -Force
    $obj | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $true
}

$allocated = @()
$next = $StartIndex
foreach ($p in ($pieces | Sort-Object Id)) {
    if ($null -ne $p.CatalogueIndex) { continue }
    while ($used.ContainsKey($next)) { $next++ }
    $idx = $next
    $used[$idx] = $p.Id
    $next++

    $pieceDir = Join-Path $cfg.ContentRoot $p.Id
    $jsonPath = Join-Path $pieceDir "piece.json"
    $iniPath = Join-Path $pieceDir "piece.ini"
    if (-not (Set-PieceJsonIndex -Path $jsonPath -Index $idx)) {
        Set-PieceIniIndex -Path $iniPath -Index $idx
    }
    Write-Host "Allocated catalogue index $idx -> $($p.Id)"
    $allocated += [PSCustomObject]@{ Id = $p.Id; CatalogueIndex = $idx }
}

if ($allocated.Count -eq 0) {
    Write-Host "Catalogue indexes already assigned."
}

return $allocated
