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

    The script operates with sensible defaults that respect your existing Git 
    configuration while allowing complete override through parameters. It creates 
    professional-grade repository structure with proper semantic versioning tags, release 
    notes, and clear next-step instructions. When GitHub integration is requested, it 
    handles authentication token management securely and creates either public or private 
    repositories according to your specification.

    The implementation maintains compatibility across Windows PowerShell 5.1 and 
    PowerShell Core 6/7+, gracefully handling platform differences in credential storage 
    and API invocation. All operations are idempotent where possible, allowing repeated 
    execution without destructive side effects.

    By default, the script sets repository-specific Git identity (user.name and 
    user.email) locally, preserving your global Git configuration for other projects. 
    This supports maintaining different personas across personal, professional, and 
    open-source contexts.

.EXAMPLE
    Init-GitHubRepo -GithubUser "jdoe" -GithubRepo "my-project"
    
    Basic usage with local-only initialization. Creates the repository structure and 
    prepares it for manual GitHub connection via the displayed instructions.

.EXAMPLE
    Init-GitHubRepo -GithubUser "acme-corp" -GithubRepo "internal-tool" `
                    -DevName "Jane Developer" -DevEmail "jane@acme.com" `
                    -PackVersion "1.0.0" -CreateRemote -Private
    
    Full specification for a corporate project. Creates a private repository on GitHub 
    under the organization account, with specific developer identity and initial version 
    1.0.0.

.EXAMPLE
    Init-GitHubRepo -GithubUser "opensourcehero" -GithubRepo "public-good" `
                    -CreateRemote -Token (Read-Host -AsSecureString "GitHub Token")
    
    Creates a public repository on GitHub using a securely entered token, demonstrating 
    safe credential handling practices.

.NOTES
    All user-facing messages and logs are emitted in English to maintain consistency 
    across international environments and facilitate troubleshooting in heterogeneous 
    teams. Internal documentation and comments follow the same convention, ensuring the 
    codebase remains accessible to contributors regardless of their locale.

    File Name      : Init-GitHubRepo.ps1
    Author         : Yorga Babuscan (yorgabr@gmail.com)
    Prerequisites  : Git must be installed and available; PowerShell 5.1 or higher
    Version        : 1.2.0
    License        : GPL-3.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="GitHub username or organization name")]
    [string]$GithubUser,

    [Parameter(Mandatory=$false, HelpMessage="Repository name")]
    [string]$GithubRepo,

    [Parameter(Mandatory=$false, HelpMessage="Developer full name for Git commits")]
    [string]$DevName,

    [Parameter(Mandatory=$false, HelpMessage="Developer email for Git commits")]
    [string]$DevEmail,

    [Parameter(Mandatory=$false, HelpMessage="Initial semantic version")]
    [string]$PackVersion = "0.1.0",

    [Parameter(Mandatory=$false, HelpMessage="Create the repository on GitHub")]
    [switch]$CreateRemote,

    [Parameter(Mandatory=$false, HelpMessage="Make the GitHub repository private")]
    [switch]$Private,

    [Parameter(Mandatory=$false, HelpMessage="GitHub personal access token (secure string or plain text)")]
    [object]$Token,

    [Parameter(Mandatory=$false, HelpMessage="GitHub API base URL (for GitHub Enterprise)")]
    [string]$ApiBaseUrl = "https://api.github.com",

    [Parameter(Mandatory=$false, HelpMessage="Force local Git config setting")]
    [switch]$SetLocalGitConfig,

    [Parameter(Mandatory=$false, HelpMessage="Use global Git config instead of local")]
    [switch]$NoSetLocalGitConfig,

    [Parameter(Mandatory=$false, HelpMessage="Enable detailed step logging")]
    [switch]$VerboseOutput,

    [Parameter(Mandatory=$false, HelpMessage="Show script version")]
    [switch]$Version,

    [Parameter(Mandatory=$false, HelpMessage="Show detailed help")]
    [switch]$Help,

    [Parameter(Mandatory=$false, HelpMessage="Install argument completion")]
    [ValidateSet("TEMP", "USER", "SYSTEM")]
    [string]$GenerateCompletion
)

# Version detection and compatibility setup
$script:IsWindowsPowerShell = $PSVersionTable.PSEdition -eq 'Desktop' -or $PSVersionTable.PSVersion.Major -le 5

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#__________ Script metadata and state _____________________________________________________________
$SCRIPT_VERSION = "1.2.0"

# Script-scoped state variables
$script:GITHUB_USER = ""
$script:GITHUB_REPO = ""
$script:DEFAULT_GIT_NAME = ""
$script:DEFAULT_GIT_EMAIL = ""
$script:DEV_NAME = ""
$script:DEV_EMAIL = ""
$script:PACK_VERSION = "0.1.0"
$script:VERBOSE = $false
$script:SET_LOCAL_GIT_CONFIG = $true
$script:REMOTE_CREATED = $false
$script:REMOTE_URL = ""

#__________ Color helpers for rich console output _________________________________________________
# PowerShell 5.1 compatibility: use [char]27 instead of `e
$ESC = [char]27
$Cyan   = "${ESC}[36m"
$Yellow = "${ESC}[33m"
$Green  = "${ESC}[32m"
$Red    = "${ESC}[31m"
$Reset  = "${ESC}[0m"

