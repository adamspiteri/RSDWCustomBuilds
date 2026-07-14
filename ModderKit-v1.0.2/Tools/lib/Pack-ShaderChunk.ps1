param(
    [string]$ConfigPath,
    [int]$ChunkId = 651
)

$ErrorActionPreference = "Stop"

if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

if (-not (Test-Path -LiteralPath $cfg.Retoc)) { throw "retoc not found: $($cfg.Retoc)" }

$chunkLibrary = "RSDragonwilds_Chunk$ChunkId"
$chunkBasename = "pakchunk$($ChunkId)-Windows_P"
$utocOut = Join-Path $cfg.BuildDir "$chunkBasename.utoc"
$stageRoot = Join-Path $cfg.BuildDir "_ShaderChunkStage_$ChunkId"
$contentStage = Join-Path $stageRoot "$($cfg.ContentMount)\Content"

if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $contentStage | Out-Null

$patterns = @(
    "ShaderArchive-$($cfg.ProjectLeaf)-*",
    "ShaderAssetInfo-$($cfg.ProjectLeaf)-*",
    "ShaderTypeInfo-$($cfg.ProjectLeaf)-*"
)

$staged = 0
foreach ($pattern in $patterns) {
    Get-ChildItem -Path $cfg.CookedContent -File -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        $destName = $_.Name.Replace($cfg.ProjectLeaf, $chunkLibrary)
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $contentStage $destName) -Force
        $staged++
        Write-Host "Staged shader chunk: $destName"
    }
}

if ($staged -eq 0) {
    throw "No cooked shader library files found for $($cfg.ProjectLeaf) under $($cfg.CookedContent)"
}

foreach ($g in @("global.utoc", "global.ucas")) {
    $gp = Join-Path $cfg.GamePaksDir $g
    if (Test-Path -LiteralPath $gp) {
        Copy-Item -LiteralPath $gp -Destination (Join-Path $stageRoot $g) -Force
    }
}

foreach ($ext in @(".pak", ".utoc", ".ucas")) {
    Remove-Item -LiteralPath (Join-Path $cfg.BuildDir "$chunkBasename$ext") -Force -ErrorAction SilentlyContinue
}

Write-Host "retoc shader chunk -> $utocOut"
& $cfg.Retoc `
    '--override-toc-version' 'ReplaceIoChunkHashWithIoHash' `
    '--override-container-header-version' 'SoftPackageReferencesOffset' `
    'to-zen' '--version' $cfg.UERetocVersion $stageRoot $utocOut

if ($LASTEXITCODE -ne 0) { throw "retoc shader chunk failed: $LASTEXITCODE" }

$ucasOut = Join-Path $cfg.BuildDir "$chunkBasename.ucas"
if (-not (Test-Path -LiteralPath $ucasOut)) { throw "Missing $ucasOut after retoc" }

Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Shader chunk pak trio written: $chunkBasename"
