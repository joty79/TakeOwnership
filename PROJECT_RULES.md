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

