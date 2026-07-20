[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcher = Join-Path $scriptDir 'Watch-Codex.ps1'
$shellPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $shellPath) { $shellPath = (Get-Command powershell.exe).Source }
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'Codex Reset Watcher.lnk'
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $shellPath
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $watcher + '"'
$shortcut.WorkingDirectory = $scriptDir
$shortcut.Description = 'Show Tibo Codex reset announcements when Codex starts'
$shortcut.Save()

Write-Output "Installed: $shortcutPath"