function Out-Info { 
    param([string]$Message) 
    if ($script:VERBOSE) { 
        [Console]::Out.WriteLine("$Cyan[INFO]$Reset $Message") 
    } 
}

function Out-Warn { 
    param([string]$Message) 
    [Console]::Out.WriteLine("$Yellow[WARN]$Reset $Message") 
}

function Out-Success { 
    param([string]$Message) 
    if ($script:VERBOSE) { 
        [Console]::Out.WriteLine("$Green[SUCCESS]$Reset $Message") 
    } 
}

function Out-Error { 
    param([string]$Message) 
    [Console]::Error.WriteLine("$Red[ERROR]$Reset $Message") 
}

#__________ Git configuration helpers _____________________________________________________________
function Get-GitConfig {
    <#
    .SYNOPSIS
        Retrieves a value from Git configuration.
    
    .DESCRIPTION
        Queries the Git configuration system for a specific key. Returns empty string
        if the key is not set or if Git is not available. This function operates
        defensively, ensuring that missing Git configurations do not halt execution.
    #>
    param([string]$Key)
    try {
        $value = git config $Key 2>$null
        if ($LASTEXITCODE -eq 0 -and $value) {
            return $value
        }
    } catch {
        # Silently handle Git not being installed
    }
    return ""
}

# Initialize default values from existing Git configuration
$script:DEFAULT_GIT_NAME = Get-GitConfig "user.name"
$script:DEFAULT_GIT_EMAIL = Get-GitConfig "user.email"

#__________ Utility functions _____________________________________________________________________
function Get-ScriptName {
    <#
    .SYNOPSIS
        Returns the name of the currently executing script.
    #>
    return Split-Path -Leaf $PSCommandPath
}

function Show-Version {
    <#
    .SYNOPSIS
        Displays the script version.
    #>
    $name = Get-ScriptName
    [Console]::Out.WriteLine("$name version $SCRIPT_VERSION")
}

function Show-Usage {
    <#
    .SYNOPSIS
        Displays comprehensive usage help.
    #>
    @"
Init-GitHubRepo.ps1 — Initialize a Git repository with proper tagging and release structure.

Usage:
    Init-GitHubRepo.ps1 -GithubUser <username> -GithubRepo <name> [options]

Required Arguments:
    -GithubUser USERNAME      GitHub username or organization for remote URL.
    -GithubRepo NAME          Repository name.

Options:
    -Version                  Show script semantic version and exit.
    -Help, -h, -?             Show this help and exit.
    -DevName NAME             Developer's full name (default: -GithubUser value,
                              or git config user.name if set).
    -DevEmail EMAIL           Developer's e-mail (default: git config user.email
                              if set, otherwise empty).
    -PackVersion SEMVER       Package version for tag (default: 0.1.0).
    -CreateRemote             Create the repository on GitHub via API.
    -Private                  Make the GitHub repository private (default: public).
    -Token TOKEN              GitHub personal access token (required for -CreateRemote).
                              Accepts SecureString or plain text (SecureString recommended).
    -ApiBaseUrl URL           GitHub Enterprise API URL (default: https://api.github.com).
    -SetLocalGitConfig        Set user.name and user.email in local git config
                              for this repository only (default: true).
    -NoSetLocalGitConfig      Disable setting local git config (use global).
    -VerboseOutput            Echo each step.
    -GenerateCompletion SCOPE
                              Generate and install PowerShell argument completer.
                              SCOPE can be: TEMP, USER, or SYSTEM.

Examples:
    # Basic local initialization
    Init-GitHubRepo.ps1 -GithubUser john -GithubRepo myproject

    # Create public repository on GitHub
    Init-GitHubRepo.ps1 -GithubUser john -GithubRepo myproject -CreateRemote -Token "`$token"

    # Create private repository with full specification
    Init-GitHubRepo.ps1 -GithubUser acme-corp -GithubRepo internal-tool `
        -DevName "Jane Doe" -DevEmail "jane@acme.com" `
        -PackVersion 1.0.0 -CreateRemote -Private -Token "`$token"

    # Generate and install autocomplete for current user
    Init-GitHubRepo.ps1 -GenerateCompletion USER

Author: Yorga Babuscan (yorgabr@gmail.com)
"@
}

