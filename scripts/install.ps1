#Requires -Version 5.1
<#
.SYNOPSIS
    One-line installer for GitMe.
    Invoke with: irm https://raw.githubusercontent.com/yorgabr/GitMe/main/scripts/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$Version = '{{VERSION}}',
    [string]$InstallPath,
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

$repoUrl = 'https://github.com/yorgabr/GitMe'
$releaseUrl = "$repoUrl/releases/download/v$Version/GitMe.${Version}.zip"

# Determine module path
if ($InstallPath) {
    $dest = $InstallPath
}
elseif ($AllUsers) {
    $dest = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules\GitMe'
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges required for -AllUsers installation.'
    }
}
else {
    $dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules\GitMe'
}

$versionPath = Join-Path $dest $Version
Write-Host "Installing GitMe $Version to $versionPath ..." -ForegroundColor Cyan

# Download
$tempZip = Join-Path $env:TEMP "GitMe.${Version}.zip"
Invoke-WebRequest -Uri $releaseUrl -OutFile $tempZip -UseBasicParsing

# Extract
if (Test-Path $versionPath) { Remove-Item $versionPath -Recurse -Force }
New-Item -ItemType Directory -Path $versionPath -Force | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $versionPath -Force
Remove-Item $tempZip -Force

# Verify checksums
$checksumFile = Join-Path $versionPath 'checksums.json'
if (Test-Path $checksumFile) {
    $hashes = Get-Content $checksumFile -Raw | ConvertFrom-Json
    foreach ($entry in $hashes) {
        $file = Join-Path $versionPath $entry.Path
        if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $entry.Hash) {
            throw "Checksum mismatch for $($entry.Path). Installation aborted to protect system integrity."
        }
    }
    Write-Host 'Checksum verification passed.' -ForegroundColor Green
}

# Ensure module is on PSModulePath
$moduleParent = Split-Path $dest
$currentPath = [Environment]::GetEnvironmentVariable('PSModulePath','Machine')
if ($AllUsers -and $currentPath -notlike "*$moduleParent*") {
    [Environment]::SetEnvironmentVariable('PSModulePath', "$currentPath;$moduleParent", 'Machine')
}

Write-Host "GitMe $Version installed successfully." -ForegroundColor Green
Write-Host "Import with: Import-Module GitMe" -ForegroundColor Yellow
