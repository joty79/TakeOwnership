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

$script:AppName = 'TakeOwnership'
$script:AppVersion = '1.0.0'
$script:GitHubRepo = 'joty79/TakeOwnership'
$script:MetadataPath = Join-Path $PSScriptRoot 'app-metadata.json'
$script:StatePath = Join-Path $PSScriptRoot 'state'
$script:InstallMetaPath = Join-Path $script:StatePath 'install-meta.json'
$script:UpdateStatusCachePath = Join-Path $script:StatePath 'app-update-status.json'
$script:UpdateStatusCacheTtlMinutes = 30
$script:UpdateStatus = $null

function New-UpdateStatus {
    param(
        [string]$LocalVersion = $script:AppVersion,
        [AllowEmptyString()][string]$LatestVersion = '',
        [AllowEmptyString()][string]$Repo = $script:GitHubRepo,
        [AllowEmptyString()][string]$Branch = '',
        [ValidateSet('Unknown', 'UpToDate', 'UpdateAvailable', 'LocalAhead', 'Error')]
        [string]$Status = 'Unknown',
        [string]$Message = 'Update status has not been checked yet.',
        [AllowEmptyString()][string]$CheckedAt = '',
        [AllowEmptyString()][string]$LocalCommit = '',
        [AllowEmptyString()][string]$RemoteCommit = ''
    )

    [pscustomobject]@{
        LocalVersion  = $LocalVersion
        LatestVersion = $LatestVersion
        Repo          = $Repo
        Branch        = $Branch
        Status        = $Status
        Message       = $Message
        CheckedAt     = $CheckedAt
        LocalCommit   = $LocalCommit
        RemoteCommit  = $RemoteCommit
    }
}

function Initialize-AppMetadata {
    $script:UpdateStatus = New-UpdateStatus
    if (-not (Test-Path -LiteralPath $script:MetadataPath -PathType Leaf)) { return }

    try {
        $metadata = Get-Content -LiteralPath $script:MetadataPath -Raw | ConvertFrom-Json
        $nameProperty = $metadata.PSObject.Properties['app_name']
        if ($null -ne $nameProperty -and -not [string]::IsNullOrWhiteSpace([string]$nameProperty.Value)) {
            $script:AppName = [string]$nameProperty.Value
        }

        $versionProperty = $metadata.PSObject.Properties['version']
        if ($null -ne $versionProperty -and -not [string]::IsNullOrWhiteSpace([string]$versionProperty.Value)) {
            $script:AppVersion = [string]$versionProperty.Value
        }

        $repoProperty = $metadata.PSObject.Properties['github_repo']
        if ($null -ne $repoProperty -and -not [string]::IsNullOrWhiteSpace([string]$repoProperty.Value)) {
            $script:GitHubRepo = [string]$repoProperty.Value
        }

        $script:UpdateStatus = New-UpdateStatus -LocalVersion $script:AppVersion -Repo $script:GitHubRepo
    }
    catch {
        $script:UpdateStatus = New-UpdateStatus -Status 'Error' -Message 'Could not read local app metadata.'
    }
}