#__________ Argument processing ___________________________________________________________________
function Initialize-Arguments {
    <#
    .SYNOPSIS
        Processes and validates all script arguments.
    
    .DESCRIPTION
        This function orchestrates the configuration phase, handling special flags like -Version
        and -Help first, then validating that required parameters are present. It establishes
        sensible defaults for developer identity by interrogating Git configuration and falling
        back to the GitHub username when necessary.
        
        When GitHub repository creation is requested, it validates that authentication
        credentials are provided and converts SecureString tokens to plain text for API
        usage while minimizing exposure time.
    #>
    # Handle completion generation first (standalone operation)
    if ($GenerateCompletion) {
        Install-Completion -Scope $GenerateCompletion
        exit 0
    }

    # Handle version display
    if ($Version) {
        Show-Version
        exit 0
    }

    # Handle help display
    if ($Help) {
        Show-Usage
        exit 0
    }

    # Set verbose flag
    $script:VERBOSE = $VerboseOutput.IsPresent

    # Validate conflicting git config flags
    if ($SetLocalGitConfig -and $NoSetLocalGitConfig) {
        Out-Error "Cannot use both -SetLocalGitConfig and -NoSetLocalGitConfig"
        exit 2
    }
    
    if ($NoSetLocalGitConfig) {
        $script:SET_LOCAL_GIT_CONFIG = $false
    }

    # Validate required parameters
    if (-not $GithubUser) {
        Out-Error "Missing required argument: -GithubUser"
        Show-Usage
        exit 2
    }

    if (-not $GithubRepo) {
        Out-Error "Missing required argument: -GithubRepo"
        Show-Usage
        exit 2
    }

    # Store required values
    $script:GITHUB_USER = $GithubUser
    $script:GITHUB_REPO = $GithubRepo

    # Validate GitHub creation requirements
    if ($CreateRemote -and -not $Token) {
        Out-Error "-CreateRemote requires -Token parameter for GitHub authentication"
        exit 2
    }

    # Convert token to secure string if provided as plain text, or decrypt if SecureString
    if ($Token) {
        if ($Token -is [System.Security.SecureString]) {
            # PowerShell 5.1 compatible SecureString conversion
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
            $script:GITHUB_TOKEN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } else {
            $script:GITHUB_TOKEN = $Token
        }
    }

    # Determine developer name with cascading fallback
    if ($DevName) {
        $script:DEV_NAME = $DevName
    } else {
        if ($script:DEFAULT_GIT_NAME) {
            $script:DEV_NAME = $script:DEFAULT_GIT_NAME
            Out-Info "Using git config user.name for dev-name: $($script:DEV_NAME)"
        } else {
            $script:DEV_NAME = $script:GITHUB_USER
            Out-Info "Using github-user for dev-name: $($script:DEV_NAME)"
        }
    }

    # Determine developer email with optional fallback
    if ($DevEmail) {
        $script:DEV_EMAIL = $DevEmail
    } else {
        if ($script:DEFAULT_GIT_EMAIL) {
            $script:DEV_EMAIL = $script:DEFAULT_GIT_EMAIL
            Out-Info "Using git config user.email for dev-email: $($script:DEV_EMAIL)"
        } else {
            $script:DEV_EMAIL = ""
            Out-Info "No dev-email provided and no git config user.email set. Leaving empty."
        }
    }

    # Store package version
    if ($PackVersion) {
        $script:PACK_VERSION = $PackVersion
    }
}

