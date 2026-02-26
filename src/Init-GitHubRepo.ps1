#Requires -Version 6.0
<#
.SYNOPSIS
    Initializes a local Git repository with proper structure and prepares it for GitHub publishing.

.DESCRIPTION
    This script automates the setup of a new Git repository with professional standards.
    
    When you start a new project, there's a repetitive sequence of steps: initialize git,
    configure your identity, create that first commit, set up versioning tags, and prepare
    documentation. This script handles all of that in one go.
    
    The script reads your existing Git configuration as sensible defaults, but allows
    complete override through parameters. It creates a tagged initial release with
    release notes, ready for you to push to GitHub and start collaborating.
    
    By default, the script sets repository-specific Git identity (user.name and user.email)
    locally, leaving your global Git configuration untouched. This is useful when you
    need different identities for personal versus work projects.

.PARAMETER GithubUser
    Your GitHub username. This becomes part of the remote URL suggestion and fallback
    developer name if no other identity is configured.

.PARAMETER GithubRepo
    The name of your repository. Used in commit messages, tags, and documentation.

.PARAMETER DevName
    The full name to use for Git commits. If not specified, the script first checks
    your global Git config, then falls back to the GithubUser value.

.PARAMETER DevEmail
    The email address for Git commits. If not specified, uses your global Git config
    if available. Can be left empty if you prefer not to include email in commits.

.PARAMETER PackVersion
    The initial semantic version for your project. Defaults to 0.1.0 for fresh starts.
    This version is used to create the initial Git tag.

.PARAMETER SetLocalGitConfig
    Forces local Git configuration even if NoSetLocalGitConfig was previously considered.
    This is the default behavior.

.PARAMETER NoSetLocalGitConfig
    When specified, the script will not modify local Git config, relying entirely on
    your global Git identity settings instead.

.PARAMETER VerboseOutput
    Enables detailed step-by-step logging with timestamps. Useful for debugging or
    understanding exactly what the script is doing.

.PARAMETER Version
    Displays the script's own version number and exits immediately.

.PARAMETER Help
    Shows this detailed help information.

.PARAMETER GenerateCompletion
    Installs PowerShell argument completion for this script. Available scopes:
    - TEMP: Current session only (lost when PowerShell closes)
    - USER: Permanent for your user profile
    - SYSTEM: Available to all users on this machine (requires administrator rights)

.EXAMPLE
    PS> Init-GitHubRepo.ps1 -GithubUser "jdoe" -GithubRepo "my-awesome-app"
    
    The simplest usage. Creates a repo using your GitHub username as fallback identity,
    with default version 0.1.0, and sets local Git config.

.EXAMPLE
    PS> Init-GitHubRepo.ps1 -GithubUser "acme-corp" -GithubRepo "internal-tool" `
                             -DevName "Jane Developer" -DevEmail "jane@acme.com" `
                             -PackVersion "1.0.0" -NoSetLocalGitConfig
    
    Full specification for a corporate project. Uses the company's GitHub organization,
    specific developer identity, starts at version 1.0.0, and respects global Git config.

.EXAMPLE
    PS> Init-GitHubRepo.ps1 -GenerateCompletion USER
    
    Sets up tab completion for this script in your PowerShell profile, making it
    easier to use parameters interactively.

.NOTES
    File Name      : Init-GitHubRepo.ps1
    Author         : Yorga Babuscan (yorgabr@gmail.com)
    Prerequisite   : Git must be installed and available in PATH
    Version        : 1.2.0
    License        : GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="GitHub username for remote URL")]
    [string]$GithubUser,

    [Parameter(Mandatory=$false, HelpMessage="Repository name")]
    [string]$GithubRepo,

    [Parameter(Mandatory=$false, HelpMessage="Developer full name for Git commits")]
    [string]$DevName,

    [Parameter(Mandatory=$false, HelpMessage="Developer email for Git commits")]
    [string]$DevEmail,

    [Parameter(Mandatory=$false, HelpMessage="Initial semantic version")]
    [string]$PackVersion = "0.1.0",

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

# Version information
$SCRIPT_VERSION = "1.2.0"

# Strict error handling
$ErrorActionPreference = "Stop"

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

