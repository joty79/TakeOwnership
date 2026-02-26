param(
    [string]$TargetFile
)

# 🔵 Configuration
$BackupDir = "$PSScriptRoot\ACL_Backups"
$BundledRunAsTI = Join-Path $PSScriptRoot 'assets\RunAsTI\RunAsTI.ps1'
$LegacyRunAsTI  = 'D:\Users\joty79\scripts\RunAsTI\RunAsTI.ps1'
$RunAsTI        = if (Test-Path -LiteralPath $BundledRunAsTI) { $BundledRunAsTI } elseif (Test-Path -LiteralPath $LegacyRunAsTI) { $LegacyRunAsTI } else { '' }

# 🔸 Force UTF-8 Encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---
# 🔵 PHASE 1: SELF-ELEVATION TO TI (with Safe Mode fallback)
# ---
$CurrentID = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Safe Mode Detection: TrustedInstaller δεν υπάρχει σε Safe Mode
$tiService = Get-Service TrustedInstaller -ErrorAction SilentlyContinue
$isSafeMode = ($tiService -eq $null) -or ((Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).BootupState -match "safe|Fail")

if ($isSafeMode) {
    # Safe Mode: Elevation μόνο σε Admin (χωρίς TI)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "🔸 Safe Mode — Elevating to Admin..." -ForegroundColor Yellow
        Start-Process pwsh.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -TargetFile `"$TargetFile`"" -Verb RunAs
        exit
    }
    Write-Host "⚠️  Safe Mode Detected — Τρέχει ως Admin (χωρίς TrustedInstaller)" -ForegroundColor Magenta
} elseif ($CurrentID -notmatch "SYSTEM" -and $CurrentID -notmatch "TrustedInstaller") {
    if ([string]::IsNullOrWhiteSpace($RunAsTI)) {
        Write-Host "⚠️ RunAsTI.ps1 not found. Expected: $BundledRunAsTI" -ForegroundColor Red
        exit 1
    }
    Write-Host "🔸 Elevating to TrustedInstaller..." -ForegroundColor Yellow
    $MyPath = $MyInvocation.MyCommand.Path
    
    # Forward arguments correctly
    # We call RunAsTI.ps1 -Command "pwsh" -Arguments "..."
    $ScriptArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$MyPath`" -TargetFile `"$TargetFile`""
    
    # Start RunAsTI.ps1
    # We use Start-Process pwsh to run the elevation script.
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$RunAsTI`" -Command `"pwsh`" -Arguments `'$ScriptArgs`'" -WindowStyle Hidden
    exit
}

