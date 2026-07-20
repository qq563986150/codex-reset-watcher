[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$showScript = Join-Path $scriptDir 'Show-LatestReset.ps1'
$shell = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $shell) { $shell = (Get-Command powershell.exe).Source }
$mutex = New-Object Threading.Mutex($false, 'Local\CodexResetWatcher')
if (-not $mutex.WaitOne(0, $false)) { exit 0 }

function Test-CodexRunning {
    $processes = Get-Process -Name ChatGPT -ErrorAction SilentlyContinue
    foreach ($process in $processes) {
        if ($process.Path -like '*OpenAI.Codex*') { return $true }
    }
    return $false
}

$wasRunning = $false
$windowProcess = $null
try {
    while ($true) {
        $isRunning = Test-CodexRunning
        if ($isRunning -and -not $wasRunning) {
            $windowProcess = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $showScript, '-StartCollapsed') -WindowStyle Hidden -PassThru
        }
        if (-not $isRunning -and $wasRunning -and $windowProcess -and -not $windowProcess.HasExited) {
            Stop-Process -Id $windowProcess.Id -Force -ErrorAction SilentlyContinue
            $windowProcess = $null
        }
        $wasRunning = $isRunning
        Start-Sleep -Seconds 3
    }
} finally {
    if ($windowProcess -and -not $windowProcess.HasExited) {
        Stop-Process -Id $windowProcess.Id -Force -ErrorAction SilentlyContinue
    }
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
