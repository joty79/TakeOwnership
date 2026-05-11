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
$script:AppVersion = '1.0.1'
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
        [AllowEmptyString()][string]$LocalCommit = '',
        [AllowEmptyString()][string]$LatestCommit = '',
        [AllowEmptyString()][string]$SourceKind = 'Unknown',
        [bool]$HasLocalChanges = $false,
        [ValidateSet('Unknown', 'UpToDate', 'UpdateAvailable', 'LocalAhead', 'WorkspaceModified', 'Error')]
        [string]$Status = 'Unknown',
        [string]$Message = 'Update status has not been checked yet.',
        [AllowEmptyString()][string]$CheckedAt = '',
        [AllowEmptyString()][string]$Error = ''
    )

    $isKnown = $Status -in @('UpToDate', 'UpdateAvailable', 'LocalAhead', 'WorkspaceModified')
    [pscustomobject]@{
        LocalVersion    = $LocalVersion
        LatestVersion   = $LatestVersion
        LocalCommit     = $LocalCommit
        LatestCommit    = $LatestCommit
        SourceKind      = $SourceKind
        HasLocalChanges = $HasLocalChanges
        Repo            = $Repo
        Branch          = $Branch
        Status          = $Status
        IsKnown         = $isKnown
        IsUpToDate      = ($Status -eq 'UpToDate')
        Message         = $Message
        CheckedAt       = $CheckedAt
        Error           = $Error
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

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 50
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$InputObject
    )

    $parentPath = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentPath) -and -not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        New-Item -Path $parentPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $json = $InputObject | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Get-OptionalObjectPropertyValue {
    param(
        [object]$InputObject,
        [string]$PropertyName,
        $DefaultValue = $null
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Get-ShortGitCommitText {
    param([AllowEmptyString()][string]$Commit)

    if ([string]::IsNullOrWhiteSpace($Commit)) { return '--' }
    $normalizedCommit = $Commit.Trim()
    if ($normalizedCommit.Length -le 7) { return $normalizedCommit }
    return $normalizedCommit.Substring(0, 7)
}

function Get-CurrentAppSourceInfo {
    $result = [ordered]@{
        Commit          = ''
        SourceKind      = 'Unknown'
        HasLocalChanges = $false
    }

    if (Test-Path -LiteralPath $script:InstallMetaPath -PathType Leaf) {
        try {
            $installMeta = Read-JsonFile -Path $script:InstallMetaPath
            $commit = [string](Get-OptionalObjectPropertyValue -InputObject $installMeta -PropertyName 'github_commit' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($commit)) {
                $result.Commit = $commit.Trim()
                $result.SourceKind = 'Installed'
                return [pscustomobject]$result
            }
        }
        catch {}
    }

    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        try {
            $inside = (& git.exe -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
            if ($inside -eq 'true') {
                $commit = (& git.exe -C $PSScriptRoot rev-parse HEAD 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($commit)) {
                    $dirty = (& git.exe -C $PSScriptRoot status --porcelain 2>$null | Out-String).Trim()
                    $result.Commit = $commit
                    $result.SourceKind = 'Workspace'
                    $result.HasLocalChanges = (-not [string]::IsNullOrWhiteSpace($dirty))
                    return [pscustomobject]$result
                }
            }
        }
        catch {}
    }

    return [pscustomobject]$result
}

function Test-LocalGitCommitContainsRemoteCommit {
    param(
        [AllowEmptyString()][string]$RemoteCommit,
        [AllowEmptyString()][string]$LocalCommit
    )

    if (
        [string]::IsNullOrWhiteSpace($RemoteCommit) -or
        [string]::IsNullOrWhiteSpace($LocalCommit) -or
        -not (Get-Command git.exe -ErrorAction SilentlyContinue)
    ) {
        return $false
    }

    try {
        & git.exe -C $PSScriptRoot merge-base --is-ancestor $RemoteCommit $LocalCommit 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Read-UpdateStatusCache {
    param([switch]$AllowStale)

    if (-not (Test-Path -LiteralPath $script:UpdateStatusCachePath -PathType Leaf)) { return $null }

    try {
        $cache = Read-JsonFile -Path $script:UpdateStatusCachePath
        if (-not $AllowStale) {
            $checkedAtText = [string](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'CheckedAt' -DefaultValue '')
            $checkedAt = [datetime]::MinValue
            if ([string]::IsNullOrWhiteSpace($checkedAtText) -or -not [datetime]::TryParse($checkedAtText, [ref]$checkedAt)) {
                return $null
            }

            if (((Get-Date) - $checkedAt).TotalMinutes -gt $script:UpdateStatusCacheTtlMinutes) {
                return $null
            }
        }

        $cachedStatus = [string](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'Status' -DefaultValue '')
        if (-not $AllowStale -and $cachedStatus -eq 'UpToDate') {
            return $null
        }

        foreach ($requiredProperty in @('LocalCommit', 'LatestCommit', 'SourceKind')) {
            if ($null -eq $cache.PSObject.Properties[$requiredProperty]) {
                return $null
            }
        }

        $localCommit = [string](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'LocalCommit' -DefaultValue '')
        $latestCommit = [string](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'LatestCommit' -DefaultValue '')
        $sourceKind = [string](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'SourceKind' -DefaultValue 'Unknown')
        $hasLocalChanges = [bool](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'HasLocalChanges' -DefaultValue $false)
        $currentSourceInfo = Get-CurrentAppSourceInfo

        if ([string]$cache.LocalVersion -ne [string]$script:AppVersion) { return $null }
        if ([string]$currentSourceInfo.SourceKind -ne $sourceKind) { return $null }
        if ([bool]$currentSourceInfo.HasLocalChanges -ne $hasLocalChanges) { return $null }
        if (
            -not [string]::IsNullOrWhiteSpace([string]$currentSourceInfo.Commit) -and
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            [string]$currentSourceInfo.Commit -ne $localCommit
        ) {
            return $null
        }

        return (New-UpdateStatus `
            -LocalVersion ([string]$cache.LocalVersion) `
            -LatestVersion ([string]$cache.LatestVersion) `
            -LocalCommit $localCommit `
            -LatestCommit $latestCommit `
            -SourceKind $sourceKind `
            -HasLocalChanges $hasLocalChanges `
            -Repo ([string]$cache.Repo) `
            -Branch ([string]$cache.Branch) `
            -Status ([string]$cache.Status) `
            -Message ([string]$cache.Message) `
            -CheckedAt ([string]$cache.CheckedAt) `
            -Error ([string](Get-OptionalObjectPropertyValue -InputObject $cache -PropertyName 'Error' -DefaultValue '')))
    }
    catch {
        return $null
    }
}

function Write-UpdateStatusCache {
    param([Parameter(Mandatory)]$Status)

    try {
        Save-JsonFile -Path $script:UpdateStatusCachePath -InputObject $Status
    }
    catch {}
}

function Get-GitHubApiHeaders {
    $headers = @{
        'User-Agent' = "$($script:AppName)/$($script:AppVersion)"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
    }

    return $headers
}

function ConvertTo-GitHubRepoSlugFromRemoteUrl {
    param([AllowEmptyString()][string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return '' }

    $match = [regex]::Match($RemoteUrl.Trim(), 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/#?]+?)(?:\.git)?(?:[/#?].*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return '' }

    return ('{0}/{1}' -f $match.Groups['owner'].Value, $match.Groups['repo'].Value).ToLowerInvariant()
}

function Get-GitRemoteTarget {
    param([AllowEmptyString()][string]$Repo = $script:GitHubRepo)

    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        return ''
    }

    $expectedRepo = $Repo.Trim().ToLowerInvariant()
    try {
        $inside = (& git.exe -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
        if ($inside -eq 'true') {
            foreach ($remoteName in @(& git.exe -C $PSScriptRoot remote 2>$null)) {
                $name = [string]$remoteName
                if ([string]::IsNullOrWhiteSpace($name)) { continue }

                $remoteUrl = (& git.exe -C $PSScriptRoot remote get-url $name 2>$null | Out-String).Trim()
                if ((ConvertTo-GitHubRepoSlugFromRemoteUrl -RemoteUrl $remoteUrl) -eq $expectedRepo) {
                    return $name.Trim()
                }
            }
        }
    }
    catch {}

    return ("https://github.com/{0}.git" -f $Repo.Trim())
}

function Resolve-RemoteCommit {
    param(
        [AllowEmptyString()][string]$Repo = $script:GitHubRepo,
        [AllowEmptyString()][string]$Ref = ''
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Ref)) { return '' }

    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $commit = (& gh.exe api "repos/$Repo/commits/$Ref" --jq '.sha' 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($commit)) { return $commit }
        }
        catch {}
    }

    try {
        $commitInfo = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/commits/{1}" -f $Repo, $Ref) -Headers (Get-GitHubApiHeaders) -TimeoutSec 5 -ErrorAction Stop
        $commit = [string]$commitInfo.sha
        if (-not [string]::IsNullOrWhiteSpace($commit)) { return $commit }
    }
    catch {}

    $gitRemoteTarget = Get-GitRemoteTarget -Repo $Repo
    if (-not [string]::IsNullOrWhiteSpace($gitRemoteTarget) -and (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        foreach ($candidateRef in @("refs/heads/$Ref", $Ref)) {
            try {
                $remoteLine = (& git.exe -C $PSScriptRoot ls-remote $gitRemoteTarget $candidateRef 2>$null | Select-Object -First 1 | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($remoteLine)) {
                    $commit = ($remoteLine -split '\s+')[0]
                    if (-not [string]::IsNullOrWhiteSpace($commit)) { return $commit }
                }
            }
            catch {}
        }
    }

    return ''
}

function Get-RemoteAppMetadataFromGit {
    param(
        [AllowEmptyString()][string]$Repo = $script:GitHubRepo,
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$BranchCandidates,
        [Parameter(Mandatory)][string]$MetadataRelativePath
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        return $null
    }

    $gitRemoteTarget = Get-GitRemoteTarget -Repo $Repo
    if ([string]::IsNullOrWhiteSpace($gitRemoteTarget)) { return $null }

    foreach ($branch in $BranchCandidates) {
        $latestCommit = ''
        try {
            $remoteLine = (& git.exe -C $PSScriptRoot ls-remote $gitRemoteTarget "refs/heads/$branch" 2>$null | Select-Object -First 1 | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($remoteLine)) { continue }
            $latestCommit = ($remoteLine -split '\s+')[0]
        }
        catch {
            continue
        }

        $metadata = $null
        try {
            $inside = (& git.exe -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
            if ($inside -eq 'true') {
                $metadataJson = (& git.exe -C $PSScriptRoot show "$($latestCommit):$MetadataRelativePath" 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($metadataJson)) {
                    $metadata = $metadataJson | ConvertFrom-Json
                }
            }
        }
        catch {}

        if ($null -eq $metadata) {
            $tempRoot = Join-Path $env:TEMP ("TakeOwnership_update_metadata_{0}" -f [guid]::NewGuid().ToString('N'))
            try {
                & git.exe clone --quiet --depth 1 --branch $branch $gitRemoteTarget $tempRoot 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $metadataPath = Join-Path $tempRoot ($MetadataRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
                        $metadata = Read-JsonFile -Path $metadataPath
                    }
                }
            }
            catch {}
            finally {
                if (Test-Path -LiteralPath $tempRoot) {
                    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($null -eq $metadata) {
            $metadata = [pscustomobject]@{ version = '' }
        }

        return [pscustomobject]@{
            Repo          = $Repo
            Branch        = $branch
            DefaultBranch = ''
            Commit        = $latestCommit
            Metadata      = $metadata
        }
    }

    return $null
}

function Get-RemoteAppMetadata {
    param([AllowEmptyString()][string]$Repo = $script:GitHubRepo)

    if ([string]::IsNullOrWhiteSpace($Repo)) { return $null }

    $headers = Get-GitHubApiHeaders
    $defaultBranch = ''
    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $repoJson = (& gh.exe api "repos/$Repo" 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($repoJson)) {
                $repoInfo = $repoJson | ConvertFrom-Json
                $defaultBranch = [string]$repoInfo.default_branch
            }
        }
        catch {}
    }

    try {
        if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
            $repoInfo = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}" -f $Repo) -Headers $headers -TimeoutSec 5 -ErrorAction Stop
            $defaultBranch = [string]$repoInfo.default_branch
        }
    }
    catch {}

    $metadataRelativePath = ($script:MetadataPath.Substring($PSScriptRoot.Length).TrimStart('\')).Replace('\', '/')
    $branchCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($defaultBranch, 'master', 'main', 'latest')) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $branchCandidates.Contains($candidate)) {
            $branchCandidates.Add($candidate)
        }
    }

    foreach ($branch in $branchCandidates) {
        if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
            try {
                $contentJson = (& gh.exe api ("repos/{0}/contents/{1}?ref={2}" -f $Repo, $metadataRelativePath, $branch) 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($contentJson)) {
                    $contentInfo = $contentJson | ConvertFrom-Json
                    $encodedContent = [string]$contentInfo.content
                    if (-not [string]::IsNullOrWhiteSpace($encodedContent)) {
                        $decodedJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($encodedContent -replace '\s', '')))
                        return [pscustomobject]@{
                            Repo          = $Repo
                            Branch        = $branch
                            DefaultBranch = $defaultBranch
                            Commit        = (Resolve-RemoteCommit -Repo $Repo -Ref $branch)
                            Metadata      = ($decodedJson | ConvertFrom-Json)
                        }
                    }
                }
            }
            catch {}
        }

        try {
            $metadataUri = "https://raw.githubusercontent.com/{0}/{1}/{2}" -f $Repo, $branch, $metadataRelativePath
            $response = Invoke-WebRequest -Uri $metadataUri -Headers $headers -TimeoutSec 5 -ErrorAction Stop
            return [pscustomobject]@{
                Repo          = $Repo
                Branch        = $branch
                DefaultBranch = $defaultBranch
                Commit        = (Resolve-RemoteCommit -Repo $Repo -Ref $branch)
                Metadata      = ($response.Content | ConvertFrom-Json)
            }
        }
        catch {}
    }

    return (Get-RemoteAppMetadataFromGit -Repo $Repo -BranchCandidates $branchCandidates -MetadataRelativePath $metadataRelativePath)
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
        if ($null -ne $staleCachedStatus -and [string]$staleCachedStatus.Status -ne 'UpToDate') {
            $staleCachedStatus.Message = 'Using cached update status because the latest version could not be reached.'
            $script:UpdateStatus = $staleCachedStatus
            return $script:UpdateStatus
        }

        $script:UpdateStatus = New-UpdateStatus -LocalVersion $script:AppVersion -Repo $script:GitHubRepo -Status 'Error' -Message 'Could not reach GitHub to check the latest version.' -CheckedAt ((Get-Date).ToString('s'))
        return $script:UpdateStatus
    }

    $latestVersionProperty = $remoteInfo.Metadata.PSObject.Properties['version']
    $latestVersion = if ($null -ne $latestVersionProperty) { [string]$latestVersionProperty.Value } else { '' }
    $sourceInfo = Get-CurrentAppSourceInfo
    $localCommit = [string]$sourceInfo.Commit
    $latestCommit = [string]$remoteInfo.Commit
    $sourceKind = [string]$sourceInfo.SourceKind
    $hasLocalChanges = [bool]$sourceInfo.HasLocalChanges
    $localVersionObject = ConvertTo-AppVersion -VersionText $script:AppVersion
    $remoteVersionObject = ConvertTo-AppVersion -VersionText $latestVersion
    $statusName = 'Unknown'
    $statusMessage = 'Update status is unavailable.'

    if ($sourceKind -eq 'Workspace' -and $hasLocalChanges) {
        $statusName = 'WorkspaceModified'
        $statusMessage = "This workspace has unpublished local changes. Local metadata is v$($script:AppVersion) at HEAD $(Get-ShortGitCommitText -Commit $localCommit); latest published GitHub $($remoteInfo.Branch) is v$latestVersion at $(Get-ShortGitCommitText -Commit $latestCommit)."
    }
    elseif ($sourceKind -eq 'Workspace' -and $localCommit -ne $latestCommit -and (Test-LocalGitCommitContainsRemoteCommit -RemoteCommit $latestCommit -LocalCommit $localCommit)) {
        $statusName = 'LocalAhead'
        $statusMessage = "This workspace has local commits not yet published to GitHub $($remoteInfo.Branch). Latest published commit is $(Get-ShortGitCommitText -Commit $latestCommit); local HEAD is $(Get-ShortGitCommitText -Commit $localCommit)."
    }
    elseif ($null -ne $localVersionObject -and $null -ne $remoteVersionObject) {
        if ($localVersionObject -lt $remoteVersionObject) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion."
        }
        elseif ($localVersionObject -gt $remoteVersionObject) {
            $statusName = 'LocalAhead'
            $statusMessage = "Local version v$($script:AppVersion) is newer than the latest published GitHub $($remoteInfo.Branch) version v$latestVersion."
        }
        elseif (
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            -not [string]::IsNullOrWhiteSpace($latestCommit) -and
            $localCommit -ne $latestCommit
        ) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion has commit $(Get-ShortGitCommitText -Commit $latestCommit); local is $(Get-ShortGitCommitText -Commit $localCommit)."
        }
        else {
            $statusName = 'UpToDate'
            $commitLabel = Get-ShortGitCommitText -Commit $latestCommit
            $statusMessage = if ($commitLabel -eq '--') { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion." } else { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion ($commitLabel)." }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($latestVersion) -and $latestVersion -eq $script:AppVersion) {
        if (
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            -not [string]::IsNullOrWhiteSpace($latestCommit) -and
            $localCommit -ne $latestCommit
        ) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion has commit $(Get-ShortGitCommitText -Commit $latestCommit); local is $(Get-ShortGitCommitText -Commit $localCommit)."
        }
        else {
            $statusName = 'UpToDate'
            $commitLabel = Get-ShortGitCommitText -Commit $latestCommit
            $statusMessage = if ($commitLabel -eq '--') { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion." } else { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion ($commitLabel)." }
        }
    }

    $script:UpdateStatus = New-UpdateStatus `
        -LocalVersion $script:AppVersion `
        -LatestVersion $latestVersion `
        -LocalCommit $localCommit `
        -LatestCommit $latestCommit `
        -SourceKind $sourceKind `
        -HasLocalChanges $hasLocalChanges `
        -Repo ([string]$remoteInfo.Repo) `
        -Branch ([string]$remoteInfo.Branch) `
        -Status $statusName `
        -Message $statusMessage `
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
        'WorkspaceModified' { return 'Local changes present' }
        'Error' { return 'Update check failed' }
        default { return 'Status unavailable' }
    }
}

function Get-InstallerCoreUpdateState {
    $state = [ordered]@{
        IsAvailable       = $false
        InstallScriptPath = ''
        Mode              = 'Unavailable'
        InstallerMode     = 'GitHub'
        DefaultAction     = ''
        GitHubBranch      = ''
        LocalSourcePath   = ''
        StatusLine        = 'InstallerCore updater unavailable'
        Reason            = ''
    }

    $installScriptPath = Join-Path $PSScriptRoot 'Install.ps1'
    if (-not (Test-Path -LiteralPath $installScriptPath -PathType Leaf)) {
        $state.Reason = 'Install.ps1 not found beside the app script.'
        return [pscustomobject]$state
    }

    $state.IsAvailable = $true
    $state.InstallScriptPath = $installScriptPath

    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git')) {
        $state.Mode = 'Repo copy'
        $state.InstallerMode = 'Git fast-forward'
        $state.DefaultAction = 'GitFastForward'

        try {
            $state.GitHubBranch = (& git.exe -C $PSScriptRoot branch --show-current 2>$null | Out-String).Trim()
        }
        catch {}

        if ([string]::IsNullOrWhiteSpace($state.GitHubBranch)) {
            try {
                $branch = (& git.exe -C $PSScriptRoot rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
                if ($branch -ne 'HEAD') { $state.GitHubBranch = $branch }
            }
            catch {}
        }

        $branchLabel = if ([string]::IsNullOrWhiteSpace($state.GitHubBranch)) { 'auto' } else { $state.GitHubBranch }
        $state.StatusLine = "Repo copy - Git/$branchLabel"
        return [pscustomobject]$state
    }

    if (Test-Path -LiteralPath $script:InstallMetaPath -PathType Leaf) {
        $state.Mode = 'Installed copy'
        $state.InstallerMode = 'GitHub'
        $state.DefaultAction = 'UpdateGitHub'

        try {
            $meta = Read-JsonFile -Path $script:InstallMetaPath
            $packageSource = [string](Get-OptionalObjectPropertyValue -InputObject $meta -PropertyName 'package_source' -DefaultValue '')
            $sourcePath = [string](Get-OptionalObjectPropertyValue -InputObject $meta -PropertyName 'source_path' -DefaultValue '')
            $githubRef = [string](Get-OptionalObjectPropertyValue -InputObject $meta -PropertyName 'github_ref' -DefaultValue '')

            if ($packageSource -eq 'Local' -and -not [string]::IsNullOrWhiteSpace($sourcePath) -and -not ($sourcePath -like 'github://*')) {
                $state.InstallerMode = 'Local'
                $state.DefaultAction = 'Update'
                $state.LocalSourcePath = $sourcePath
            }
            else {
                $state.GitHubBranch = $githubRef
            }
        }
        catch {
            $state.Reason = 'install-meta.json could not be parsed; falling back to GitHub auto-detect.'
        }

        if ($state.InstallerMode -eq 'Local') {
            $state.StatusLine = 'Installed copy - Local'
        }
        else {
            $branchLabel = if ([string]::IsNullOrWhiteSpace($state.GitHubBranch)) { 'auto' } else { $state.GitHubBranch }
            $state.StatusLine = "Installed copy - GitHub/$branchLabel"
        }
        return [pscustomobject]$state
    }

    $state.Mode = 'Portable copy'
    $state.DefaultAction = 'DownloadLatest'
    $state.StatusLine = 'Portable copy - GitHub/auto'
    $state.Reason = 'No .git folder and no install-meta.json were found.'
    return [pscustomobject]$state
}

function Invoke-GitWorkingCopyUpdateProcess {
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [AllowEmptyString()][string]$Branch
    )

    $recentLines = [System.Collections.Generic.List[string]]::new()
    function Add-RecentLine {
        param([AllowEmptyString()][string]$Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return }
        [void]$recentLines.Add($Line)
        while ($recentLines.Count -gt 12) { $recentLines.RemoveAt(0) }
    }

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Add-RecentLine 'git.exe was not found in PATH.'
        return [pscustomobject]@{ ExitCode = 9001; RecentLines = @($recentLines) }
    }

    try {
        $inside = (& git.exe -C $WorkingDirectory rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim()
        if ($inside -ne 'true') {
            Add-RecentLine 'This folder is not a git working copy.'
            return [pscustomobject]@{ ExitCode = 9002; RecentLines = @($recentLines) }
        }

        $dirty = (& git.exe -C $WorkingDirectory status --porcelain 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($dirty)) {
            Add-RecentLine 'Working copy has local changes. Fast-forward update refused.'
            Add-RecentLine 'Commit, stash, or discard local changes before updating this repo copy.'
            return [pscustomobject]@{ ExitCode = 3; RecentLines = @($recentLines) }
        }

        if ([string]::IsNullOrWhiteSpace($Branch)) {
            $Branch = (& git.exe -C $WorkingDirectory branch --show-current 2>&1 | Out-String).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($Branch)) {
            Add-RecentLine 'Could not determine the current git branch.'
            return [pscustomobject]@{ ExitCode = 9003; RecentLines = @($recentLines) }
        }

        Add-RecentLine ("Fetching origin/{0}..." -f $Branch)
        $fetchText = (& git.exe -C $WorkingDirectory fetch --prune origin $Branch 2>&1 | Out-String).Trim()
        foreach ($line in ($fetchText -split "`r?`n")) { Add-RecentLine $line }
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; RecentLines = @($recentLines) }
        }

        $localHead = (& git.exe -C $WorkingDirectory rev-parse HEAD 2>&1 | Out-String).Trim()
        $remoteHead = (& git.exe -C $WorkingDirectory rev-parse "origin/$Branch" 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($localHead) -and $localHead -eq $remoteHead) {
            Add-RecentLine ("Already up to date with origin/{0}." -f $Branch)
            return [pscustomobject]@{ ExitCode = 0; RecentLines = @($recentLines) }
        }

        Add-RecentLine ("Fast-forwarding to origin/{0}..." -f $Branch)
        $mergeText = (& git.exe -C $WorkingDirectory merge --ff-only "origin/$Branch" 2>&1 | Out-String).Trim()
        foreach ($line in ($mergeText -split "`r?`n")) { Add-RecentLine $line }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; RecentLines = @($recentLines) }
    }
    catch {
        Add-RecentLine ("Git update failed: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{ ExitCode = 9999; RecentLines = @($recentLines) }
    }
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

    $sourceLabel = if ([bool]$script:UpdateStatus.HasLocalChanges) { "$($script:UpdateStatus.SourceKind) + local changes" } else { [string]$script:UpdateStatus.SourceKind }
    Write-UpdateSection -Title 'Update App'
    Write-Host "  $ResultMessage" -ForegroundColor $messageColor
    Write-Host ("  Status         : {0}" -f [string]$script:UpdateStatus.Status) -ForegroundColor DarkGray
    Write-Host ("  Current version: {0}" -f [string]$script:UpdateStatus.LocalVersion) -ForegroundColor DarkGray
    Write-Host ("  Latest version : {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$script:UpdateStatus.LatestVersion)) { '--' } else { [string]$script:UpdateStatus.LatestVersion })) -ForegroundColor DarkGray
    Write-Host ("  Current commit : {0}" -f (Get-ShortGitCommitText -Commit ([string]$script:UpdateStatus.LocalCommit))) -ForegroundColor DarkGray
    Write-Host ("  Latest commit  : {0}" -f (Get-ShortGitCommitText -Commit ([string]$script:UpdateStatus.LatestCommit))) -ForegroundColor DarkGray
    Write-Host ("  Source         : {0}" -f $sourceLabel) -ForegroundColor DarkGray

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
    $state = Get-InstallerCoreUpdateState
    if (-not $state.IsAvailable) {
        return [pscustomobject]@{ Success = $false; Message = $state.Reason }
    }

    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwshCommand -or -not (Test-Path -LiteralPath $pwshCommand.Source -PathType Leaf)) {
        return [pscustomobject]@{ Success = $false; Message = 'pwsh.exe was not found.' }
    }

    if ($state.DefaultAction -eq 'GitFastForward') {
        $progressMessage = 'Updating this git working copy with fetch + fast-forward...'
        Show-AppUpdateResultPanel -ResultMessage $progressMessage -Level 'Info' -RecentLines @("Branch: $($state.GitHubBranch)")
        $updateProcessResult = Invoke-GitWorkingCopyUpdateProcess -WorkingDirectory $PSScriptRoot -Branch $state.GitHubBranch
        $exitCode = [int]$updateProcessResult.ExitCode
        $finalLines = @($updateProcessResult.RecentLines)
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

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $state.InstallScriptPath,
        '-Action', $state.DefaultAction,
        '-Force'
    )

    if ($state.InstallerMode -eq 'Local' -and -not [string]::IsNullOrWhiteSpace($state.LocalSourcePath)) {
        $arguments += @('-PackageSource', 'Local', '-SourcePath', $state.LocalSourcePath)
    }
    elseif ($state.InstallerMode -eq 'GitHub' -and -not [string]::IsNullOrWhiteSpace($state.GitHubBranch)) {
        $arguments += @('-GitHubRef', $state.GitHubBranch)
    }

    if ($state.DefaultAction -eq 'DownloadLatest') {
        $arguments += '-NoSelfRelaunch'
    }
    if ($state.Mode -eq 'Installed copy') {
        $arguments += '-NoExplorerRestart'
    }

    $progressMessage = if ($state.DefaultAction -eq 'DownloadLatest') {
        'Updating this portable copy inside the current app session...'
    }
    elseif ($state.InstallerMode -eq 'Local') {
        'Updating from the recorded local source inside the current app session...'
    }
    else {
        'Updating from GitHub inside the current app session...'
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
        $state = Get-InstallerCoreUpdateState
        $sourceLabel = if ([bool]$script:UpdateStatus.HasLocalChanges) { "$($script:UpdateStatus.SourceKind) + local changes" } else { [string]$script:UpdateStatus.SourceKind }
        Write-Host "🔵 $script:AppName Update" -ForegroundColor Cyan
        Write-Host "------------------------------"
        Write-Host "Current version: $script:AppVersion" -ForegroundColor Gray
        Write-Host "Latest version : $(if ([string]::IsNullOrWhiteSpace([string]$script:UpdateStatus.LatestVersion)) { '--' } else { $script:UpdateStatus.LatestVersion })" -ForegroundColor Gray
        Write-Host "Current commit : $(Get-ShortGitCommitText -Commit ([string]$script:UpdateStatus.LocalCommit))" -ForegroundColor Gray
        Write-Host "Latest commit  : $(Get-ShortGitCommitText -Commit ([string]$script:UpdateStatus.LatestCommit))" -ForegroundColor Gray
        Write-Host "Source         : $sourceLabel" -ForegroundColor Gray
        Write-Host "Update        : $(Get-UpdateLabel)" -ForegroundColor Yellow
        Write-Host "Update path   : $($state.StatusLine)" -ForegroundColor DarkGray
        Write-Host "Repo / branch : $($script:UpdateStatus.Repo) / $(if ([string]::IsNullOrWhiteSpace([string]$script:UpdateStatus.Branch)) { '--' } else { $script:UpdateStatus.Branch })" -ForegroundColor DarkGray
        Write-Host "Last check    : $(if ([string]::IsNullOrWhiteSpace([string]$script:UpdateStatus.CheckedAt)) { '--' } else { ([string]$script:UpdateStatus.CheckedAt) -replace 'T', ' ' })" -ForegroundColor DarkGray
        Write-Host "Message       : $($script:UpdateStatus.Message)" -ForegroundColor DarkGray
        if ($state.DefaultAction -eq 'GitFastForward') {
            Write-Host "Repo copies update with git fetch + fast-forward only; dirty workspaces are refused." -ForegroundColor DarkGray
        }
        elseif ($state.DefaultAction -eq 'DownloadLatest') {
            Write-Host "Portable copies update with DownloadLatest -NoSelfRelaunch." -ForegroundColor DarkGray
        }
        elseif ($state.Mode -eq 'Installed copy') {
            Write-Host "Installed copies compare state\\install-meta.json github_commit against the remote commit." -ForegroundColor DarkGray
        }
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
