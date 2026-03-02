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

### Entry - 2026-03-02 (Legacy HKLM cleanup for old Manage Ownership installs)
- Date: 2026-03-02
- Problem: Old `Manage Ownership` context-menu entries could remain after uninstall because earlier installs had written standalone keys under `HKLM\SOFTWARE\Classes\...`.
- Root cause: Current installer was user-scope (`HKCU`) only and did not attempt targeted cleanup of known legacy machine-scope keys.
- Guardrail/rule: `TakeOwnership` uninstall should perform best-effort cleanup of known legacy `HKLM\SOFTWARE\Classes\*\shell\Z_ManageOwnership|ManageOwnership` and `Directory\shell\...` keys, but treat Access Denied as warning-only so non-elevated user-scope uninstall still completes.
- Files affected: `Install.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation on `Install.ps1`; static review of cleanup key list and Access Denied handling.

### Entry - 2026-03-02 (Do not emit empty SubCommands on shared System Tools parents)
- Date: 2026-03-02
- Problem: `TakeOwnership` could break or suppress the `System Tools` cascade on branches it introduced itself, especially the file branch.
- Root cause: The local installer/manual registry definition wrote `SubCommands=""` on shared `SystemTools` parent keys even though the menu is built from nested `shell\TakeOwnership` child keys.
- Guardrail/rule: For `TakeOwnership` shared submenu integration, emit only `MUIVerb` and `Icon` on the `SystemTools` parent and let nested `shell\...` children define the cascade; do not write empty `SubCommands` values.
- Files affected: `Install.ps1`, `Manage_Ownership.reg`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation on `Install.ps1`; static diff review of parent key values.

### Entry - 2026-03-02 (TakeOwnership is child-only under System Tools)
- Date: 2026-03-02
- Problem: Repeating the `WhoIsUsingThis` integration approach caused the same submenu failure: child repo tried to help by creating shared `SystemTools` parent keys.
- Root cause: Submenu ownership was mixed between the host repo (`SystemTools`) and the child repo (`TakeOwnership`).
- Guardrail/rule: `TakeOwnership` must be child-only under the shared submenu. It may register only `*\shell\SystemTools\shell\TakeOwnership` and `Directory\shell\SystemTools\shell\TakeOwnership` plus targeted legacy cleanup; it must never create, patch, or remove the shared `SystemTools` parent keys.
- Files affected: `Install.ps1`, `Manage_Ownership.reg`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated installer from updated `InstallerCore` profile; parser validation on `Install.ps1`; static review of manual `.reg`.

### Entry - 2026-03-02 (Regenerated after empty-string registry helper hardening)
- Date: 2026-03-02
- Problem: Generated installer inherited a fragile template helper for empty-string registry writes.
- Root cause: `InstallerCore` template still used a literal `""` conversion pattern for empty `REG_SZ` values before the shared helper was hardened.
- Guardrail/rule: Keep `Install.ps1` generated from the current `InstallerCore` template after helper fixes; do not keep stale generated installers once registry write semantics change in the template.
- Files affected: `Install.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated `Install.ps1` from `InstallerCore`; parser validation on generated installer; targeted scan confirmed the old literal `""` pattern is absent.