# ---
# 🔵 PHASE 2: SYSTEM / TI MODE
# ---
Start-Service TrustedInstaller -ErrorAction SilentlyContinue
if (!(Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

$MD5 = [System.Security.Cryptography.HashAlgorithm]::Create("MD5")
if ($TargetFile) {
    $PathBytes = [System.Text.Encoding]::UTF8.GetBytes($TargetFile.ToLower())
    $HashString = [BitConverter]::ToString($MD5.ComputeHash($PathBytes)).Replace("-", "")
    $BackupFile = "$BackupDir\$HashString.sddl"
}

# ---
# 🔵 FUNCTION: Take Ownership
# ---
function Take-Ownership {
    Write-Host "`n🔵 TAKING OWNERSHIP (TI Direct)" -ForegroundColor Cyan
    Write-Host "-------------------"
    
    if (!(Test-Path $BackupFile)) {
        try {
            $Acl = Get-Acl -Path $TargetFile
            $Acl.Sddl | Out-File -FilePath $BackupFile -Encoding UTF8
            Write-Host "✅ Backup Created: $HashString" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠️ Backup Failed! Aborting." -ForegroundColor Red; return
        }
    } else {
        Write-Host "💡 Backup exists. Keeping original state." -ForegroundColor Yellow
    }

    $IsDirectory = (Get-Item $TargetFile) -is [System.IO.DirectoryInfo]
    
    Write-Host "🔸 Seizing Ownership..." -ForegroundColor Gray
    if ($IsDirectory) {
        $Res = takeown.exe /f $TargetFile /a /r /d Y 2>&1
    } else {
        $Res = takeown.exe /f $TargetFile /a 2>&1
    }

    if ($LASTEXITCODE -ne 0) { Write-Host "⚠️ TakeOwn Error: $Res" -ForegroundColor Red }
    else { Write-Host "✅ Ownership Seized." -ForegroundColor Green }
    
    Write-Host "🔸 Granting Administrators Access..." -ForegroundColor Gray
    $Icacls = icacls.exe $TargetFile /grant "Administrators:F" /t /c /q 2>&1
    
    if ($LASTEXITCODE -ne 0) { Write-Host "⚠️ Icacls Error: $Icacls" -ForegroundColor Red }
    else { Write-Host "✅ Permissions Granted." -ForegroundColor Green }
}

# ---
# 🔵 FUNCTION: Restore Ownership (AUTO-RECURSIVE)
# ---
function Restore-Ownership {
    Write-Host "`n🔵 RESTORING OWNERSHIP (TI Direct)" -ForegroundColor Cyan
    Write-Host "-------------------"

    if (!(Test-Path $BackupFile)) {
        Write-Host "⚠️ No backup found." -ForegroundColor Red
        return
    }

    try {
        Write-Host "🔸 Reading Backup..."
        $SddlString = Get-Content -Path $BackupFile -Raw
        
        # 1. Restore Parent (The Target itself)
        Write-Host "🔸 Restoring Target..."
        $Acl = Get-Acl -Path $TargetFile
        $Acl.SetSecurityDescriptorSddlForm($SddlString)
        Set-Acl -Path $TargetFile -AclObject $Acl
        Write-Host "✅ Target Restored." -ForegroundColor Green
        
        # 2. Check & Exec Recursive (No questions asked)
        $IsDirectory = (Get-Item $TargetFile) -is [System.IO.DirectoryInfo]
        
        if ($IsDirectory) {
            Write-Host "🔸 Scanning Sub-items for Deep Restore..." -ForegroundColor Cyan
            
            # Get all sub-items
            $Items = Get-ChildItem -Path $TargetFile -Recurse -Force
            $Total = $Items.Count
            $Count = 0
            
            foreach ($Item in $Items) {
                $Count++
                # Εμφανίζει πρόοδο κάθε 50 αρχεία για να μην καθυστερεί την κονσόλα
                if ($Count % 50 -eq 0) { 
                    Write-Progress -Activity "Restoring Permissions" -Status "$Count / $Total" -PercentComplete (($Count / $Total) * 100) 
                }
                
                try {
                    # Εφαρμόζει το IDIO SDDL (του μπαμπά) σε όλα τα παιδιά.
                    # Αυτό επαναφέρει το ownership στο SYSTEM (συνήθως) και καθαρίζει τα permissions.
                    $SubAcl = Get-Acl -Path $Item.FullName
                    $SubAcl.SetSecurityDescriptorSddlForm($SddlString)
                    Set-Acl -Path $Item.FullName -AclObject $SubAcl -ErrorAction SilentlyContinue
                }
                catch {
                    # Αγνοούμε αρχεία που χρησιμοποιούνται
                }
            }
            Write-Progress -Activity "Restoring Permissions" -Completed
            Write-Host "✅ Recursive Restore Complete ($Total items)." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "⚠️ Restore Failed: $_" -ForegroundColor Red
    }
}

# ---
# 🔵 MAIN LOOP
# ---
do {
    Clear-Host
    Write-Host "🔵 OWNERSHIP MANAGER (V10 - AUTO RECURSIVE)" -ForegroundColor Cyan
    Write-Host "   User: $CurrentID" -ForegroundColor DarkGray
    Write-Host "   Target: $TargetFile" -ForegroundColor Gray
    Write-Host "------------------------------"
    
    Write-Host "[1]   Take Ownership" -ForegroundColor White
    Write-Host "[2]   Restore Original" -ForegroundColor White
    Write-Host "[3] [X] Exit" -ForegroundColor Gray
    
    Write-Host "------------------------------"
    $Choice = Read-Host "🔸 Choose Action"

    switch ($Choice) {
        "1" { Take-Ownership; Write-Host "`nPress any key..." -ForegroundColor Gray; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        "2" { Restore-Ownership; Write-Host "`nPress any key..." -ForegroundColor Gray; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        "3" { exit }
    }
} while ($true)
