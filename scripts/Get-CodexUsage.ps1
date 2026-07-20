[CmdletBinding()]
param([switch]$AsJson)

$ErrorActionPreference = 'Stop'
$cacheDir = Join-Path $env:LOCALAPPDATA 'CodexResetWatcher'
$cachePath = Join-Path $cacheDir 'usage.json'
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

function Find-CodexCli {
    $bin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $candidate = Get-ChildItem $bin -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -ne $bin } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if ($candidate) { return $candidate }
    $fallback = Join-Path $bin 'codex.exe'
    if (Test-Path $fallback) { return $fallback }
    throw 'Codex CLI not found.'
}

function Read-Response {
    param($Process, [int]$ExpectedId, [int]$TimeoutMs = 15000)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $TimeoutMs) {
        $task = $Process.StandardOutput.ReadLineAsync()
        $remaining = [math]::Max(1, $TimeoutMs - [int]$watch.ElapsedMilliseconds)
        if (-not $task.Wait($remaining)) { break }
        $line = $task.Result
        if ($null -eq $line) { break }
        try {
            $message = $line | ConvertFrom-Json
            if ($message.id -eq $ExpectedId) { return $message }
        } catch {}
    }
    throw "Timed out waiting for app-server response $ExpectedId."
}

function Normalize-Window {
    param($Window, [string]$FallbackLabel)
    if (-not $Window) { return $null }
    $duration = [int]$Window.windowDurationMins
    $label = if ($duration -ge 1000) { '周额度' } else { $FallbackLabel }
    $used = [double]$Window.usedPercent
    $remaining = [math]::Max(0, [math]::Min(100, (100 - $used)))
    $resetUtc = if ($Window.resetsAt) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$Window.resetsAt) } else { $null }
    $resetLocal = if ($resetUtc) { $resetUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
    $secondsLeft = if ($resetUtc) { [math]::Max(0, [math]::Round(($resetUtc - [DateTimeOffset]::UtcNow).TotalSeconds)) } else { $null }
    [ordered]@{
        label = $label
        used_percent = [math]::Round($used, 1)
        remaining_percent = [math]::Round($remaining, 1)
        window_duration_mins = $duration
        resets_at = if ($resetUtc) { $resetUtc.ToString('o') } else { $null }
        resets_at_local = $resetLocal
        seconds_until_reset = $secondsLeft
    }
}

try {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = Find-CodexCli
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.ArgumentList.Add('app-server')
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw 'Could not start Codex app-server.' }
    try {
        $initialize = [ordered]@{ method='initialize'; id=1; params=[ordered]@{ clientInfo=[ordered]@{ name='codex_reset_watcher'; title='Codex Reset Watcher'; version='0.3.0' } } } | ConvertTo-Json -Compress -Depth 6
        $process.StandardInput.WriteLine($initialize)
        $process.StandardInput.Flush()
        $initResponse = Read-Response -Process $process -ExpectedId 1
        if ($initResponse.error) { throw $initResponse.error.message }
        $process.StandardInput.WriteLine((@{ method='initialized'; params=@{} } | ConvertTo-Json -Compress))
        $process.StandardInput.WriteLine((@{ method='account/read'; id=2; params=@{ refreshToken=$false } } | ConvertTo-Json -Compress))
        $process.StandardInput.Flush()
        $accountResponse = Read-Response -Process $process -ExpectedId 2
        $process.StandardInput.WriteLine((@{ method='account/rateLimits/read'; id=3 } | ConvertTo-Json -Compress))
        $process.StandardInput.Flush()
        $limitsResponse = Read-Response -Process $process -ExpectedId 3
        if ($limitsResponse.error) { throw $limitsResponse.error.message }
        $limits = $limitsResponse.result.rateLimits
        $credits = $limitsResponse.result.rateLimitResetCredits
        $result = [ordered]@{
            plan_type = $accountResponse.result.account.planType
            auth_type = $accountResponse.result.account.type
            primary = Normalize-Window $limits.primary '主要额度'
            secondary = Normalize-Window $limits.secondary '次要额度'
            rate_limit_reached_type = $limits.rateLimitReachedType
            reset_credits = if ($credits) { [int]$credits.availableCount } else { $null }
            fetched_at = [DateTimeOffset]::UtcNow.ToString('o')
            source = 'codex-app-server'
        }
        $result | ConvertTo-Json -Depth 6 | Set-Content $cachePath -Encoding utf8
    } finally {
        if (-not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
} catch {
    if (Test-Path $cachePath) {
        $result = Get-Content $cachePath -Raw | ConvertFrom-Json
        $result.source = 'cache'
        $result | Add-Member -NotePropertyName warning -NotePropertyValue $_.Exception.Message -Force
    } else { throw }
}

if ($AsJson) { $result | ConvertTo-Json -Depth 6 } else { $result }