#__________ PowerShell completion infrastructure _________________________________________________
function Get-CompletionScript {
    <#
    .SYNOPSIS
        Generates the PowerShell argument completer script block.
    #>
    @'
# Init-GitHubRepo.ps1 argument completer
# Generated automatically - do not edit manually

$initRepoParams = @(
    'GithubUser'
    'GithubRepo'
    'DevName'
    'DevEmail'
    'PackVersion'
    'CreateRemote'
    'Private'
    'Token'
    'ApiBaseUrl'
    'SetLocalGitConfig'
    'NoSetLocalGitConfig'
    'VerboseOutput'
    'Version'
    'Help'
    'GenerateCompletion'
)

$generateCompletionValues = @('TEMP', 'USER', 'SYSTEM')

$script:initRepoCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    switch ($parameterName) {
        'GenerateCompletion' {
            return $generateCompletionValues | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        default {
            return $null
        }
    }
}

Register-ArgumentCompleter -CommandName Init-GitHubRepo.ps1 -ParameterName GenerateCompletion -ScriptBlock $script:initRepoCompleter
'@
}

function Install-Completion {
    <#
    .SYNOPSIS
        Installs PowerShell argument completion.
    
    .DESCRIPTION
        Configures tab completion for this script's parameters. The TEMP scope is useful for
        trying out the completion or in automation scenarios. USER scope modifies your personal
        PowerShell profile for persistence across sessions. SYSTEM scope requires administrator
        rights and makes completion available to all users.
    #>
    param([string]$Scope)

    switch ($Scope) {
        'TEMP' {
            Out-Info "Installing PowerShell completion for current session (TEMP)..."
            Invoke-Expression (Get-CompletionScript)
            Out-Success "PowerShell completion activated for current session."
        }
        'USER' {
            Out-Info "Installing PowerShell completion for user (USER)..."
            
            $profileDir = Split-Path -Parent $PROFILE
            if (-not (Test-Path -LiteralPath $profileDir)) {
                Out-Info "Creating directory: $profileDir"
                $null = New-Item -ItemType Directory -Path $profileDir -Force
            }

            $completionScript = Get-CompletionScript
            $completionBlock = "`n# Init-GitHubRepo.ps1 completion`n$completionScript`n"
            
            if (Test-Path -LiteralPath $PROFILE) {
                Add-Content -Path $PROFILE -Value $completionBlock
            } else {
                Set-Content -Path $PROFILE -Value $completionBlock
            }
            
            Out-Success "PowerShell completion installed to profile: $PROFILE"
            Out-Info "To activate immediately, run: . `$PROFILE"
            Out-Info "Or restart your PowerShell session."
        }
        'SYSTEM' {
            Out-Info "Installing PowerShell completion system-wide (SYSTEM)..."
            
            # Determine if we have administrator privileges (PowerShell 5.1 compatible)
            $isAdmin = $false
            try {
                $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            } catch {
                # Non-Windows or error in detection
                $isAdmin = $false
            }

            if (-not $isAdmin) {
                Out-Error "System-wide installation requires administrator privileges."
                Out-Info "Please run PowerShell as Administrator."
                exit 1
            }

            # Determine the all-users profile location (PowerShell 5.1 compatible)
            if ($PSVersionTable.PSEdition -eq 'Core') {
                if ($IsWindows -or -not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
                    $allUsersProfile = "$env:ProgramFiles\PowerShell\7\profile.ps1"
                } else {
                    $allUsersProfile = "/usr/local/share/powershell/profile.ps1"
                }
            } else {
                $allUsersProfile = "$env:WINDIR\System32\WindowsPowerShell\v1.0\profile.ps1"
            }

            $completionScript = Get-CompletionScript
            $completionBlock = "`n# Init-GitHubRepo.ps1 completion`n$completionScript`n"
            
            $profileDir = Split-Path -Parent $allUsersProfile
            if (-not (Test-Path -LiteralPath $profileDir)) {
                $null = New-Item -ItemType Directory -Path $profileDir -Force
            }

            if (Test-Path -LiteralPath $allUsersProfile) {
                Add-Content -Path $allUsersProfile -Value $completionBlock
            } else {
                Set-Content -Path $allUsersProfile -Value $completionBlock
            }
            
            Out-Success "PowerShell completion installed to: $allUsersProfile"
            Out-Info "All users will have completion available in new PowerShell sessions."
        }
    }
}