# Color codes for terminal output
$ESC = [char]27
$Cyan = "${ESC}[36m"
$Yellow = "${ESC}[33m"
$Green = "${ESC}[32m"
$Red = "${ESC}[31m"
$Reset = "${ESC}[0m"

<#
.SYNOPSIS
    Retrieves a value from Git configuration.

.DESCRIPTION
    Queries the Git configuration system for a specific key. Returns empty string
    if the key is not set or if Git is not available.
#>
function Get-GitConfig {
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

<#
.SYNOPSIS
    Generates a timestamp string for log entries.

.DESCRIPTION
    Creates a compact timestamp in the format YearMonthDayHourMinuteSecond,
    suitable for prefixing log messages to show when events occurred.
#>
function Get-Timestamp {
    return Get-Date -Format "yyyyMMddHHmmss"
}

<#
.SYNOPSIS
    Writes an error message to the error stream.

.DESCRIPTION
    Displays error messages in red with a timestamp. Always visible regardless
    of verbose settings, as errors indicate problems that need attention.
#>
function Write-LogError {
    param([string]$Message)
    $timestamp = Get-Timestamp
    Write-Host "$timestamp`t${Red}[ERROR]${Reset}`t$Message" -ForegroundColor Red
}

<#
.SYNOPSIS
    Writes a warning message.

.DESCRIPTION
    Displays warning messages in yellow with a timestamp. Warnings indicate
    non-fatal issues that the user should be aware of but don't stop execution.
#>
function Write-LogWarn {
    param([string]$Message)
    $timestamp = Get-Timestamp
    Write-Host "$timestamp`t${Yellow}[WARN]${Reset}`t$Message" -ForegroundColor Yellow
}

<#
.SYNOPSIS
    Writes an informational message.

.DESCRIPTION
    Displays informational messages in cyan, but only when verbose mode is enabled.
    These messages help track the script's progress through various stages.
#>
function Write-LogInfo {
    param([string]$Message)
    if ($script:VERBOSE) {
        $timestamp = Get-Timestamp
        Write-Host "$timestamp`t${Cyan}[INFO]${Reset}`t$Message" -ForegroundColor Cyan
    }
}

<#
.SYNOPSIS
    Writes a success message.

.DESCRIPTION
    Displays success messages in green, but only when verbose mode is enabled.
    Used to confirm that a major step has completed successfully.
#>
function Write-LogSuccess {
    param([string]$Message)
    if ($script:VERBOSE) {
        $timestamp = Get-Timestamp
        Write-Host "$timestamp`t${Green}[SUCCESS]${Reset}`t$Message" -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Returns the name of the currently executing script.

.DESCRIPTION
    Extracts just the filename from the full path of the script, useful for
    displaying the script name in messages and version information.
#>
function Get-ScriptName {
    return Split-Path -Leaf $PSCommandPath
}

<#
.SYNOPSIS
    Displays the script version.

.DESCRIPTION
    Prints the script name and version number in a simple format, then exits.
    This is a standalone operation that doesn't perform any repository initialization.
#>
function Show-Version {
    $name = Get-ScriptName
    Write-Host "$name version $SCRIPT_VERSION"
}

<#
.SYNOPSIS
    Displays comprehensive usage help.

.DESCRIPTION
    Shows detailed help information including description, parameter explanations,
    and usage examples. Formatted for readability in the terminal.
#>
function Show-Usage {
    @"
Init-GitHubRepo.ps1 — Initialize a Git repository with proper tagging and release structure.

Usage:
    Init-GitHubRepo.ps1 -GithubUser <username> -GithubRepo <name> [options]

Required Arguments:
    -GithubUser USERNAME      GitHub username for remote URL.
    -GithubRepo NAME          GitHub repository name.

Options:
    -Version                  Show script semantic version and exit.
    -Help, -h, -?             Show this help and exit.
    -DevName NAME             Developer's full name (default: -GithubUser value,
                              or git config user.name if set).
    -DevEmail EMAIL           Developer's e-mail (default: git config user.email
                              if set, otherwise empty).
    -PackVersion SEMVER      Package version for tag (default: 0.1.0).
    -SetLocalGitConfig        Set user.name and user.email in local git config
                              for this repository only (default: true).
    -NoSetLocalGitConfig      Disable setting local git config (use global).
    -VerboseOutput            Echo each step.
    -GenerateCompletion SCOPE
                              Generate and install PowerShell argument completer.
                              SCOPE can be: TEMP, USER, or SYSTEM.
                              TEMP: registers completer for current session only.
                              USER: installs to user profile.
                              SYSTEM: installs to all users (requires admin).

Examples:
    # Basic usage (sets local git config by default)
    Init-GitHubRepo.ps1 -GithubUser john -GithubRepo myproject

    # Use global git config instead
    Init-GitHubRepo.ps1 -GithubUser john -GithubRepo myproject -NoSetLocalGitConfig

    # Full specification
    Init-GitHubRepo.ps1 -GithubUser john -GithubRepo myproject `
        -DevName "John Doe" -DevEmail "john@example.com" `
        -PackVersion 1.0.0

    # Generate and install autocomplete for current user
    Init-GitHubRepo.ps1 -GenerateCompletion USER

    # Generate and install autocomplete system-wide (requires admin)
    Init-GitHubRepo.ps1 -GenerateCompletion SYSTEM

Author: Yorga Babuscan (yorgabr@gmail.com)
"@
}

<#
.SYNOPSIS
    Processes and validates all script arguments.

.DESCRIPTION
    This is the central configuration phase. It handles special flags like -Version
    and -Help first, then validates that required parameters are present. It applies
    sensible defaults for developer identity by checking Git configuration and
    falling back to the GitHub username when necessary.

    The function ensures that conflicting flags are detected and that the script
    state is fully initialized before any Git operations begin.
#>
function Initialize-Arguments {
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

    # Set verbose flag based on parameter
    $script:VERBOSE = $VerboseOutput.IsPresent

    # Validate conflicting git config flags
    if ($SetLocalGitConfig -and $NoSetLocalGitConfig) {
        Write-LogError "Cannot use both -SetLocalGitConfig and -NoSetLocalGitConfig"
        exit 2
    }
    
    if ($NoSetLocalGitConfig) {
        $script:SET_LOCAL_GIT_CONFIG = $false
    }

    # Validate required parameters
    if (-not $GithubUser) {
        Write-LogError "Missing required argument: -GithubUser"
        Show-Usage
        exit 2
    }

    if (-not $GithubRepo) {
        Write-LogError "Missing required argument: -GithubRepo"
        Show-Usage
        exit 2
    }

    # Store required values
    $script:GITHUB_USER = $GithubUser
    $script:GITHUB_REPO = $GithubRepo

    # Determine developer name with cascading fallback
    if ($DevName) {
        $script:DEV_NAME = $DevName
    } else {
        if ($script:DEFAULT_GIT_NAME) {
            $script:DEV_NAME = $script:DEFAULT_GIT_NAME
            Write-LogInfo "Using git config user.name for dev-name: $($script:DEV_NAME)"
        } else {
            $script:DEV_NAME = $script:GITHUB_USER
            Write-LogInfo "Using github-user for dev-name: $($script:DEV_NAME)"
        }
    }

    # Determine developer email with optional fallback
    if ($DevEmail) {
        $script:DEV_EMAIL = $DevEmail
    } else {
        if ($script:DEFAULT_GIT_EMAIL) {
            $script:DEV_EMAIL = $script:DEFAULT_GIT_EMAIL
            Write-LogInfo "Using git config user.email for dev-email: $($script:DEV_EMAIL)"
        } else {
            $script:DEV_EMAIL = ""
            Write-LogInfo "No dev-email provided and no git config user.email set. Leaving empty."
        }
    }

    # Store package version
    if ($PackVersion) {
        $script:PACK_VERSION = $PackVersion
    }
}

<#
.SYNOPSIS
    Generates the PowerShell argument completer script block.

.DESCRIPTION
    Creates a completion script that provides IntelliSense-style parameter
    suggestions when users type commands interactively. This makes the script
    more discoverable and easier to use.
#>
function Get-CompletionScript {
    @'
# Init-GitHubRepo.ps1 argument completer
# Generated automatically - do not edit manually

$initRepoParams = @(
    'GithubUser'
    'GithubRepo'
    'DevName'
    'DevEmail'
    'PackVersion'
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

<#
.SYNOPSIS
    Installs PowerShell argument completion.

.DESCRIPTION
    Sets up tab completion for this script's parameters. Three scopes are available:
    
    TEMP is useful for trying out the completion or in automation scenarios where
    you don't want permanent changes. USER modifies your personal PowerShell profile
    so completion works in every new session you start. SYSTEM requires administrator
    rights and makes completion available to all users on the machine.

    The completion specifically helps with the GenerateCompletion parameter values,
    suggesting TEMP, USER, or SYSTEM as you type.
#>
function Install-Completion {
    param([string]$Scope)

    switch ($Scope) {
        'TEMP' {
            Write-LogInfo "Installing PowerShell completion for current session (TEMP)..."
            Invoke-Expression (Get-CompletionScript)
            Write-LogSuccess "PowerShell completion activated for current session."
        }
        'USER' {
            Write-LogInfo "Installing PowerShell completion for user (USER)..."
            
            $profileDir = Split-Path -Parent $PROFILE
            if (-not (Test-Path $profileDir)) {
                Write-LogInfo "Creating directory: $profileDir"
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            }

            $completionScript = Get-CompletionScript
            $completionBlock = "`n# Init-GitHubRepo.ps1 completion`n$completionScript`n"
            
            if (Test-Path $PROFILE) {
                Add-Content -Path $PROFILE -Value $completionBlock
            } else {
                Set-Content -Path $PROFILE -Value $completionBlock
            }
            
            Write-LogSuccess "PowerShell completion installed to profile: $PROFILE"
            Write-LogInfo "To activate immediately, run: . `$PROFILE"
            Write-LogInfo "Or restart your PowerShell session."
        }
        'SYSTEM' {
            Write-LogInfo "Installing PowerShell completion system-wide (SYSTEM)..."
            
            # Determine if we have administrator privileges
            $isAdmin = $false
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                # PowerShell Core / 7+
                if ($IsWindows) {
                    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                } else {
                    $isAdmin = (id -u) -eq 0 2>$null
                }
            } else {
                # Windows PowerShell 5.1
                $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            }

            if (-not $isAdmin) {
                Write-LogError "System-wide installation requires administrator privileges."
                Write-LogInfo "Please run PowerShell as Administrator."
                exit 1
            }

            # Determine the all-users profile location based on PowerShell version
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                if ($IsWindows) {
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
            if (-not (Test-Path $profileDir)) {
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            }

            if (Test-Path $allUsersProfile) {
                Add-Content -Path $allUsersProfile -Value $completionBlock
            } else {
                Set-Content -Path $allUsersProfile -Value $completionBlock
            }
            
            Write-LogSuccess "PowerShell completion installed to: $allUsersProfile"
            Write-LogInfo "All users will have completion available in new PowerShell sessions."
        }
    }
}

<#
.SYNOPSIS
    Creates and configures the local Git repository.

.DESCRIPTION
    Initializes a new Git repository if one doesn't exist, then switches to the
    main branch (falling back to master for older Git versions). 
    
    When local configuration is enabled, it sets repository-specific user identity,
    which is particularly useful when you maintain different personas for different
    projects (personal vs. professional, open source vs. internal).
    
    The function reports what configuration was applied so you can verify the
    repository is set up according to your intentions.
#>
function Initialize-GitRepository {
    if (-not (Test-Path ".git")) {
        Write-LogInfo "Initializing git repository..."
        
        git init | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "Failed to initialize git repository."
            exit 1
        }
        
        # Try 'main' first (modern default), fall back to 'master' if needed
        git checkout -b main 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            git checkout -b master 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-LogError "Failed to create main/master branch."
                exit 1
            }
        }
        
        Write-LogSuccess "Git repository initialized."
    } else {
        Write-LogInfo "Git repository already exists."
    }

    # Apply local Git configuration if requested
    if ($script:SET_LOCAL_GIT_CONFIG) {
        Write-LogInfo "Setting local git config for this repository..."
        
        if ($script:DEV_NAME) {
            git config --local user.name "$($script:DEV_NAME)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-LogSuccess "Set local user.name: $($script:DEV_NAME)"
            } else {
                Write-LogWarn "Failed to set local user.name"
            }
        }
        
        if ($script:DEV_EMAIL) {
            git config --local user.email "$($script:DEV_EMAIL)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-LogSuccess "Set local user.email: $($script:DEV_EMAIL)"
            } else {
                Write-LogWarn "Failed to set local user.email"
            }
        }
        
        # Display current configuration for verification
        $localName = git config --local user.name 2>$null
        $localEmail = git config --local user.email 2>$null
        Write-LogInfo "Local git config for this repository:"
        Write-LogInfo "  user.name:  $(if ($localName) { $localName } else { '(not set)' })"
        Write-LogInfo "  user.email: $(if ($localEmail) { $localEmail } else { '(not set)' })"
    } else {
        Write-LogInfo "Using global git config (local config not set)"
        # Set for this commit only if not configuring locally
        if ($script:DEV_NAME) {
            git config user.name "$($script:DEV_NAME)" 2>$null | Out-Null
        }
        if ($script:DEV_EMAIL) {
            git config user.email "$($script:DEV_EMAIL)" 2>$null | Out-Null
        }
    }
}