function ConvertTo-AppVersion {
    param([AllowEmptyString()][string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) { return $null }
    try { return [version]$VersionText }
    catch { return $null }
}

function Read-UpdateStatusCache {
    param([switch]$AllowStale)

    if (-not (Test-Path -LiteralPath $script:UpdateStatusCachePath -PathType Leaf)) { return $null }

    try {
        $cacheItem = Get-Item -LiteralPath $script:UpdateStatusCachePath -ErrorAction Stop
        if (-not $AllowStale -and ((Get-Date) - $cacheItem.LastWriteTime).TotalMinutes -gt $script:UpdateStatusCacheTtlMinutes) {
            return $null
        }

        $cache = Get-Content -LiteralPath $script:UpdateStatusCachePath -Raw | ConvertFrom-Json
        return (New-UpdateStatus `
            -LocalVersion ([string]$cache.LocalVersion) `
            -LatestVersion ([string]$cache.LatestVersion) `
            -Repo ([string]$cache.Repo) `
            -Branch ([string]$cache.Branch) `
            -Status ([string]$cache.Status) `
            -Message ([string]$cache.Message) `
            -CheckedAt ([string]$cache.CheckedAt) `
            -LocalCommit ([string]$cache.LocalCommit) `
            -RemoteCommit ([string]$cache.RemoteCommit))
    }
    catch {
        return $null
    }
}

function Write-UpdateStatusCache {
    param([Parameter(Mandatory)]$Status)

    try {
        if (-not (Test-Path -LiteralPath $script:StatePath -PathType Container)) {
            New-Item -Path $script:StatePath -ItemType Directory -Force | Out-Null
        }
        $Status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:UpdateStatusCachePath -Encoding UTF8
    }
    catch {}
}

function Get-RemoteAppMetadata {
    if ([string]::IsNullOrWhiteSpace($script:GitHubRepo)) { return $null }

    foreach ($branch in @('master', 'main')) {
        $rawUri = "https://raw.githubusercontent.com/$($script:GitHubRepo)/$branch/app-metadata.json"
        try {
            $metadata = Invoke-RestMethod -Uri $rawUri -Method Get -Headers @{ 'User-Agent' = "$($script:AppName)/$($script:AppVersion)" } -TimeoutSec 8
            if ($null -ne $metadata) {
                return [pscustomobject]@{
                    Metadata = $metadata
                    Repo     = $script:GitHubRepo
                    Branch   = $branch
                }
            }
        }
        catch {}
    }

    return $null
}

function Get-InstalledCommitInfo {
    $result = [ordered]@{
        GitHubCommit = ''
        GitHubRef    = ''
    }

    if (-not (Test-Path -LiteralPath $script:InstallMetaPath -PathType Leaf)) {
        return [pscustomobject]$result
    }

    try {
        $installMeta = Get-Content -LiteralPath $script:InstallMetaPath -Raw | ConvertFrom-Json
        foreach ($item in @(
            @{ Name = 'github_commit'; Target = 'GitHubCommit' },
            @{ Name = 'github_ref'; Target = 'GitHubRef' }
        )) {
            $property = $installMeta.PSObject.Properties[$item.Name]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $result[$item.Target] = [string]$property.Value
            }
        }
    }
    catch {}

    return [pscustomobject]$result
}

function Get-RemoteCommit {
    param(
        [AllowEmptyString()][string]$Repo = $script:GitHubRepo,
        [AllowEmptyString()][string]$Ref = 'master'
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Ref)) { return '' }

    try {
        $commitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits/$Ref" -Method Get -Headers @{ 'User-Agent' = "$($script:AppName)/$($script:AppVersion)" } -TimeoutSec 8
        if ($null -ne $commitInfo -and -not [string]::IsNullOrWhiteSpace([string]$commitInfo.sha)) {
            return [string]$commitInfo.sha
        }
    }
    catch {}

    return ''
}

function Resolve-UpdateStatus {
    param([switch]$ForceRefresh)

    if (-not $ForceRefresh) {
        $cachedStatus = Read-UpdateStatusCache
        if ($null -ne $cachedStatus) {
            $script:UpdateStatus = $cachedStatus
            return $script:UpdateStatus
        }
    }

    $staleCachedStatus = Read-UpdateStatusCache -AllowStale
    $remoteInfo = Get-RemoteAppMetadata
    if ($null -eq $remoteInfo) {
        if ($null -ne $staleCachedStatus) {
            $staleCachedStatus.Message = 'Using cached update status because GitHub could not be reached.'
            $script:UpdateStatus = $staleCachedStatus
            return $script:UpdateStatus
        }

        $script:UpdateStatus = New-UpdateStatus -LocalVersion $script:AppVersion -Repo $script:GitHubRepo -Status 'Error' -Message 'Could not reach GitHub to check updates.' -CheckedAt ((Get-Date).ToString('s'))
        return $script:UpdateStatus
    }

    $latestVersionProperty = $remoteInfo.Metadata.PSObject.Properties['version']
    $latestVersion = if ($null -ne $latestVersionProperty) { [string]$latestVersionProperty.Value } else { '' }
    $localVersionObject = ConvertTo-AppVersion -VersionText $script:AppVersion
    $remoteVersionObject = ConvertTo-AppVersion -VersionText $latestVersion
    $statusName = 'Unknown'
    $statusMessage = 'Update status is unavailable.'
    $commitInfo = Get-InstalledCommitInfo
    $localCommit = [string]$commitInfo.GitHubCommit
    $remoteCommit = Get-RemoteCommit -Repo ([string]$remoteInfo.Repo) -Ref ([string]$remoteInfo.Branch)

    if ($null -ne $localVersionObject -and $null -ne $remoteVersionObject) {
        if ($localVersionObject -lt $remoteVersionObject) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available: v$latestVersion"
        }
        elseif ($localVersionObject -gt $remoteVersionObject) {
            $statusName = 'LocalAhead'
            $statusMessage = "Local version v$script:AppVersion is ahead of origin."
        }
        else {
            $statusName = 'UpToDate'
            $statusMessage = "App is up to date at v$latestVersion."
        }
    }

    if ($statusName -in @('UpToDate', 'Unknown') -and
        -not [string]::IsNullOrWhiteSpace($localCommit) -and
        -not [string]::IsNullOrWhiteSpace($remoteCommit) -and
        $localCommit -ne $remoteCommit) {
        $statusName = 'UpdateAvailable'
        $statusMessage = "Update available: remote $($remoteInfo.Branch) has newer code."
    }

    $script:UpdateStatus = New-UpdateStatus `
        -LocalVersion $script:AppVersion `
        -LatestVersion $latestVersion `
        -Repo ([string]$remoteInfo.Repo) `
        -Branch ([string]$remoteInfo.Branch) `
        -Status $statusName `
        -Message $statusMessage `
        -LocalCommit $localCommit `
        -RemoteCommit $remoteCommit `
        -CheckedAt ((Get-Date).ToString('s'))

    Write-UpdateStatusCache -Status $script:UpdateStatus
    return $script:UpdateStatus
}

function Get-UpdateLabel {
    if ($null -eq $script:UpdateStatus) { $script:UpdateStatus = New-UpdateStatus }

    switch ([string]$script:UpdateStatus.Status) {
        'UpToDate' { return 'Up to date' }
        'UpdateAvailable' {
            if ([string]::IsNullOrWhiteSpace([string]$script:UpdateStatus.LatestVersion)) { return 'Update available' }
            return "Update available ($($script:UpdateStatus.LatestVersion))"
        }
        'LocalAhead' { return 'Local version ahead' }
        'Error' { return 'Update check failed' }
        default { return 'Status unavailable' }
    }
}

function Get-InstallerAction {
    $defaultInstallPath = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'TakeOwnershipContext')).TrimEnd('\')
    $currentRootPath = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    if ($currentRootPath -ieq $defaultInstallPath) {
        return 'UpdateGitHub'
    }

    return 'DownloadLatest'
}

function Get-RecentTextFileLines {
    param(
        [AllowEmptyString()][string]$Path,
        [int]$TailCount = 10
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    try {
        return @(Get-Content -LiteralPath $Path -Tail $TailCount -ErrorAction Stop | ForEach-Object { [string]$_ })
    }
    catch {
        return @()
    }
}

function Write-UpdateSection {
    param([string]$Title)

    Write-Host ""
    Write-Host "◆ $Title " -ForegroundColor Cyan -NoNewline
    Write-Host ("-" * 58) -ForegroundColor DarkGray
}

function Show-AppUpdateResultPanel {
    param(
        [string]$ResultMessage,
        [ValidateSet('Info', 'Good', 'Warn', 'Error')]
        [string]$Level = 'Info',
        [string[]]$RecentLines = @(),
        [switch]$AutoRestart
    )

    $messageColor = switch ($Level) {
        'Good' { 'Green' }
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        default { 'Cyan' }
    }

    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host ("║ {0} v{1}" -f $script:AppName, $script:AppVersion).PadRight(79) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║ Ownership + TrustedInstaller + Context Menu".PadRight(79) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host ("║ Update: {0}" -f (Get-UpdateLabel)).PadRight(79) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-UpdateSection -Title 'Update App'
    Write-Host "  $ResultMessage" -ForegroundColor $messageColor

    if (@($RecentLines).Count -gt 0) {
        Write-UpdateSection -Title 'Recent Output'
        foreach ($line in @($RecentLines | Select-Object -Last 10)) {
            $displayLine = [string]$line
            if ($displayLine.Length -gt 118) {
                $displayLine = $displayLine.Substring(0, 115) + '...'
            }
            Write-Host "  $displayLine" -ForegroundColor DarkGray
        }
    }

    Write-UpdateSection -Title 'Commands'
    if ($AutoRestart) {
        Write-Host "  Restarting $script:AppName in pwsh..." -ForegroundColor Green
    }
    else {
        Write-Host "  ESC back" -ForegroundColor Red
    }
}

function Start-UpdatedAppHost {
    param([string]$AppRoot = $PSScriptRoot)

    $appPath = Join-Path $AppRoot 'Manage_Ownership.ps1'
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
        return $false
    }

    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwshCommand -or -not (Test-Path -LiteralPath $pwshCommand.Source -PathType Leaf)) {
        return $false
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $appPath
    )
    if (-not [string]::IsNullOrWhiteSpace($TargetFile)) {
        $arguments += @('-TargetFile', $TargetFile)
    }

    try {
        Start-Process -FilePath $pwshCommand.Source -ArgumentList $arguments -WorkingDirectory $AppRoot | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Request-ApplicationHostExit {
    try { $Host.SetShouldExit(0) } catch {}
    exit 0
}

function Invoke-AppUpdate {
    $installerPath = Join-Path $PSScriptRoot 'Install.ps1'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        return [pscustomobject]@{ Success = $false; Message = 'Install.ps1 was not found next to this script.' }
    }

    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwshCommand -or -not (Test-Path -LiteralPath $pwshCommand.Source -PathType Leaf)) {
        return [pscustomobject]@{ Success = $false; Message = 'pwsh.exe was not found.' }
    }

    $action = Get-InstallerAction
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installerPath,
        '-Action', $action,
        '-Force'
    )

    if ($action -eq 'UpdateGitHub') {
        $arguments += '-NoExplorerRestart'
    }
    if ($action -eq 'DownloadLatest') {
        $arguments += '-NoSelfRelaunch'
    }

    $progressMessage = if ($action -eq 'UpdateGitHub') {
        'Updating from GitHub inside the current app session...'
    }
    else {
        'Updating this working copy with the best available repo-aware path...'
    }
    $stdoutPath = Join-Path $env:TEMP ("TakeOwnership_updater_out_{0}.log" -f [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path $env:TEMP ("TakeOwnership_updater_err_{0}.log" -f [guid]::NewGuid().ToString('N'))
    $installerLogPath = Join-Path $PSScriptRoot 'logs\installer.log'

    try {
        $process = Start-Process -FilePath $pwshCommand.Source -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
        while (-not $process.HasExited) {
            $recentLines = @((Get-RecentTextFileLines -Path $installerLogPath -TailCount 8) + (Get-RecentTextFileLines -Path $stderrPath -TailCount 3))
            Show-AppUpdateResultPanel -ResultMessage $progressMessage -Level 'Info' -RecentLines $recentLines
            Start-Sleep -Milliseconds 250
        }

        $process.Refresh()
        $exitCode = [int]$process.ExitCode
        $finalLines = @((Get-RecentTextFileLines -Path $installerLogPath -TailCount 8) + (Get-RecentTextFileLines -Path $stderrPath -TailCount 5))
        if ($exitCode -le 2) {
            Show-AppUpdateResultPanel -ResultMessage 'Update finished. Restarting the updated app host and closing this window...' -Level 'Good' -RecentLines $finalLines -AutoRestart
            Start-Sleep -Milliseconds 900
            if (Start-UpdatedAppHost -AppRoot $PSScriptRoot) {
                Request-ApplicationHostExit
            }

            return [pscustomobject]@{ Success = $false; Message = 'Update finished, but the app could not relaunch automatically.' }
        }

        Show-AppUpdateResultPanel -ResultMessage ("Update failed with exit code {0}." -f $exitCode) -Level 'Error' -RecentLines $finalLines
        return [pscustomobject]@{ Success = $false; Message = "Update failed with exit code $exitCode." }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Message = "Could not start updater: $($_.Exception.Message)" }
    }
    finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            try {
                if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {}
        }
    }
}

