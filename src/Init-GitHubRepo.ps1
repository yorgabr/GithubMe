<#
.SYNOPSIS
Init-GitHubRepo automates the complete setup of a Git repository from local 
initialization to GitHub publication.

.DESCRIPTION
This script embodies a comprehensive, self-contained approach to repository creation. 
Rather than merely initializing a local Git repository, it orchestrates the entire 
lifecycle: establishing local version control, configuring developer identity, 
creating structured initial commits and version tags, generating release 
documentation, and optionally creating the remote repository on GitHub through 
authenticated API calls.

The implementation maintains compatibility across Windows PowerShell 5.1 and 
PowerShell Core 6/7+, gracefully handling platform differences in credential storage 
and API invocation. All operations are idempotent where possible, allowing repeated 
execution without destructive side effects.

.EXAMPLE
Init-GitHubRepo `
    -GithubUser "jdoe" `
    -GithubRepo "my-project" `
    -CreateRemote `
    -Token (Read-Host -AsSecureString "Token")

.NOTES
File Name      : Init-GitHubRepo.ps1
Author         : Yorga Babuscan (yorgabr@gmail.com)
Prerequisite   : PowerShell 5.1 or higher
Version        : 1.2.1
License        : GPL-3.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GithubUser,

    [Parameter(Mandatory=$false)]
    [string]$GithubRepo,

    [Parameter(Mandatory=$false)]
    [string]$DevName,

    [Parameter(Mandatory=$false)]
    [string]$DevEmail,

    [Parameter(Mandatory=$false)]
    [string]$PackVersion = "0.1.0",

    [Parameter(Mandatory=$false)]
    [switch]$CreateRemote,

    [Parameter(Mandatory=$false)]
    [switch]$Private,

    [Parameter(Mandatory=$false)]
    [object]$Token,

    [Parameter(Mandatory=$false)]
    [string]$ApiBaseUrl = "https://api.github.com",

    [Parameter(Mandatory=$false)]
    [switch]$SetLocalGitConfig,

    [Parameter(Mandatory=$false)]
    [switch]$NoSetLocalGitConfig,

    [Parameter(Mandatory=$false)]
    [switch]$VerboseOutput,

    [Parameter(Mandatory=$false)]
    [switch]$ForceTag,

    [Parameter(Mandatory=$false)]
    [switch]$Version,

    [Parameter(Mandatory=$false)]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SCRIPT_VERSION = "1.2.1"

#__________ Color helpers _________________________________________
$ESC = [char]27
$Cyan   = "${ESC}[36m"
$Yellow = "${ESC}[33m"
$Green  = "${ESC}[32m"
$Red    = "${ESC}[31m"
$Reset  = "${ESC}[0m"

function Out-Info { 
    param([string]$Message) 
    if ($VerboseOutput) { [Console]::Out.WriteLine("$Cyan[INFO]$Reset $Message") }
}

function Out-Warn { 
    param([string]$Message) 
    [Console]::Out.WriteLine("$Yellow[WARN]$Reset $Message") 
}

function Out-Success { 
    param([string]$Message) 
    if ($VerboseOutput) { [Console]::Out.WriteLine("$Green[SUCCESS]$Reset $Message") }
}

function Out-Error { 
    param([string]$Message) 
    [Console]::Error.WriteLine("$Red[ERROR]$Reset $Message") 
}

#__________ Git helpers _____________________________________________
function Get-GitConfig($Key) {
    try { 
        $v = git config $Key 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return $v }
    } catch {}
    return ""
}

$DEFAULT_GIT_NAME = Get-GitConfig "user.name"
$DEFAULT_GIT_EMAIL = Get-GitConfig "user.email"

#__________ Core functions __________________________________________
function Show-Version { 
    "$(Split-Path -Leaf $PSCommandPath) version $SCRIPT_VERSION" 
}

function Show-Usage {
    @"
Init-GitHubRepo.ps1 — Initialize a Git repository with proper tagging and release structure.

Usage: Init-GitHubRepo.ps1 -GithubUser <user> -GithubRepo <repo> [options]

Required: -GithubUser, -GithubRepo
Options:  -DevName, -DevEmail, -PackVersion (default: 0.1.0)
          -CreateRemote, -Private, -Token, -ApiBaseUrl
          -SetLocalGitConfig, -NoSetLocalGitConfig, -VerboseOutput, -ForceTag
          -Version, -Help

Examples:
    Init-GitHubRepo.ps1 -GithubUser jdoe -GithubRepo myproject
    Init-GitHubRepo.ps1 -GithubUser jdoe -GithubRepo myproject -CreateRemote -Token "`$token"
    Init-GitHubRepo.ps1 -GithubUser jdoe -GithubRepo myproject -PackVersion 2.0.0 -ForceTag
"@
}

