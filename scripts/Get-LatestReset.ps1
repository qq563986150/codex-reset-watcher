[CmdletBinding()]
param(
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$trackerUrl = 'https://codex-resets.com/'
$cacheDir = Join-Path $env:LOCALAPPDATA 'CodexResetWatcher'
$cachePath = Join-Path $cacheDir 'latest.json'

function Read-LatestResetFromHtml {
    param([string]$Html)

    $pattern = '(?s)<li class="log-item">.*?data-datetime="(?<time>[^"]+)".*?<p class="log-item-text">(?<text>.*?)</p>.*?<a class="log-item-link" href="(?<url>https://x\.com/thsottiaux/status/\d+)"'
    $matches = [regex]::Matches($Html, $pattern)
    if ($matches.Count -eq 0) {
        throw 'Could not find the latest reset announcement in the tracker page.'
    }

    Add-Type -AssemblyName System.Web
    try {
        $beijingZone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
    } catch {
        $beijingZone = [TimeZoneInfo]::FindSystemTimeZoneById('Asia/Shanghai')
    }

    $history = @()
    foreach ($item in $matches) {
        $itemText = [System.Web.HttpUtility]::HtmlDecode($item.Groups['text'].Value)
        $itemText = ($itemText -replace '<[^>]+>', '' -replace "`r?`n\s*`r?`n", "`n`n").Trim()
        $itemUtc = [DateTimeOffset]::Parse($item.Groups['time'].Value).ToUniversalTime()
        $itemBeijing = [TimeZoneInfo]::ConvertTime($itemUtc, $beijingZone)
        $history += [ordered]@{
            time_utc = $itemUtc.ToString('o')
            time_beijing = $itemBeijing.ToString('yyyy-MM-dd HH:mm:ss') + ' 北京时间'
            text = $itemText
            url = $item.Groups['url'].Value
        }
    }

    $latest = $history[0]
    $intervalHours = @()
    for ($i = 0; $i -lt ($history.Count - 1); $i++) {
        $newer = [DateTimeOffset]::Parse($history[$i].time_utc)
        $older = [DateTimeOffset]::Parse($history[$i + 1].time_utc)
        $intervalHours += ($newer - $older).TotalHours
    }
    $sorted = @($intervalHours | Sort-Object)
    $medianHours = if ($sorted.Count) { [math]::Round($sorted[[math]::Floor($sorted.Count / 2)], 1) } else { 0 }
    $averageHours = if ($intervalHours.Count) { [math]::Round(($intervalHours | Measure-Object -Average).Average, 1) } else { 0 }
    $nextEstimate = [DateTimeOffset]::Parse($latest.time_utc).AddHours($medianHours)
    $remainingHours = [math]::Round(($nextEstimate - [DateTimeOffset]::UtcNow).TotalHours, 1)

    [ordered]@{
        author = 'Tibo Sottiaux (@thsottiaux)'
        time_utc = $latest.time_utc
        time_beijing = $latest.time_beijing
        text = $latest.text
        url = $latest.url
        history = $history
        stats = [ordered]@{
            count = $history.Count
            median_interval_hours = $medianHours
            average_interval_hours = $averageHours
            estimated_next_utc = $nextEstimate.ToString('o')
            remaining_hours = $remainingHours
        }
        tracker = $trackerUrl
        fetched_at = [DateTimeOffset]::UtcNow.ToString('o')
        source = 'live'
    }
}

try {
    $headers = @{ 'User-Agent' = 'CodexResetWatcher/0.1 (+https://github.com/qq563986150/codex-reset-watcher)' }
    try {
        $html = (Invoke-WebRequest -Uri $trackerUrl -Headers $headers -UseBasicParsing -TimeoutSec 15).Content
    } catch {
        $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
        if (-not $curl) { throw }
        $html = & $curl -L --silent --show-error --max-time 15 --user-agent 'CodexResetWatcher/0.1' $trackerUrl
        if (-not $html) { throw }
        $html = $html -join "`n"
    }
    $result = Read-LatestResetFromHtml -Html $html
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cachePath -Encoding utf8
} catch {
    if (Test-Path -LiteralPath $cachePath) {
        $result = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        $result.source = 'cache'
        $result | Add-Member -NotePropertyName warning -NotePropertyValue $_.Exception.Message -Force
        if (-not $result.history) {
            $result | Add-Member -NotePropertyName history -NotePropertyValue @([ordered]@{
                time_utc = $result.time_utc
                time_beijing = $result.time_beijing
                text = $result.text
                url = $result.url
            }) -Force
        }
        if (-not $result.stats) {
            $result | Add-Member -NotePropertyName stats -NotePropertyValue ([ordered]@{
                count = $result.history.Count
                median_interval_hours = 0
                average_interval_hours = 0
                estimated_next_utc = $result.time_utc
                remaining_hours = 0
            }) -Force
        }
    } else {
        throw
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 4
} else {
    $result
}
