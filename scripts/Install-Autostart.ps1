[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$showScript = Join-Path $scriptDir 'Show-LatestReset.ps1'
$hostSource = Join-Path $scriptDir 'CodexResetWatcherHost.cs'
$hostDir = Join-Path $env:LOCALAPPDATA 'CodexResetWatcher\host'
$hostExe = Join-Path $hostDir 'CodexResetWatcherHost.exe'

Get-Process -Name 'CodexResetWatcherHost' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 250
New-Item -ItemType Directory -Path $hostDir -Force | Out-Null
$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) { throw '未找到 Windows .NET Framework C# 编译器。' }

& $compiler /nologo /target:winexe /optimize+ /platform:x86 /out:$hostExe $hostSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $hostExe)) { throw '轻量启动宿主编译失败。' }

$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'Codex Reset Watcher.lnk'
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $hostExe
$shortcut.Arguments = '"' + $showScript + '"'
$shortcut.WorkingDirectory = $scriptDir
$shortcut.Description = 'Codex 启动时显示额度雷达（低内存）'
$shortcut.Save()

# 迁移旧版常驻 PowerShell 监听器和旧窗口，随后立即启用轻量宿主。
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('powershell.exe','pwsh.exe') -and $_.CommandLine -match 'codex-reset-watcher' -and $_.CommandLine -match '(Watch-Codex|Show-LatestReset)\.ps1' } |
    ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null }

Start-Sleep -Milliseconds 350
if (-not (Get-Process -Name 'CodexResetWatcherHost' -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $hostExe -ArgumentList ('"' + $showScript + '"') -WorkingDirectory $scriptDir -WindowStyle Hidden
}

Write-Output "已安装低内存自动启动：$shortcutPath"
