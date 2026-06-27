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

.EXAMPLE
    Invoke-Gitme -RepoName myproject -Verbose
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

    # Meta flags — these exit early without performing any repository operations
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
  -Verbose               Print DEBUG messages in addition to all other levels
  -Version               Show version and exit
  -Help                  Show this help and exit

Examples:
  gitme -RepoName myproject -Provider GitHub -CreateRemote -Token "tok"
  gitme -RepoName myproject -Provider GitLab -CreateRemote -Token "tok"
  gitme -RepoName myproject -Provider Local -RemotePath '\\server\share'
  gitme -RepoName myproject -Verbose
"@
        return
    }

    # Resolve path — create directory if it does not exist
    $target = Resolve-Path $Path -ErrorAction SilentlyContinue
    if (-not $target) {
        $target = (New-Item -ItemType Directory -Path $Path -Force).FullName
    }
    Push-Location $target

    try {
        # ── Log-level resolution ──────────────────────────────────────────────
        # -Verbose (standard PS switch) activates Debug level, which is a
        # superset of Info.  -VerboseOutput activates Info level only.
        # Neither switch leaves the level at Quiet.
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose') -and
            $PSCmdlet.MyInvocation.BoundParameters['Verbose'] -eq $true) {
            $script:GitMeLogLevel = 'Debug'
        }
        elseif ($VerboseOutput) {
            $script:GitMeLogLevel = 'Info'
        }
        else {
            $script:GitMeLogLevel = 'Quiet'
        }

        Write-GitMeLog -Level Debug -Message "GitMe $script:GitMeVersion starting."
        Write-GitMeLog -Level Debug -Message "Resolved target path: $target"
        Write-GitMeLog -Level Debug -Message "Parameters: RepoName='$RepoName' Provider='$Provider' CreateRemote=$CreateRemote AutoBump=$AutoBump Force=$Force"

        # Prerequisites
        Test-GitMePrerequisite

        # Identity fallback chain: explicit param > git config > environment
        $defaultName  = Get-GitMeConfig 'user.name'
        $defaultEmail = Get-GitMeConfig 'user.email'

        Write-GitMeLog -Level Debug -Message "Git global user.name='$defaultName' user.email='$defaultEmail'"

        $devName  = if ($UserName)  { $UserName }  elseif ($defaultName)  { $defaultName }  else { $env:USERNAME }
        $devEmail = if ($UserEmail) { $UserEmail } elseif ($defaultEmail) { $defaultEmail } else { '' }

        Write-GitMeLog -Level Debug -Message "Resolved identity: name='$devName' email='$devEmail'"

        # Version resolution — attempt to read from existing tags first
        $describeResult = Invoke-GitMeNative @('describe', '--tags', '--abbrev=0')

        Write-GitMeLog -Level Debug -Message "git describe exit=$($describeResult.ExitCode) output='$($describeResult.Output)'"

        $currentTag = if ($describeResult.ExitCode -eq 0 -and $describeResult.Output) {
            ($describeResult.Output -replace '^v', '').Trim()
        }
        else {
            '0.1.0'
        }

        Write-GitMeLog -Level Debug -Message "Current tag resolved to: '$currentTag'"

        if ($AutoBump) {
            $PackVersion = Get-GitMeVersionFromCommit -CurrentVersion $currentTag
            Write-GitMeLog -Level Info  -Message "Auto-bumped version: $PackVersion"
            Write-GitMeLog -Level Debug -Message "Version before bump: '$currentTag' — after: '$PackVersion'"
        }
        elseif (-not $PackVersion) {
            $PackVersion = $currentTag
            Write-GitMeLog -Level Debug -Message "PackVersion not supplied — using current tag: '$PackVersion'"
        }
        else {
            Write-GitMeLog -Level Debug -Message "PackVersion supplied explicitly: '$PackVersion'"
        }

        # ShouldProcess guard — provides -WhatIf and -Confirm support
        $operation = "Initialise Git repository '$RepoName' at $target with remote $Provider"
        if (-not $PSCmdlet.ShouldProcess($target, $operation)) { return }

        # Local setup via splatting
        $repoParams = @{
            DevName        = $devName
            DevEmail       = $devEmail
            SetLocalConfig = (-not $NoLocalConfig.IsPresent)
            Force          = $Force
        }

        Write-GitMeLog -Level Debug -Message "Calling Initialize-GitMeRepository with SetLocalConfig=$($repoParams.SetLocalConfig)"

        Initialize-GitMeRepository @repoParams

        $commitParams = @{
            RepoName    = $RepoName
            PackVersion = $PackVersion
            DevName     = $devName
            DevEmail    = $devEmail
        }

        Write-GitMeLog -Level Debug -Message "Calling New-GitMeInitialCommit for '$RepoName' v$PackVersion"

        New-GitMeInitialCommit @commitParams

        $tagParams = @{
            RepoName    = $RepoName
            PackVersion = $PackVersion
            DevName     = $devName
            DevEmail    = $devEmail
            Force       = $Force
        }

        Write-GitMeLog -Level Debug -Message "Calling New-GitMeVersionTag for v$PackVersion"

        New-GitMeVersionTag @tagParams

        # Remote creation — triggered by -CreateRemote or implicitly for Local provider
        $remoteInfo = $null
        if ($CreateRemote -or $Provider -eq 'Local') {
            Write-GitMeLog -Level Debug -Message "Remote creation requested — Provider='$Provider'"

            switch ($Provider) {
                'GitHub' {
                    if (-not $Token) { throw '-Token is required for GitHub remote creation.' }
                    $remoteParams = @{
                        Provider  = 'GitHub'
                        Owner     = $devName
                        Name      = $RepoName
                        Token     = $Token
                        IsPrivate = $Private.IsPresent
                    }
                    if ($ApiBaseUrl) {
                        $remoteParams['ApiBaseUrl'] = $ApiBaseUrl
                        Write-GitMeLog -Level Debug -Message "GitHub ApiBaseUrl override: '$ApiBaseUrl'"
                    }
                    $remoteInfo = New-RemoteRepository @remoteParams
                }
                'GitLab' {
                    if (-not $Token) { throw '-Token is required for GitLab remote creation.' }
                    $remoteParams = @{
                        Provider  = 'GitLab'
                        Owner     = $devName
                        Name      = $RepoName
                        Token     = $Token
                        IsPrivate = $Private.IsPresent
                    }
                    if ($ApiBaseUrl) {
                        $remoteParams['ApiBaseUrl'] = $ApiBaseUrl
                        Write-GitMeLog -Level Debug -Message "GitLab ApiBaseUrl override: '$ApiBaseUrl'"
                    }
                    $remoteInfo = New-RemoteRepository @remoteParams
                }
                'Local' {
                    if (-not $RemotePath) { throw '-RemotePath is required when Provider is Local.' }
                    $localParams = @{
                        RemotePath = $RemotePath
                        RepoName   = $RepoName
                    }
                    Write-GitMeLog -Level Debug -Message "Local bare repository path: '$RemotePath'"
                    $remoteInfo = New-LocalRepository @localParams
                }
            }

            Write-GitMeLog -Level Debug -Message "Remote info — CloneUrl='$($remoteInfo.CloneUrl)' Provider='$($remoteInfo.Provider)'"
        }
        else {
            Write-GitMeLog -Level Debug -Message "No remote creation requested — skipping API call."
        }

        # Push or display manual instructions
        if ($remoteInfo) {
            Write-GitMeLog -Level Debug -Message "Pushing to remote '$($remoteInfo.CloneUrl)'"
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

        Write-GitMeLog -Level Debug -Message "Invoke-Gitme completed successfully."
    }
    finally {
        Pop-Location
        Write-GitMeLog -Level Debug -Message "Working directory restored."
    }
}