<#
.SYNOPSIS
    Creates the initial commit with project setup message.

.DESCRIPTION
    Stages all files in the current directory and creates the first commit with
    a descriptive message that includes the repository name, version, and author
    information. This establishes the baseline of your project history.

    If there's nothing to commit (empty directory), a warning is issued but
    execution continues so you can add files later.
#>
function New-InitialCommit {
    Write-LogInfo "Adding files to git..."
    
    git add . 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-LogError "Failed to add files to git."
        exit 1
    }
    
    Write-LogInfo "Creating initial commit..."
    
    $commitMessage = @"
Initial commit: $($script:GITHUB_REPO)

- Project setup with proper structure
- Version $($script:PACK_VERSION)
"@
    
    # Append author information to commit message
    if ($script:DEV_EMAIL) {
        $commitMessage += "`n- Author: $($script:DEV_NAME) <$($script:DEV_EMAIL)>"
    } else {
        $commitMessage += "`n- Author: $($script:DEV_NAME)"
    }
    
    $commitOutput = git commit -m "$commitMessage" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-LogWarn "Nothing to commit or commit failed."
    } else {
        Write-LogSuccess "Initial commit created."
    }
}

<#
.SYNOPSIS
    Creates an annotated Git tag for the initial version.

.DESCRIPTION
    Tags are how Git marks specific points in history as important. This function
    creates an annotated tag (which includes metadata like author and date) marking
    the initial release. The tag message includes version, project name, and
    author details.

    If the tag already exists, a warning is issued without failing, allowing
    you to run the script multiple times safely.
