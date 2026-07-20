---
name: codex-reset-watcher
description: Check and display the latest public Codex usage-limit reset announcement by Tibo Sottiaux (@thsottiaux), including exact Beijing time and the original X link. Use when the user asks whether Codex limits were reset, asks for Tibo's latest reset post, or invokes Codex Reset Watcher.
---

# Codex Reset Watcher

Run the bundled PowerShell reader and report its result directly:

```powershell
& "$PSScriptRoot\..\..\scripts\Get-LatestReset.ps1" -AsJson
```

If `$PSScriptRoot` is unavailable in the current shell, resolve the plugin root from this `SKILL.md` path and run `scripts/Get-LatestReset.ps1 -AsJson`.

Present:

- whether the result was refreshed live or loaded from cache;
- the exact `time_beijing` value;
- the announcement text;
- the clickable `url`.

For current local Codex quota, run `scripts/Get-CodexUsage.ps1 -AsJson`. Report remaining percentage and reset time from the app-server response, and explicitly say when a primary or secondary window is absent instead of estimating it.

Treat this as an unofficial public tracker, not an OpenAI guarantee that every account or every quota bucket was reset.

For companion controls, run one of:

```powershell
& "<plugin-root>\scripts\Show-LatestReset.ps1" -StartCollapsed
& "<plugin-root>\scripts\Install-Autostart.ps1"
& "<plugin-root>\scripts\Uninstall-Autostart.ps1"
```