function Initialize-Arguments {
    if ($Version) { Show-Version; exit 0 }
    if ($Help) { Show-Usage; exit 0 }
    if ($SetLocalGitConfig -and $NoSetLocalGitConfig) { 
        Out-Error "Cannot use both -SetLocalGitConfig and -NoSetLocalGitConfig"; exit 2 
    }
    if (-not $GithubUser) { Out-Error "Missing: -GithubUser"; Show-Usage; exit 2 }
    if (-not $GithubRepo) { Out-Error "Missing: -GithubRepo"; Show-Usage; exit 2 }
    if ($CreateRemote -and -not $Token) { 
        Out-Error "-CreateRemote requires -Token"; exit 2 
    }
    
    # Token handling
    $script:GITHUB_TOKEN = if ($Token -is [System.Security.SecureString]) {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        $plain
    } else { $Token }
    
    # Dev name fallback
    $script:DEV_NAME = if ($DevName) { $DevName } 
                      elseif ($DEFAULT_GIT_NAME) { Out-Info "Using git user.name: $DEFAULT_GIT_NAME"; $DEFAULT_GIT_NAME }
                      else { $GithubUser }
    
    # Dev email fallback
    $script:DEV_EMAIL = if ($DevEmail) { $DevEmail }
                        elseif ($DEFAULT_GIT_EMAIL) { Out-Info "Using git user.email: $DEFAULT_GIT_EMAIL"; $DEFAULT_GIT_EMAIL }
                        else { "" }
    
    $script:SET_LOCAL_GIT_CONFIG = if ($NoSetLocalGitConfig) { $false } else { $true }
}

function New-GitHubRepository($Owner, $Name, $Token, $IsPrivate, $ApiUrl) {
    $visibility = if ($IsPrivate) { "private" } else { "public" }
    Out-Info "Creating ${visibility} repository '$Name' on GitHub..."
    
    $uri = "$ApiUrl/user/repos"
    try {
        $user = Invoke-RestMethod -Uri "$ApiUrl/user" -Headers @{ Authorization = "Bearer $Token" }
        if ($Owner -ne $user.login) { $uri = "$ApiUrl/orgs/$Owner/repos" }
    } catch { Out-Warn "Could not verify user context, trying personal repo" }
    
    $body = @{ name = $Name; private = [bool]$IsPrivate; auto_init = $false; 
               description = "Repository created by Init-GitHubRepo.ps1" } | ConvertTo-Json
    
    $headers = @{ Authorization = "Bearer $Token"; Accept = "application/vnd.github.v3+json"; 
                  "Content-Type" = "application/json" }
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        Out-Success "Repository created at $($response.html_url)"
        return $response
    }
    catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        switch ($code) {
            422 { Out-Error "Repository '$Name' already exists or name is invalid" }
            401 { Out-Error "Authentication failed. Check your token has 'repo' scope" }
            403 { Out-Error "Permission denied. Token needs repository creation rights" }
            default { Out-Error "GitHub API error (${code}): $($_.Exception.Message)" }
        }
        throw
    }
}

function Initialize-GitRepository {
    if (-not (Test-Path ".git")) {
        Out-Info "Initializing git repository..."
        git init | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git init failed" }
        git checkout -b main 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { git checkout -b master 2>$null | Out-Null }
        Out-Success "Git repository initialized"
    } else {
        Out-Info "Git repository already exists"
    }
    
    if ($script:SET_LOCAL_GIT_CONFIG) {
        Out-Info "Setting local git config..."
        if ($script:DEV_NAME) { 
            git config --local user.name "$($script:DEV_NAME)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Out-Success "Set user.name: $($script:DEV_NAME)" }
        }
        if ($script:DEV_EMAIL) { 
            git config --local user.email "$($script:DEV_EMAIL)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Out-Success "Set user.email: $($script:DEV_EMAIL)" }
        }
        $localName = git config --local user.name 2>$null
        $localEmail = git config --local user.email 2>$null
        Out-Info "Local config: user.name=$localName, user.email=$localEmail"
    }
}

