[CmdletBinding()]
param()

$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Reset Watcher.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-Output "Removed: $shortcutPath"
} else {
    Write-Output 'Codex Reset Watcher startup entry is not installed.'
}