#__________ GitHub API integration ________________________________________________________________
function New-GitHubRepository {
    <#
    .SYNOPSIS
        Creates a new repository on GitHub using the REST API.
    
    .DESCRIPTION
        This function encapsulates the GitHub repository creation logic, handling both public
        and private repositories. It constructs the appropriate API payload, manages authentication
        via Bearer token, and interprets response codes to provide meaningful feedback.
        
        The function respects the ApiBaseUrl parameter to support GitHub Enterprise installations,
        defaulting to the public GitHub API endpoint. Upon successful creation, it extracts the
        repository's clone URL and HTML URL for subsequent use.
    #>
    param(
        [string]$Owner,
        [string]$Name,
        [string]$Token,
        [bool]$IsPrivate = $false,
        [string]$ApiUrl = "https://api.github.com"
    )

    # PowerShell 5.1 compatible conditional string construction
    $visibility = "public"
    if ($IsPrivate) {
        $visibility = "private"
    }
    Out-Info "Creating ${visibility} repository '$Name' on GitHub..."
    
    $uri = "$ApiUrl/user/repos"
    
    # Check if creating for organization (PowerShell 5.1 compatible)
    try {
        $userResponse = Invoke-RestMethod -Uri "$ApiUrl/user" -Headers @{ Authorization = "Bearer $Token" }
        if ($Owner -ne $userResponse.login) {
            $uri = "$ApiUrl/orgs/$Owner/repos"
        }
    } catch {
        # If user check fails, assume personal repo
        Out-Warn "Could not verify user context, attempting personal repository creation"
    }

    $body = @{
        name = $Name
        private = $IsPrivate
        auto_init = $false  # We'll push our own initialization
        description = "Repository created by Init-GitHubRepo.ps1"
    } | ConvertTo-Json

    $headers = @{
        Authorization = "Bearer $Token"
        Accept = "application/vnd.github.v3+json"
        "Content-Type" = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        
        $script:REMOTE_CREATED = $true
        $script:REMOTE_URL = $response.clone_url
        
        Out-Success "Repository created successfully at $($response.html_url)"
        return $response
    }
    catch {
        # PowerShell 5.1 compatible error handling
        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        
        if ($statusCode -eq 422) {
            Out-Error "Repository '$Name' already exists under '$Owner' or name is invalid."
        } elseif ($statusCode -eq 401) {
            Out-Error "Authentication failed. Please verify your GitHub token has 'repo' scope."
        } elseif ($statusCode -eq 403) {
            Out-Error "Permission denied. Ensure your token has repository creation rights."
        } else {
            Out-Error "GitHub API error (${statusCode}): $($_.Exception.Message)"
        }
        throw
    }
}

#__________ Git operations ________________________________________________________________________
function Initialize-GitRepository {
    <#
    .SYNOPSIS
        Creates and configures the local Git repository.
    
    .DESCRIPTION
        Initializes a new Git repository if one doesn't exist, establishing the main branch
        (with fallback to master for compatibility). When local configuration is enabled,
        it sets repository-specific user identity, supporting multiple personas across
        different projects without polluting global Git configuration.
    #>
    if (-not (Test-Path -LiteralPath ".git")) {
        Out-Info "Initializing git repository..."
        
        git init | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Out-Error "Failed to initialize git repository."
            exit 1
        }
        
        # Try 'main' first (modern default), fall back to 'master' if needed
        git checkout -b main 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            git checkout -b master 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Out-Error "Failed to create main/master branch."
                exit 1
            }
        }
        
        Out-Success "Git repository initialized."
    } else {
        Out-Info "Git repository already exists."
    }

    # Apply local Git configuration if requested
    if ($script:SET_LOCAL_GIT_CONFIG) {
        Out-Info "Setting local git config for this repository..."
        
        if ($script:DEV_NAME) {
            git config --local user.name "$($script:DEV_NAME)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Out-Success "Set local user.name: $($script:DEV_NAME)"
            } else {
                Out-Warn "Failed to set local user.name"
            }
        }
        
        if ($script:DEV_EMAIL) {
            git config --local user.email "$($script:DEV_EMAIL)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Out-Success "Set local user.email: $($script:DEV_EMAIL)"
            } else {
                Out-Warn "Failed to set local user.email"
            }
        }
        
        # Display current configuration for verification
        $localName = git config --local user.name 2>$null
        $localEmail = git config --local user.email 2>$null
        Out-Info "Local git config for this repository:"
        Out-Info "  user.name:  $(if ($localName) { $localName } else { '(not set)' })"
        Out-Info "  user.email: $(if ($localEmail) { $localEmail } else { '(not set)' })"
    } else {
        Out-Info "Using global git config (local config not set)"
        if ($script:DEV_NAME) {
            git config user.name "$($script:DEV_NAME)" 2>$null | Out-Null
        }
        if ($script:DEV_EMAIL) {
            git config user.email "$($script:DEV_EMAIL)" 2>$null | Out-Null
        }
    }
}

