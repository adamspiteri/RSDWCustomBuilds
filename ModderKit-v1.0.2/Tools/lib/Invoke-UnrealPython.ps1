# Run a headless UE editor Python task (UnrealEditor-Cmd -run=pythonscript).
# Task parameters are passed as a JSON file whose path is exposed via RSDW_UE_TASK_CONFIG
# (same pattern as unreal_import_raw_piece.py / RSDW_RAW_IMPORT_CONFIG).
# The python script MUST print "RSDW_TASK_OK" on success; anything else fails the build.
param(
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskConfig,
    [int]$TimeoutSec = 900,
    [switch]$MountGamePaks
)

$ErrorActionPreference = "Stop"
if ($ConfigPath) {
    $cfg = & "$PSScriptRoot\Read-Config.ps1" -ConfigPath $ConfigPath
} else {
    $cfg = & "$PSScriptRoot\Read-Config.ps1"
}

$ueCmd = Join-Path $cfg.UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
if (-not (Test-Path -LiteralPath $ueCmd)) { throw "UnrealEditor-Cmd not found: $ueCmd" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Python script not found: $ScriptPath" }
if (-not (Test-Path -LiteralPath $cfg.ProjectFile)) { throw "Project not found: $($cfg.ProjectFile)" }

$taskJson = Join-Path $env:TEMP ("rsdw-ue-task-" + [guid]::NewGuid().ToString("N") + ".json")
$TaskConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskJson -Encoding UTF8

$logFile = Join-Path $env:TEMP ("rsdw-ue-task-" + [guid]::NewGuid().ToString("N") + ".log")

$prevTask = $env:RSDW_UE_TASK_CONFIG
$env:RSDW_UE_TASK_CONFIG = $taskJson
try {
    Write-Host "[ue-python] $([IO.Path]::GetFileName($ScriptPath)) (task: $([IO.Path]::GetFileName($taskJson)))"
    $args = @(
        "`"$($cfg.ProjectFile)`"",
        "-run=pythonscript",
        "-script=`"$ScriptPath`"",
        "-unattended", "-nop4", "-nosplash", "-stdout", "-FullStdOutLogOutput",
        "-abslog=`"$logFile`""
    )
    if ($MountGamePaks) { $args += "-pak" }
    $proc = Start-Process -FilePath $ueCmd -ArgumentList $args -PassThru -NoNewWindow
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch {}
        throw "[ue-python] timed out after $TimeoutSec s: $ScriptPath"
    }
    $exit = $proc.ExitCode

    $out = @()
    if (Test-Path -LiteralPath $logFile) { $out = @(Get-Content -LiteralPath $logFile) }
    # Surface the task's own log lines + any python errors for the build log.
    $out | Where-Object { $_ -match '\[RSDW\]|LogPython: Error|ScriptError|Traceback' } | ForEach-Object { Write-Host "  $_" }

    $ok = ($out | Where-Object { $_ -match 'RSDW_TASK_OK' }).Count -gt 0
    if (-not $ok) {
        $tail = ($out | Select-Object -Last 25) -join "`n"
        throw "[ue-python] task did not report RSDW_TASK_OK (exit=$exit). Log tail:`n$tail`nFull log: $logFile"
    }
    if ($null -ne $exit -and $exit -ne 0) {
        Write-Warning "[ue-python] editor exit code $exit but task reported OK - continuing."
    }
    Write-Host "[ue-python] OK"
} finally {
    $env:RSDW_UE_TASK_CONFIG = $prevTask
    Remove-Item -LiteralPath $taskJson -Force -ErrorAction SilentlyContinue
}
