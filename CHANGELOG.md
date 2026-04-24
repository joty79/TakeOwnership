# CHANGELOG - TakeOwnership

## 2026-04-24

- Added `app-metadata.json` so `TakeOwnership` has a canonical app version/repo contract.
- Added plain-`pwsh` in-app update status to the ownership manager header.
- Added an `Update app` menu item that uses the generated `Install.ps1` flow without a Windows Terminal bootstrap.
- Regenerated `Install.ps1` from the current `InstallerCore` template/profile so it includes null-safe prompts, info-only `-NoExplorerRestart`, and commit-aware install metadata.
- Replaced the legacy `Get-WmiObject` safe-mode check with a PowerShell 7 compatible `Get-CimInstance` check.
- Aligned the in-app updater behavior with the `WinAppManager` pattern: visible update progress, recent installer output, automatic relaunch, and old-session exit.
