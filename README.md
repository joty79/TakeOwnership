<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows_10%2F11-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/PowerShell-7%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell">
  <img src="https://img.shields.io/badge/Elevation-TrustedInstaller-CC2927?style=for-the-badge&logo=windowsterminal&logoColor=white" alt="Elevation">
  <img src="https://img.shields.io/badge/Dependencies-Zero-2ea44f?style=for-the-badge" alt="Dependencies">
</p>

<h1 align="center">🛡️ TakeOwnership</h1>

<p align="center">
  <b>Take and restore file/folder ownership from the right-click context menu — with TrustedInstaller-level access</b><br>
  <sub>Seize ownership · Grant permissions · Restore originals — one click, fully reversible</sub>
</p>

---

## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| 🛡️ | **[Ownership Manager](#%EF%B8%8F-ownership-manager)** | Interactive take/restore ownership with ACL backup and TI elevation |
| 🔄 | **[In-app Update](#-in-app-update)** | Plain PowerShell update status and installer-driven refresh from the main menu |
| 👻 | **[Silent Launcher](#-silent-launcher)** | Zero-flash VBS wrapper that hides all intermediate windows |
| ⚡ | **[RunAsTI Engine](#-runasti-engine)** | TrustedInstaller token impersonation without third-party tools |

---

## 🛡️ Ownership Manager

> Right-click any file or folder, take full ownership as TrustedInstaller, and restore the original permissions when you're done — no manual `takeown`/`icacls` commands needed.

### The Problem

- Windows system files and folders are **owned by TrustedInstaller** — even Administrators can't modify them
- Running `takeown` + `icacls` manually is tedious and you inevitably **forget the original permissions**
- After modifying a protected file, there's no easy way to **restore the original ACL** to keep the system secure
- Standard "Take Ownership" registry hacks give you access but **never restore** the original state

### The Solution

A two-action interactive menu that backs up the original SDDL before taking ownership, and restores it on demand:

```
┌─────────────────────────────────────────────────────────────┐
│              OWNERSHIP MANAGER FLOW                         │
│                                                             │
│  Context Menu Click                                         │
│    │                                                        │
│    ├─→ SilentOwnership.vbs  (hidden, no flash)              │
│    │     │                                                  │
│    │     └─→ RunAsTI.ps1  (token impersonation)             │
│    │           │                                            │
│    │           └─→ Manage_Ownership.ps1  (as TI / SYSTEM)   │
│    │                                                        │
│    ▼                                                        │
│  ┌────────────────────────────────┐                         │
│  │ [1] Take Ownership            │                          │
│  │     • Backup ACL → .sddl file │                          │
│  │     • takeown /r /a            │                          │
│  │     • icacls Administrators:F  │                          │
│  │                                │                          │
│  │ [2] Restore Original          │                          │
│  │     • Read .sddl backup        │                          │
│  │     • Set-Acl (recursive)      │                          │
│  │     • Progress bar per item    │                          │
│  │                                │                          │
│  │ [3] Update app                │                          │
│  │     • Check version/commit     │                          │
│  │     • Run generated installer  │                          │
│  │                                │                          │
│  │ [4] Exit                      │                          │
│  └────────────────────────────────┘                         │
└─────────────────────────────────────────────────────────────┘
```

The ACL backup uses **SDDL format** (Security Descriptor Definition Language) — a compact, portable representation of the full security descriptor including owner, group, DACL, and SACL. Backups are stored as MD5-hashed filenames so each target path maps to a unique backup file.

### Usage

**From context menu** — *Right-click any file or folder → System Tools → Manage Ownership 🛡️*

**From terminal:**

```powershell
# Take ownership of a specific file
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Manage_Ownership.ps1 -TargetFile "C:\Windows\System32\some_file.dll"

# Take ownership of a folder (recursive)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Manage_Ownership.ps1 -TargetFile "C:\Windows\WinSxS\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TargetFile` | `string` | *(required)* | Full path to the file or folder to manage ownership for |

### Backup Location

ACL backups are saved to `ACL_Backups\` next to the script:

```
ACL_Backups/
├── C4C0F4A6D747E78A863009AC335AACDD.sddl   # MD5 of target path → SDDL content
└── C57E2295AB52D3D1A16AB90BB2AC12EE.sddl
```

Each `.sddl` file contains the original security descriptor. As long as the backup exists, **Restore** will return the target to its exact original state.

---

## 🔄 In-app Update

> `TakeOwnership` shows update status in the main header and exposes update actions from the same plain PowerShell menu.

This tool intentionally does **not** bootstrap into Windows Terminal. The RunAsTI chain works best in the current `pwsh` host, so the update UI stays compact and numbered instead of using the resize-safe WT TUI pattern used by other tools.

```
OWNERSHIP MANAGER
  Update: Up to date / Update available

[1] Take Ownership
[2] Restore Original
[3] Update app
[4] Exit
```

The update action reuses the generated `Install.ps1` instead of duplicating install logic in the ownership script.

---

## 👻 Silent Launcher

> A VBS wrapper that launches the ownership tool with zero visible windows — no PowerShell flash, no CMD popup, completely silent.

### The Problem

- Launching PowerShell scripts from context menu creates a **brief blue PowerShell window flash**
- The elevation chain involves multiple hops (VBS → PowerShell → RunAsTI → PowerShell) and each could flash
- Users expect context menu tools to feel **native** — no visible script execution

### The Solution

`SilentOwnership.vbs` acts as the entry point from the registry command. VBScript can launch processes with `WindowStyle Hidden` natively, and handles its own UAC elevation via `ShellExecute ... "runas"`:

```
┌──────────────────────────────────────────────┐
│  Registry Command                            │
│    wscript.exe "SilentOwnership.vbs" "%1"    │
│                                              │
│  VBS Actions:                                │
│    1. Check if running as Admin              │
│    2. If not → self-elevate via Shell.runas  │
│    3. Resolve script-relative paths          │
│    4. Launch RunAsTI.ps1 → hidden window     │
└──────────────────────────────────────────────┘
```

All paths are resolved from `WScript.ScriptFullName` — no hardcoded paths that break when the folder is moved.

---

## ⚡ RunAsTI Engine

> Impersonate the NT AUTHORITY\SYSTEM and TrustedInstaller tokens to run any command with the highest Windows privilege level — no third-party tools required.

### The Problem

- Even **Administrator** can't modify TrustedInstaller-owned files — Windows Resource Protection blocks it
- Tools like `PsExec -s` require **external downloads** from Sysinternals
- Running as SYSTEM still isn't enough for some operations — you need the actual **TrustedInstaller token**

### The Solution

`RunAsTI.ps1` (adapted from AveYo's RunAsTI) uses dynamic P/Invoke to call `CreateProcess` with a duplicated token from the TrustedInstaller service process:

```
┌───────────────────────────────────────────────────┐
│              RunAsTI Token Chain                   │
│                                                    │
│  1. Start TrustedInstaller service (if stopped)    │
│  2. Open TI process handle                         │
│  3. Duplicate token via CreateProcess              │
│  4. Inject command into registry-based bootstrap   │
│  5. Execute as NT AUTHORITY\SYSTEM with TI token   │
│                                                    │
│  Privileges granted:                               │
│    • SeSecurityPrivilege                           │
│    • SeTakeOwnershipPrivilege                      │
│    • SeBackupPrivilege                             │
│    • SeRestorePrivilege                            │
└───────────────────────────────────────────────────┘
```

Works silently in the background with no console windows visible to the user.

### Usage

```powershell
# Run any command as TrustedInstaller
pwsh -NoProfile -ExecutionPolicy Bypass -File .\assets\RunAsTI\RunAsTI.ps1 -Command "pwsh" -Arguments "-NoProfile -Command Get-Process"

# Universal mode: pass script + target file directly
pwsh -NoProfile -ExecutionPolicy Bypass -File .\assets\RunAsTI\RunAsTI.ps1 -TargetFile "C:\path" -ScriptPath "C:\script.ps1"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Command` | `string` | `""` | The executable to run as TrustedInstaller |
| `-Arguments` | `string` | `""` | Arguments to pass to the command |
| `-TargetFile` | `string` | `""` | Target file path (universal mode — auto-builds command) |
| `-ScriptPath` | `string` | `""` | Script to execute on the target (universal mode) |

---

## 📦 Installation

### Quick Setup

```powershell
# Install (registers context menu under System Tools + copies files)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Install

# Update from GitHub
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Update

# Uninstall (removes registry entries + installed files)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action Uninstall -Force
```

### Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 / 11 |
| **PowerShell** | pwsh 7+ (required for installer and main script) |
| **Privileges** | Admin — auto-requested; TrustedInstaller — auto-escalated via RunAsTI |
| **Dependencies** | None — pure Windows COM + native APIs |

### What the Installer Does

- Copies runtime files to `%LOCALAPPDATA%\TakeOwnershipContext\`
- Deploys `app-metadata.json` for version/update status
- Bundles `assets\RunAsTI\RunAsTI.ps1` alongside the main script
- Registers context menu entries under the shared **System Tools** submenu:
  - `*\shell\SystemTools\shell\TakeOwnership` — files
  - `Directory\shell\SystemTools\shell\TakeOwnership` — folders
  - `Directory\Background\shell\...` + `DesktopBackground\Shell\...` — backgrounds
- Cleans up legacy `Z_ManageOwnership` and `ManageOwnership` keys from previous versions
- Adds uninstall entry to Programs & Features

### Safe Mode Support

In Safe Mode, the TrustedInstaller service is not available. The script detects this automatically and falls back to standard **Administrator-level** elevation — enough for most ownership operations outside of WRP-protected files.

---

## 📁 Project Structure

```
TakeOwnership/
├── Manage_Ownership.ps1           # Main ownership manager (TI-elevated)
├── SilentOwnership.vbs            # Zero-flash VBS launcher
├── Install.ps1                    # Installer/updater/uninstaller
├── app-metadata.json              # App version/repo metadata for update checks
├── CHANGELOG.md                   # Shipped change history
├── Manage_Ownership.reg           # Static registry sample (manual import)
├── Manage_Ownership - Remove.reg  # Registry cleanup (manual removal)
├── assets/
│   └── RunAsTI/
│       └── RunAsTI.ps1            # TrustedInstaller token impersonation
├── ACL_Backups/                   # SDDL backup files (gitignored)
├── .gitignore                     # Excludes logs, state, backups
├── PROJECT_RULES.md               # Decision log and project guardrails
└── README.md                      # You are here
```

---

## 🧠 Technical Notes

<details>
<summary><b>Why a VBS launcher instead of launching PowerShell directly?</b></summary>

Registry context menu commands run synchronously in the shell. Launching `pwsh.exe` directly causes a **visible blue console flash** before the script can hide its window. VBScript's `WshShell.Run` with `WindowStyle 0` launches the entire chain hidden from the first millisecond. This gives the tool a native, flash-free feel despite running multiple PowerShell processes behind the scenes.

</details>

<details>
<summary><b>Why SDDL format for ACL backups instead of XML or binary?</b></summary>

SDDL (Security Descriptor Definition Language) is the **canonical, lossless** representation of Windows security descriptors. It captures owner, group, DACL, and SACL in a single compact string. PowerShell's `Get-Acl` and `Set-Acl` natively support SDDL via `GetSecurityDescriptorSddlForm()` and `SetSecurityDescriptorSddlForm()`, making it the most reliable round-trip format for ACL backup and restore.

</details>

<details>
<summary><b>Why MD5 hashing for backup filenames?</b></summary>

File paths can contain characters that are **illegal in filenames** (colons, special characters). Hashing the lowercase path with MD5 produces a consistent, filesystem-safe filename that uniquely maps to each target. This also means re-running Take Ownership on the same path won't overwrite the original backup — it detects the existing hash and preserves the first-captured ACL.

</details>

<details>
<summary><b>How does the RunAsTI token impersonation work?</b></summary>

RunAsTI (originally by AveYo) uses **dynamic P/Invoke** to call `CreateProcess` with a duplicated token from the TrustedInstaller service process. It starts the TI service if needed, opens its process handle, and creates a new process that inherits the TI token. The command payload is injected via a registry volatile key (`HKU\<SID>\Volatile Environment`) and executed by a hidden PowerShell bootstrap process. This achieves TrustedInstaller-level access without any external tools.

</details>

---

<p align="center">
  <sub>Built for Windows 10/11 · TrustedInstaller-level access · Fully reversible ownership changes · Zero dependencies</sub>
</p>
