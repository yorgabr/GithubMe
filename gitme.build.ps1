#Requires -Version 5.1
#Requires -Modules @{ModuleName='InvokeBuild';ModuleVersion='5.0.0'}
<#
.SYNOPSIS
    Entry-point build script for GitMe.
    Invoke with: Invoke-Build
#>
param(
    [string]$Configuration = 'Release',
    [string]$Repository    = 'PSGallery'
)

# Delegate to the task file
. $PSScriptRoot\.build\build.tasks.ps1 @PSBoundParameters
