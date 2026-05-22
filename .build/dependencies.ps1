<#
.SYNOPSIS
    Bootstraps all build-time dependencies for GitMe CI/CD.
#>
[CmdletBinding()]
param()

$required = @(
    @{ Name = 'InvokeBuild';      Version = '5.0.0' }
    @{ Name = 'Pester';           Version = '5.0.0' }
    @{ Name = 'PSScriptAnalyzer'; Version = '1.21.0' }
    @{ Name = 'PowerShellGet';    Version = '2.2.5' }
    @{ Name = 'PackageManagement'; Version = '1.4.8' }
)

foreach ($mod in $required) {
    $installed = Get-Module -ListAvailable -Name $mod.Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $installed -or $installed.Version -lt [version]$mod.Version) {
        Write-Host "Installing $($mod.Name) >= $($mod.Version)..." -ForegroundColor Cyan
        Install-Module -Name $mod.Name -MinimumVersion $mod.Version -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
    }
    else {
        Write-Host "$($mod.Name) $($installed.Version) already installed." -ForegroundColor Green
    }
}

# Ensure git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is not installed. Install Git for Windows >= 2.50.0 from https://git-scm.com/download/win'
}

Write-Host 'All dependencies satisfied.' -ForegroundColor Green