function New-InitialCommit {
    <#
    .SYNOPSIS
        Creates the initial commit with project setup message.
    #>
    Out-Info "Adding files to git..."
    
    git add . 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Out-Error "Failed to add files to git."
        exit 1
    }
    
    Out-Info "Creating initial commit..."
    
    $commitMessage = @"
Initial commit: $($script:GITHUB_REPO)

- Project setup with proper structure
- Version $($script:PACK_VERSION)
"@
    
    if ($script:DEV_EMAIL) {
        $commitMessage += "`n- Author: $($script:DEV_NAME) <$($script:DEV_EMAIL)>"
    } else {
        $commitMessage += "`n- Author: $($script:DEV_NAME)"
    }
    
    $commitOutput = git commit -m "$commitMessage" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Out-Warn "Nothing to commit or commit failed."
    } else {
        Out-Success "Initial commit created."
    }
}

function New-VersionTag {
    <#
    .SYNOPSIS
        Creates an annotated Git tag for the initial version.
    #>
    Out-Info "Creating tag v$($script:PACK_VERSION)..."
    
    $tagMessage = @"
Release v$($script:PACK_VERSION)

Initial release of $($script:GITHUB_REPO).
"@
    
    if ($script:DEV_EMAIL) {
        $tagMessage += "`nAuthor: $($script:DEV_NAME) <$($script:DEV_EMAIL)>"
    } else {
        $tagMessage += "`nAuthor: $($script:DEV_NAME)"
    }
    
    $tagOutput = git tag -a "v$($script:PACK_VERSION)" -m "$tagMessage" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Out-Success "Tag v$($script:PACK_VERSION) created."
    } else {
        Out-Warn "Tag v$($script:PACK_VERSION) may already exist."
    }
}

function New-ReleaseNotes {
    <#
    .SYNOPSIS
        Generates RELEASE_NOTES.md file.
    #>
    Out-Info "Generating release notes..."
    
    if ($script:DEV_EMAIL) {
        $authorLine = "$($script:DEV_NAME) ($($script:DEV_EMAIL))"
    } else {
        $authorLine = $script:DEV_NAME
    }
    
    $releaseNotes = @"
# Release v$($script:PACK_VERSION)

## What's New
- First stable release of $($script:GITHUB_REPO)
- Project initialized and configured

## Installation

Download appropriate package for your platform from the releases section.

## Documentation
See README.md and CONTRIBUTING.md for details.

Author: $authorLine
"@
    
    Set-Content -LiteralPath "RELEASE_NOTES.md" -Value $releaseNotes
    Out-Success "Release notes created: RELEASE_NOTES.md"
}

function Add-GitRemote {
    <#
    .SYNOPSIS
        Configures the Git remote and pushes initial content.
    
    .DESCRIPTION
        Adds the GitHub repository as the 'origin' remote and pushes both the main branch
        and the version tag. If the repository was created via API, it uses the provided
        clone URL; otherwise, constructs the standard HTTPS URL for manual setup.
    #>
    param([string]$RemoteUrl)

    Out-Info "Adding remote origin..."
    
    git remote add origin $RemoteUrl 2>$null
    if ($LASTEXITCODE -ne 0) {
        # Remote might already exist, try to update URL
        git remote set-url origin $RemoteUrl 2>$null
        if ($LASTEXITCODE -ne 0) {
            Out-Warn "Could not configure remote origin. You may need to add it manually."
            return
        }
    }
    
    Out-Info "Pushing to GitHub..."
    
    # Determine default branch name
    $branchName = git branch --show-current 2>$null
    if (-not $branchName) {
        $branchName = "main"
    }
    
    git push -u origin $branchName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Out-Success "Pushed branch '$branchName' to GitHub."
    } else {
        Out-Warn "Failed to push branch. You may need to push manually."
    }
    
    git push origin "v$($script:PACK_VERSION)" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Out-Success "Pushed tag v$($script:PACK_VERSION) to GitHub."
    } else {
        Out-Warn "Failed to push tag. You may need to push it manually."
    }
}