#>
function New-VersionTag {
    Write-LogInfo "Creating tag v$($script:PACK_VERSION)..."
    
    $tagMessage = @"
Release v$($script:PACK_VERSION)

Initial release of $($script:GITHUB_REPO).
"@
    
    # Append author information to tag message
    if ($script:DEV_EMAIL) {
        $tagMessage += "`nAuthor: $($script:DEV_NAME) <$($script:DEV_EMAIL)>"
    } else {
        $tagMessage += "`nAuthor: $($script:DEV_NAME)"
    }
    
    $tagOutput = git tag -a "v$($script:PACK_VERSION)" -m "$tagMessage" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-LogSuccess "Tag v$($script:PACK_VERSION) created."
    } else {
        Write-LogWarn "Tag v$($script:PACK_VERSION) may already exist."
    }
}

<#
.SYNOPSIS
    Generates RELEASE_NOTES.md file.

.DESCRIPTION
    Creates a markdown file with initial release documentation. This serves as
    a template that you can expand as your project grows, documenting what's
    new in each version. The file includes installation instructions and pointers
    to other documentation files.
#>
function New-ReleaseNotes {
    Write-LogInfo "Generating release notes..."
    
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
    
    Set-Content -Path "RELEASE_NOTES.md" -Value $releaseNotes
    Write-LogSuccess "Release notes created: RELEASE_NOTES.md"
}

