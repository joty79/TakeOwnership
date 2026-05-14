# CHANGELOG - TakeOwnership

## 2026-05-14

- Bumped `app-metadata.json` to `1.0.4` and removed the desktop-background `System Tools > Windows > Take Ownership` entry so `InstallAll` no longer pushes the shared desktop menu over the Windows 10 static-menu item limit; file/folder targets remain registered.
- Bumped `app-metadata.json` to `1.0.3` and moved the shared child verb to `System Tools > Windows > Take Ownership`.
- Regenerated `Install.ps1` from `InstallerCore` with cleanup for the incorrect `WindowsUtilities` migration path.
- Bumped `app-metadata.json` to `1.0.2` for the shared `System Tools > Windows Utilities` layout move.
- Regenerated `Install.ps1` from `InstallerCore` so the context-menu child verb installs under `SystemTools\shell\WindowsUtilities\shell\TakeOwnership`.

## 2026-05-11

- Bumped `app-metadata.json` to `1.0.1` for the user-facing commit-aware `Update app` behavior change.
- Έγινε commit-aware το plain-`pwsh` `Update app` status: local/latest version, local/latest commit, source kind και dirty state.
- Hardened update-status caching so stale `UpToDate` results are not reused when a fresh remote check fails.
- Changed git working-copy updates to use `git fetch` + fast-forward only and refuse dirty workspaces.
- Kept installed-copy updates on the recorded InstallerCore source, defaulting to `UpdateGitHub` for GitHub installs, while comparing `state\install-meta.json` `github_commit` against the latest remote commit.
- Kept non-git portable-copy updates on `DownloadLatest -NoSelfRelaunch` with visible progress, recent output, relaunch, and old-host exit.
- Regenerated `Install.ps1` from the current `InstallerCore` profile/template.

## 2026-04-24

- Added `app-metadata.json` so `TakeOwnership` has a canonical app version/repo contract.
- Added plain-`pwsh` in-app update status to the ownership manager header.
- Added an `Update app` menu item that uses the generated `Install.ps1` flow without a Windows Terminal bootstrap.
- Regenerated `Install.ps1` from the current `InstallerCore` template/profile so it includes null-safe prompts, info-only `-NoExplorerRestart`, and commit-aware install metadata.
- Replaced the legacy `Get-WmiObject` safe-mode check with a PowerShell 7 compatible `Get-CimInstance` check.
- Aligned the in-app updater behavior with the `WinAppManager` pattern: visible update progress, recent installer output, automatic relaunch, and old-session exit.
