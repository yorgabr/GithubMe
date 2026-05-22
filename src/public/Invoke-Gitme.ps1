#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-Gitme initializes a Git repository, optionally creates a remote, and pushes it.

.DESCRIPTION
    Idempotent, convention-driven Git repository bootstrapper supporting GitHub, GitLab,
    and local/CIFS remotes. Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    Invoke-Gitme -UserName jdoe -RepoName myproject -Provider GitHub -VerboseOutput

.EXAMPLE
    Invoke-Gitme -Provider Local -RemotePath '\\nas\git' -RepoName myproject -Force
#>
function Invoke-Gitme {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Path = (Get-Location),
        [string]$RepoName = (Split-Path -Leaf (Get-Location)),

        [ValidateSet('GitHub', 'GitLab', 'Local')]
        [string]$Provider = 'GitHub',

        [string]$RemotePath,
        [string]$UserName,
        [string]$UserEmail,
        [string]$PackVersion,
        [switch]$Force,
        [switch]$CreateRemote,
        [switch]$Private,
        [string]$Token,
        [string]$ApiBaseUrl,
        [switch]$NoLocalConfig,
        [switch]$Version,
        [switch]$Help,
        [switch]$VerboseOutput,
        [switch]$AutoBump
    )

    # Meta flags
    if ($Version) {
        "GitMe version $script:GitMeVersion"
        return
    }

    if ($Help) {
        @"
Invoke-Gitme -- Initialize a Git repository with tagging and remote publishing.

Usage:
  Invoke-Gitme -RepoName <n> [options]
  gitme        -RepoName <n> [options]

Required:
  -RepoName              Repository name (default: current folder name)

Identity (optional):
  -UserName              Committer name (default: git config user.name)
  -UserEmail             Committer email (default: git config user.email)

Remote:
  -Provider              GitHub | GitLab | Local  (default: GitHub)
  -CreateRemote          Create the remote repository via API (GitHub/GitLab)
  -Private               Make the remote repository private
  -Token                 API token (GitHub PAT or GitLab token)
  -ApiBaseUrl            Override API endpoint (e.g. GitHub Enterprise)
  -RemotePath            UNC or local path when Provider = Local

Versioning:
  -PackVersion           SemVer string for tag (default: 0.1.0 or auto-detected)
  -AutoBump              Derive next SemVer from Conventional Commits
  -Force                 Recreate tag if it exists; re-init if needed

Config:
  -NoLocalConfig         Do not write local git user.name / user.email
  -VerboseOutput         Print INFO and SUCCESS messages
  -Version               Show version and exit
  -Help                  Show this help and exit

Examples:
  gitme -RepoName myproject -Provider GitHub -CreateRemote -Token "tok"
  gitme -RepoName myproject -Provider GitLab -CreateRemote -Token "tok"
  gitme -RepoName myproject -Provider Local -RemotePath '\\server\share'
"@
        return
    }

    # Resolve path
    $target = Resolve-Path $Path -ErrorAction SilentlyContinue
    if (-not $target) {
        $target = (New-Item -ItemType Directory -Path $Path -Force).FullName
    }
    Push-Location $target

    try {
        $script:GitMeLogLevel = if ($VerboseOutput) { 'Info' } else { 'Quiet' }

        # Prerequisites
        Test-GitMePrerequisite

        # Identity fallback
        $defaultName = Get-GitMeConfig 'user.name'
        $defaultEmail = Get-GitMeConfig 'user.email'
        $devName = if ($UserName) { $UserName }  elseif ($defaultName) { $defaultName }  else { $env:USERNAME }
        $devEmail = if ($UserEmail) { $UserEmail } elseif ($defaultEmail) { $defaultEmail } else { '' }

        # Version resolution
        $currentTag = (Invoke-GitMeNative @('describe', '--tags', '--abbrev=0')).Output
        $currentTag = if ($currentTag) { $currentTag -replace '^v', '' } else { '0.1.0' }

        if ($AutoBump) {
            $PackVersion = Get-GitMeVersionFromCommit -CurrentVersion $currentTag
            Write-GitMeLog -Level Info -Message "Auto-bumped version: $PackVersion"
        }
        elseif (-not $PackVersion) {
            $PackVersion = $currentTag
        }

        # ShouldProcess guard
        $operation = "Initialise Git repository '$RepoName' at $target with remote $Provider"
        if (-not $PSCmdlet.ShouldProcess($target, $operation)) { return }

        # Local setup via Splatting
        $repoParams = @{
            DevName        = $devName
            DevEmail       = $devEmail
            SetLocalConfig = (-not $NoLocalConfig.IsPresent)
            Force          = $Force
        }
        Initialize-GitMeRepository @repoParams

        $commitParams = @{
            RepoName    = $RepoName
            PackVersion = $PackVersion
            DevName     = $devName
            DevEmail    = $devEmail
        }
        New-GitMeInitialCommit @commitParams

        $tagParams = @{
            RepoName    = $RepoName
            PackVersion = $PackVersion
            DevName     = $devName
            DevEmail    = $devEmail
            Force       = $Force
        }
        New-GitMeVersionTag @tagParams

        # Remote creation
        $remoteInfo = $null
        if ($CreateRemote -or $Provider -eq 'Local') {
            switch ($Provider) {
                'GitHub' {
                    if (-not $Token) { throw '-Token is required for GitHub remote creation.' }
                    $remoteParams = @{
                        Provider   = 'GitHub'
                        Owner      = $devName
                        Name       = $RepoName
                        Token      = $Token
                        IsPrivate  = $Private.IsPresent
                        ApiBaseUrl = $ApiBaseUrl
                    }
                    $remoteInfo = New-RemoteRepository @remoteParams
                }
                'GitLab' {
                    if (-not $Token) { throw '-Token is required for GitLab remote creation.' }
                    $remoteParams = @{
                        Provider   = 'GitLab'
                        Owner      = $devName
                        Name       = $RepoName
                        Token      = $Token
                        IsPrivate  = $Private.IsPresent
                        ApiBaseUrl = $ApiBaseUrl
                    }
                    $remoteInfo = New-RemoteRepository @remoteParams
                }
                'Local' {
                    if (-not $RemotePath) { throw '-RemotePath is required when Provider is Local.' }
                    $localParams = @{
                        RemotePath = $RemotePath
                        RepoName   = $RepoName
                    }
                    $remoteInfo = New-LocalRepository @localParams
                }
            }
        }

        # Push or manual instructions
        if ($remoteInfo) {
            Add-GitMeRemote -RemoteUrl $remoteInfo.CloneUrl -PackVersion $PackVersion
            Write-GitMeLog -Level Success -Message '=== Repository is live ==='
        }
        else {
            $instructionParams = @{
                Provider    = $Provider
                User        = $devName
                Repo        = $RepoName
                PackVersion = $PackVersion
                RemoteUrl   = $RemotePath
            }
            Show-GitMeInstruction @instructionParams

            Write-GitMeLog -Level Success -Message '=== Local initialization complete ==='
        }
    }
    finally {
        Pop-Location
    }
}