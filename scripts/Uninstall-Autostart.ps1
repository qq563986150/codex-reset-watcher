[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Reset Watcher.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-Output "Removed: $shortcutPath"
} else {
    Write-Output 'Codex Reset Watcher startup entry is not installed.'
}

Get-Process -Name 'CodexResetWatcherHost' -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('powershell.exe','pwsh.exe') -and $_.CommandLine -match 'codex-reset-watcher' -and $_.CommandLine -match '(Watch-Codex|Show-LatestReset)\.ps1' } |
    ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null }

Start-Sleep -Milliseconds 250
$hostDir = Join-Path $env:LOCALAPPDATA 'CodexResetWatcher\host'
if (Test-Path -LiteralPath $hostDir) { Remove-Item -LiteralPath $hostDir -Recurse -Force }