function Show-UpdateMenu {
    do {
        Clear-Host
        Write-Host "🔵 $script:AppName Update" -ForegroundColor Cyan
        Write-Host "------------------------------"
        Write-Host "Current version: $script:AppVersion" -ForegroundColor Gray
        Write-Host "Latest version : $(if ([string]::IsNullOrWhiteSpace([string]$script:UpdateStatus.LatestVersion)) { '--' } else { $script:UpdateStatus.LatestVersion })" -ForegroundColor Gray
        Write-Host "Update        : $(Get-UpdateLabel)" -ForegroundColor Yellow
        Write-Host "Repo / branch : $($script:UpdateStatus.Repo) / $(if ([string]::IsNullOrWhiteSpace([string]$script:UpdateStatus.Branch)) { '--' } else { $script:UpdateStatus.Branch })" -ForegroundColor DarkGray
        Write-Host "Message       : $($script:UpdateStatus.Message)" -ForegroundColor DarkGray
        Write-Host "------------------------------"
        Write-Host "[1] Run update now" -ForegroundColor White
        Write-Host "[2] Refresh update status" -ForegroundColor White
        Write-Host "[3] Back" -ForegroundColor Gray
        Write-Host "------------------------------"
        $choice = Read-Host "Choose Action"

        switch ($choice) {
            "1" {
                $result = Invoke-AppUpdate
                if ($result.Success) {
                    Write-Host $result.Message -ForegroundColor Green
                }
                else {
                    Write-Host $result.Message -ForegroundColor Red
                }
                Write-Host "`nPress any key..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                [void](Resolve-UpdateStatus -ForceRefresh)
            }
            "2" {
                [void](Resolve-UpdateStatus -ForceRefresh)
            }
            "3" { return }
        }
    } while ($true)
}