<#
.SYNOPSIS
    Displays post-initialization instructions.

.DESCRIPTION
    Shows the exact Git commands needed to connect your local repository to GitHub
    and push your initial commit and tag. It also displays the Git identity
    configuration that will be used for future commits, helping you verify that
    everything is set up correctly before proceeding.

    This bridges the gap between local initialization and remote publication.
#>
function Show-RemoteInstructions {
    Write-LogInfo ""
    Write-LogInfo "To connect to GitHub, run:"
    Write-LogInfo "  git remote add origin https://github.com/$($script:GITHUB_USER)/$($script:GITHUB_REPO).git"
    Write-LogInfo "  git push -u origin main"
    Write-LogInfo ""
    Write-LogInfo "To push tag to GitHub:"
    Write-LogInfo "  git push origin v$($script:PACK_VERSION)"
    Write-LogInfo ""
    
    # Display current Git identity
    $currentName = git config user.name 2>$null
    $currentEmail = git config user.email 2>$null
    Write-LogInfo "Git identity for this repository:"
    Write-LogInfo "  Commit will use: $(if ($currentName) { $currentName } else { '(not set)' }) <$(if ($currentEmail) { $currentEmail } else { '(not set)' })>"
    
    if ($script:SET_LOCAL_GIT_CONFIG) {
        $localName = git config --local user.name 2>$null
        $localEmail = git config --local user.email 2>$null
        $globalName = git config --global user.name 2>$null
        $globalEmail = git config --global user.email 2>$null
        
        Write-LogInfo ""
        Write-LogInfo "Local git config was set. Future commits in this repo will use:"
        Write-LogInfo "  user.name:  $(if ($localName) { $localName } else { '(not set)' })"
        Write-LogInfo "  user.email: $(if ($localEmail) { $localEmail } else { '(not set)' })"
        Write-LogInfo ""
        Write-LogInfo "Your global git config remains unchanged:"
        Write-LogInfo "  global user.name:  $(if ($globalName) { $globalName } else { '(not set)' })"
        Write-LogInfo "  global user.email: $(if ($globalEmail) { $globalEmail } else { '(not set)' })"
    } else {
        Write-LogInfo ""
        Write-LogInfo "Using global git config (not modified for this repo)"
    }
}

