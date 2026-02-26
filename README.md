# TakeOwnership

TrustedInstaller-powered context menu για να κάνεις `Take Ownership` και `Restore Original` σε files/folders από δεξί κλικ, με backup του αρχικού ACL state.

## 🔵 Γιατί να το χρησιμοποιήσεις

- Όταν παίρνεις `Access is denied` ακόμα και ως admin.
- Όταν θέλεις προσωρινά πλήρη πρόσβαση σε protected paths.
- Όταν θέλεις να μπορείς να επιστρέψεις στο αρχικό ownership/ACL state.

## 🔵 Τι προσφέρει

- `Take Ownership` με `takeown.exe` + `icacls.exe`.
- `Restore Original` από αποθηκευμένο SDDL backup.
- Auto-recursive restore για directories.
- Elevation chain:
  - normal mode -> UAC admin
  - admin mode -> TrustedInstaller (via bundled `RunAsTI.ps1`)
  - Safe Mode fallback -> admin-only execution
- Hidden launch από `SilentOwnership.vbs` για καθαρό UX στο context menu.
- Installer-based deployment με `Install / Update / Uninstall`.

## 🔵 Πώς δουλεύει

1. Δεξί κλικ σε file/folder -> `Manage Ownership`.
2. Το `SilentOwnership.vbs` ξεκινά hidden flow και κάνει elevation.
3. Το `Manage_Ownership.ps1` δείχνει menu:
   - `[1] Take Ownership`
   - `[2] Restore Original`
4. Πριν το takeover αποθηκεύει ACL backup σε `ACL_Backups\<md5>.sddl`.
5. Το restore επαναφέρει ACL/owner από το backup.

## 🔵 Εγκατάσταση

### Option A: Installer (recommended)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Default install path:
- `%LOCALAPPDATA%\TakeOwnershipContext`

Installer actions:
- `Install`
- `Update`
- `Uninstall`
- `OpenInstallDirectory`
- `OpenInstallLogs`

### Option B: Manual `.reg` (advanced)

- Χρήση του `Manage_Ownership.reg` για άμεσο context-menu wiring.
- Προτείνεται installer γιατί κάνει και cleanup/verify.

## 🔵 Project Structure

- `Manage_Ownership.ps1`: core ownership logic + restore logic.
- `SilentOwnership.vbs`: hidden launcher + elevation wrapper.
- `Manage_Ownership.reg`: manual registry integration.
- `assets\RunAsTI\RunAsTI.ps1`: bundled TI dependency.
- `Install.ps1`: generated installer (InstallerCore profile-based).
- `PROJECT_RULES.md`: project memory / decisions.

## 🔵 Requirements

- Windows 10/11
- PowerShell 7 (`pwsh`)
- `wscript.exe`, `takeown.exe`, `icacls.exe`

## 🔵 Troubleshooting

- `Required TakeOwnership files are missing. Please reinstall.`  
  Re-run installer (`Install` or `Update`) ώστε να ξαναγίνει πλήρες deploy.

- Context menu δεν εμφανίζεται αμέσως  
  Κάνε Explorer restart (ή επίλεξε restart μέσα από installer flow).

- Δεν υπάρχει backup για restore  
  Το restore δουλεύει μόνο αν έχει προηγηθεί `Take Ownership` στο ίδιο target.

## ⚠️ Safety Notes

- Χρησιμοποίησέ το προσεκτικά σε system paths.
- Μην αφήνεις μόνιμα ownership αλλαγές χωρίς λόγο.
- Μετά από troubleshooting/debug, προτίμησε `Restore Original`.

