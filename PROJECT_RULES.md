# PROJECT_RULES - TakeOwnership

## Scope
- Repo: `D:\Users\joty79\scripts\TakeOwnership`
- Purpose: Ownership context-menu tool with TrustedInstaller elevation and installer-based deployment.

## Guardrails
- Keep tool logic in `Manage_Ownership.ps1`, hidden launcher in `SilentOwnership.vbs`, and manual integration in `Manage_Ownership.reg`.
- Avoid hardcoded absolute script paths; resolve runtime dependencies from script-relative install paths first.
- Installer-managed registry keys must live under `HKCU\Software\Classes\...` and cleanup should include `HKCR\...` merged-view leftovers.

## Decision Log

### Entry - 2026-02-26
- Date: 2026-02-26
- Problem: Tool broke after folder move because `.ps1/.vbs/.reg` used old hardcoded paths.
- Root cause: Launch scripts and manual registry file referenced legacy directories directly.
- Guardrail/rule: Use script-relative dependency resolution (`$PSScriptRoot` / `WScript.ScriptFullName`) and bundle `assets\RunAsTI\RunAsTI.ps1` for installer deployments.
- Files affected: `Manage_Ownership.ps1`, `SilentOwnership.vbs`, `Manage_Ownership.reg`, `assets\RunAsTI\RunAsTI.ps1`, `Install.ps1`.
- Validation/tests run: `Parser::ParseFile` passed for `Manage_Ownership.ps1` and generated `Install.ps1`; GitHub installer smoke tests ran (`InstallGitHub`, `UpdateGitHub`, `Uninstall`) with expected warning only when `-NoExplorerRestart` is used.

### Entry - 2026-03-02 (Move TakeOwnership under shared System Tools submenu)
- Date: 2026-03-02
- Problem: `TakeOwnership` still installed as standalone file/folder verbs and its generated installer lagged behind the current InstallerCore template behavior.
- Root cause: Local `Install.ps1` was generated from an older template snapshot and both installer/manual registry definitions still targeted legacy `Z_ManageOwnership` standalone keys.
- Guardrail/rule: `TakeOwnership` must register as a child verb under `*\shell\SystemTools\shell` and `Directory\shell\SystemTools\shell`, while keeping valid shared parent keys on those branches and using the current generated-installer behavior (branch picker, GitHub ref autodetect, clean Explorer restart).
- Files affected: `Install.ps1`, `Manage_Ownership.reg`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated local `Install.ps1` from current template, patched embedded profile for shared submenu keys, parser validation on `Install.ps1`.