<#
.SYNOPSIS
    Main execution flow.

.DESCRIPTION
    Orchestrates the entire repository initialization process. It validates
    arguments, initializes the Git repository, creates the initial commit,
    sets up the version tag, generates release notes, and finally displays
    instructions for connecting to GitHub.

    Each phase is logged so you can follow the progress, and the script
    is designed to fail fast if any critical step encounters an error.
#>
function Invoke-Main {
    Initialize-Arguments
    
    if ($script:VERBOSE) {
        Write-LogInfo "Running $(Get-ScriptName) version $SCRIPT_VERSION"
    }
    Write-LogInfo "Initializing repository: $($script:GITHUB_REPO)"
    Write-LogInfo "GitHub user: $($script:GITHUB_USER)"
    Write-LogInfo "Developer: $($script:DEV_NAME) $(if ($script:DEV_EMAIL) { "<$($script:DEV_EMAIL)>" })"
    Write-LogInfo "Package version: $($script:PACK_VERSION)"
    if ($script:SET_LOCAL_GIT_CONFIG) {
        Write-LogInfo "Will set local git config: YES"
    } else {
        Write-LogInfo "Will set local git config: NO (using global)"
    }
    
    # Execute initialization phases
    Initialize-GitRepository
    New-InitialCommit
    New-VersionTag
    New-ReleaseNotes
    
    # Finalization
    Write-LogSuccess "=== Initialization complete ==="
    Show-RemoteInstructions
    Write-LogInfo "Next steps:"
    Write-LogInfo "1. Create repository on GitHub: https://github.com/new"
    Write-LogInfo "2. Run: git remote add origin https://github.com/$($script:GITHUB_USER)/$($script:GITHUB_REPO).git"
    Write-LogInfo "3. Run: git push -u origin main"
    Write-LogInfo "4. Run: git push origin v$($script:PACK_VERSION)"
    Write-LogInfo "5. Upload release artifacts"
}

# Begin execution
Invoke-Main