# ---
# 🔵 PHASE 1: SELF-ELEVATION TO TI (with Safe Mode fallback)
# ---
$CurrentID = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Safe Mode Detection: TrustedInstaller δεν υπάρχει σε Safe Mode
$tiService = Get-Service TrustedInstaller -ErrorAction SilentlyContinue
$bootupState = ''
try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($null -ne $computerSystem) { $bootupState = [string]$computerSystem.BootupState }
}
catch {}
$isSafeMode = ($tiService -eq $null) -or ($bootupState -match "safe|Fail")

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
Initialize-AppMetadata
[void](Resolve-UpdateStatus)

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
        & takeown.exe /f $TargetFile /a /r /d Y > $null 2>&1
    } else {
        & takeown.exe /f $TargetFile /a > $null 2>&1
    }

    if ($LASTEXITCODE -ne 0) { Write-Host "⚠️ TakeOwn failed (exit code: $LASTEXITCODE)" -ForegroundColor Red }
    else { Write-Host "✅ Ownership Seized." -ForegroundColor Green }
    
    Write-Host "🔸 Granting Administrators Access..." -ForegroundColor Gray
    & icacls.exe $TargetFile /grant "Administrators:F" /t /c /q > $null 2>&1
    
    if ($LASTEXITCODE -ne 0) { Write-Host "⚠️ Icacls failed (exit code: $LASTEXITCODE)" -ForegroundColor Red }
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
    Write-Host "🔵 $script:AppName v$script:AppVersion (V10 - AUTO RECURSIVE)" -ForegroundColor Cyan
    Write-Host "   User: $CurrentID" -ForegroundColor DarkGray
    Write-Host "   Update: $(Get-UpdateLabel)" -ForegroundColor DarkGray
    Write-Host "   Target: $TargetFile" -ForegroundColor Gray
    Write-Host "------------------------------"
    
    Write-Host "[1]   Take Ownership" -ForegroundColor White
    Write-Host "[2]   Restore Original" -ForegroundColor White
    Write-Host "[3] ⟳  Update app" -ForegroundColor White
    Write-Host "[4] [X] Exit" -ForegroundColor Gray
    
    Write-Host "------------------------------"
    $Choice = Read-Host "🔸 Choose Action"

    switch ($Choice) {
        "1" { Take-Ownership; Write-Host "`nPress any key..." -ForegroundColor Gray; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        "2" { Restore-Ownership; Write-Host "`nPress any key..." -ForegroundColor Gray; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        "3" { Show-UpdateMenu }
        "4" { exit }
    }
} while ($true)
