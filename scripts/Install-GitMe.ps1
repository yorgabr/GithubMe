#Requires -Version 5.1
<#
.SYNOPSIS
    Idempotent local installer for GitMe.
    Run from the repository root:  .\scripts\Install-GitMe.ps1
#>
[CmdletBinding()]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. Resolve source and destination
# ---------------------------------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
$srcPath  = Join-Path $repoRoot 'src'

$manifestFile = Join-Path $srcPath 'GitMe.psd1'
if (-not (Test-Path $manifestFile)) {
    throw "Manifest not found at '$manifestFile'. Run this script from the repository root."
}

$version = (Import-PowerShellDataFile $manifestFile).ModuleVersion

if ($AllUsers) {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw '-AllUsers requires an elevated (Administrator) PowerShell session.'
    }
    $modulesRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
}
else {
    $modulesRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
}

$destModule  = Join-Path $modulesRoot 'GitMe'
$destVersion = Join-Path $destModule  $version

# ---------------------------------------------------------------------------
# 2. Copy module files
# ---------------------------------------------------------------------------
Write-Host "Installing GitMe $version to '$destVersion'..." -ForegroundColor Cyan

if (Test-Path $destVersion) {
    Remove-Item $destVersion -Recurse -Force
}

New-Item -ItemType Directory -Path $destVersion -Force | Out-Null
Copy-Item -Path "$srcPath\*" -Destination $destVersion -Recurse -Force

Write-Host "Module files copied." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Ensure the module root is on PSModulePath (persistent)
# ---------------------------------------------------------------------------
$scope = if ($AllUsers) { 'Machine' } else { 'User' }

$currentPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', $scope)
if ($null -eq $currentPSModulePath) { $currentPSModulePath = '' }

if ($currentPSModulePath -notlike "*$modulesRoot*") {
    if ($currentPSModulePath -eq '') {
        $newPath = $modulesRoot
    }
    else {
        $newPath = $currentPSModulePath.TrimEnd(';') + ";$modulesRoot"
    }
    [Environment]::SetEnvironmentVariable('PSModulePath', $newPath, $scope)
    Write-Host "Added '$modulesRoot' to PSModulePath ($scope)." -ForegroundColor Green
}
else {
    Write-Host "'$modulesRoot' already in PSModulePath ($scope)." -ForegroundColor DarkGreen
}

# Update the current session immediately
if ($env:PSModulePath -notlike "*$modulesRoot*") {
    $env:PSModulePath = $env:PSModulePath.TrimEnd(';') + ";$modulesRoot"
}

# ---------------------------------------------------------------------------
# 4. Import the module in the current session
# ---------------------------------------------------------------------------
Write-Host "Importing GitMe into the current session..." -ForegroundColor Cyan

if (Get-Module -Name GitMe) {
    Remove-Module -Name GitMe -Force
}

Import-Module GitMe -Force -ErrorAction Stop

$loadedVersion = (Get-Module -Name GitMe).Version
Write-Host "GitMe $loadedVersion loaded successfully." -ForegroundColor Green

# Verify or manually register the alias.
# In some PS 5.1 hosts the alias from Export-ModuleMember is not visible in
# the global scope until the next session; Set-Alias ensures it works now.
if (-not (Get-Alias -Name gitme -ErrorAction SilentlyContinue)) {
    Set-Alias -Name gitme -Value Invoke-Gitme -Scope Global
    Write-Host "Alias 'gitme' registered manually for this session." -ForegroundColor Yellow
}
else {
    Write-Host "Alias 'gitme' is available." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 5. Configure the PowerShell profile
# ---------------------------------------------------------------------------
$profilePath = if ($AllUsers) { $PROFILE.AllUsersCurrentHost } else { $PROFILE.CurrentUserCurrentHost }

Write-Host "Configuring profile at '$profilePath'..." -ForegroundColor Cyan

$profileDir = Split-Path $profilePath
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
    Write-Host "Profile file created." -ForegroundColor Green
}

$importLine     = 'Import-Module GitMe -ErrorAction SilentlyContinue'
$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if ($null -eq $profileContent) { $profileContent = '' }

if ($profileContent -notlike "*$importLine*") {
    Add-Content -Path $profilePath -Value "`n$importLine" -Encoding UTF8
    Write-Host "Added '$importLine' to profile." -ForegroundColor Green
}
else {
    Write-Host "Profile already contains the Import-Module line." -ForegroundColor DarkGreen
}

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host "  GitMe $version installed successfully."  -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Available right now in this session:'      -ForegroundColor Yellow
Write-Host '  gitme -Help'                             -ForegroundColor White
Write-Host '  gitme -Version'                          -ForegroundColor White
Write-Host ''
Write-Host 'Will load automatically in every new PowerShell session.' -ForegroundColor Yellow