function New-InitialCommit {
    Out-Info "Adding files to git..."
    git add . 2>$null | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git add failed" }
    
    Out-Info "Creating initial commit..."
    $msg = "Initial commit: $GithubRepo`n`n- Project setup with proper structure`n- Version $PackVersion"
    if ($script:DEV_EMAIL) { $msg += "`n- Author: $($script:DEV_NAME) <$($script:DEV_EMAIL)>" }
    else { $msg += "`n- Author: $($script:DEV_NAME)" }
    
    git commit -m "$msg" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { 
        Out-Warn "Nothing to commit or commit failed (working tree clean)"
    } else {
        Out-Success "Initial commit created"
    }
}

function New-VersionTag {
    param([switch]$Force)
    
    Out-Info "Creating tag v$PackVersion..."
    
    # Check if tag exists
    $exists = git tag -l "v$PackVersion" 2>$null
    if ($exists) {
        if ($Force) {
            Out-Warn "Tag v$PackVersion exists, deleting..."
            git tag -d "v$PackVersion" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { Out-Warn "Could not delete existing tag"; return }
        } else {
            Out-Warn "Tag v$PackVersion already exists. Use -ForceTag to recreate."
            return
        }
    }
    
    $msg = "Release v$PackVersion`n`nInitial release of $GithubRepo."
    if ($script:DEV_EMAIL) { $msg += "`nAuthor: $($script:DEV_NAME) <$($script:DEV_EMAIL)>" }
    else { $msg += "`nAuthor: $($script:DEV_NAME)" }
    
    git tag -a "v$PackVersion" -m "$msg" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Out-Success "Tag v$PackVersion created" }
    else { Out-Warn "Failed to create tag v$PackVersion" }
}

function New-ReleaseNotes {
    Out-Info "Generating release notes..."
    $author = if ($script:DEV_EMAIL) { "$($script:DEV_NAME) ($($script:DEV_EMAIL))" } else { $script:DEV_NAME }
    @"
# Release v$PackVersion

## What's New
- First stable release of $GithubRepo
- Project initialized and configured

## Installation
Download appropriate package from the releases section.

## Documentation
See README.md and CONTRIBUTING.md.

Author: $author
"@ | Set-Content "RELEASE_NOTES.md"
    Out-Success "Release notes created"
}

function Add-GitRemote($RemoteUrl) {
    Out-Info "Adding remote origin..."
    git remote add origin $RemoteUrl 2>$null
    if ($LASTEXITCODE -ne 0) { git remote set-url origin $RemoteUrl 2>$null }
    
    $branch = git branch --show-current 2>$null; if (-not $branch) { $branch = "main" }
    
    Out-Info "Pushing to GitHub..."
    git push -u origin $branch 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Out-Success "Pushed branch '$branch'" } else { Out-Warn "Failed to push branch" }
    
    git push origin "v$PackVersion" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Out-Success "Pushed tag v$PackVersion" } else { Out-Warn "Failed to push tag" }
}

function Show-RemoteInstructions {
    [Console]::Out.WriteLine("")
    Out-Info "Manual GitHub connection:"
    Out-Info "  git remote add origin https://github.com/$GithubUser/$GithubRepo.git"
    Out-Info "  git push -u origin main"
    Out-Info "  git push origin v$PackVersion"
    [Console]::Out.WriteLine("")
    $currentName = git config user.name 2>$null
    $currentEmail = git config user.email 2>$null
    Out-Info "Git identity: $currentName <$currentEmail>"
}

#__________ Main execution __________________________________________
function Invoke-Main {
    Initialize-Arguments
    
    Out-Info "Running $(Split-Path -Leaf $PSCommandPath) v$SCRIPT_VERSION"
    Out-Info "Repository: $GithubRepo, User: $GithubUser"
    Out-Info "Developer: $script:DEV_NAME <$script:DEV_EMAIL>, Version: $PackVersion"
    
    Initialize-GitRepository
    New-InitialCommit
    New-VersionTag -Force:$ForceTag
    New-ReleaseNotes
    
    if ($CreateRemote) {
        try {
            $repo = New-GitHubRepository -Owner $GithubUser -Name $GithubRepo -Token $script:GITHUB_TOKEN `
                                         -IsPrivate $Private -ApiUrl $ApiBaseUrl
            Add-GitRemote -RemoteUrl $repo.clone_url
            Out-Success "=== Repository live on GitHub ==="
        }
        catch {
            Out-Warn "GitHub creation failed. Manual steps:"
            Show-RemoteInstructions
            exit 1
        }
    } else {
        Show-RemoteInstructions
        Out-Success "=== Local initialization complete ==="
    }
}

Invoke-Main