function Show-RemoteInstructions {
    <#
    .SYNOPSIS
        Displays post-initialization instructions.
    #>
    [Console]::Out.WriteLine("")
    Out-Info "To connect to GitHub, run:"
    Out-Info "  git remote add origin https://github.com/$($script:GITHUB_USER)/$($script:GITHUB_REPO).git"
    Out-Info "  git push -u origin main"
    [Console]::Out.WriteLine("")
    Out-Info "To push tag to GitHub:"
    Out-Info "  git push origin v$($script:PACK_VERSION)"
    [Console]::Out.WriteLine("")
    
    # Display current Git identity
    $currentName = git config user.name 2>$null
    $currentEmail = git config user.email 2>$null
    Out-Info "Git identity for this repository:"
    Out-Info "  Commit will use: $(if ($currentName) { $currentName } else { '(not set)' }) <$(if ($currentEmail) { $currentEmail } else { '(not set)' })>"
    
    if ($script:SET_LOCAL_GIT_CONFIG) {
        $localName = git config --local user.name 2>$null
        $localEmail = git config --local user.email 2>$null
        $globalName = git config --global user.name 2>$null
        $globalEmail = git config --global user.email 2>$null
        
        [Console]::Out.WriteLine("")
        Out-Info "Local git config was set. Future commits in this repo will use:"
        Out-Info "  user.name:  $(if ($localName) { $localName } else { '(not set)' })"
        Out-Info "  user.email: $(if ($localEmail) { $localEmail } else { '(not set)' })"
        [Console]::Out.WriteLine("")
        Out-Info "Your global git config remains unchanged:"
        Out-Info "  global user.name:  $(if ($globalName) { $globalName } else { '(not set)' })"
        Out-Info "  global user.email: $(if ($globalEmail) { $globalEmail } else { '(not set)' })"
    } else {
        [Console]::Out.WriteLine("")
        Out-Info "Using global git config (not modified for this repo)"
    }
}

#__________ Main execution flow ___________________________________________________________________
function Invoke-Main {
    <#
    .SYNOPSIS
        Orchestrates the repository initialization process.
    #>
    Initialize-Arguments
    
    if ($script:VERBOSE) {
        Out-Info "Running $(Get-ScriptName) version $SCRIPT_VERSION"
    }
    Out-Info "Initializing repository: $($script:GITHUB_REPO)"
    Out-Info "GitHub user: $($script:GITHUB_USER)"
    Out-Info "Developer: $($script:DEV_NAME) $(if ($script:DEV_EMAIL) { "<$($script:DEV_EMAIL)>" })"
    Out-Info "Package version: $($script:PACK_VERSION)"
    if ($script:SET_LOCAL_GIT_CONFIG) {
        Out-Info "Will set local git config: YES"
    } else {
        Out-Info "Will set local git config: NO (using global)"
    }
    if ($CreateRemote) {
        $remoteType = "public"
        if ($Private) {
            $remoteType = "private"
        }
        Out-Info "Will create GitHub repository: YES ($remoteType)"
    }
    
    # Execute initialization phases
    Initialize-GitRepository
    New-InitialCommit
    New-VersionTag
    New-ReleaseNotes
    
    # GitHub remote creation and push
    if ($CreateRemote) {
        try {
            $repoInfo = New-GitHubRepository -Owner $script:GITHUB_USER -Name $script:GITHUB_REPO `
                                            -Token $script:GITHUB_TOKEN -IsPrivate $Private `
                                            -ApiUrl $ApiBaseUrl
            Add-GitRemote -RemoteUrl $repoInfo.clone_url
        }
        catch {
            Out-Warn "GitHub repository creation failed. You can create it manually and push."
            Show-RemoteInstructions
            exit 1
        }
    } else {
        Show-RemoteInstructions
    }
    
    # Finalization
    Out-Success "=== Initialization complete ==="
    if (-not $CreateRemote) {
        Out-Info "Next steps:"
        Out-Info "1. Create repository on GitHub: https://github.com/new"
        Out-Info "2. Run: git remote add origin https://github.com/$($script:GITHUB_USER)/$($script:GITHUB_REPO).git"
        Out-Info "3. Run: git push -u origin main"
        Out-Info "4. Run: git push origin v$($script:PACK_VERSION)"
        Out-Info "5. Upload release artifacts"
    } else {
        Out-Info "Your repository is now live on GitHub and ready for development."
    }
}

# Begin execution
Invoke-Main