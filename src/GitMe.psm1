#Requires -Version 5.1
Set-StrictMode -Version Latest

# Force TLS 1.2 for modern API compatibility on older .NET hosts
# TLS 1.3 is not available in .NET Framework 4.x used by PS 5.1, so we
# guard the assignment with a check to avoid a runtime error.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tls13 = [Net.SecurityProtocolType] | Get-Member -Static -MemberType Property |
    Where-Object { $_.Name -eq 'Tls13' }
if ($tls13) {
    [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13
}

$script:GitMeVersion = '1.0.0'
$script:GitMeLogLevel = 'Info'

# ── Load private helpers first, then public functions ────────────────────────
# We load each folder explicitly and in the correct dependency order.
# The previous approach used Get-ChildItem -Recurse from the module root, which
# caused PowerShell to re-process #Requires directives in public .ps1 files and
# trigger a second module-load attempt, breaking Pester's InModuleScope contract.
foreach ($folder in @('private', 'public')) {
    $folderPath = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path $folderPath)) { continue }

    $files = Get-ChildItem -Path $folderPath -Filter '*.ps1' -File |
        Sort-Object Name

    foreach ($file in $files) {
        try {
            . $file.FullName
        }
        catch {
            throw "Failed to import $($file.FullName): $_"
        }
    }
}

# Register tab completion once at module load
Register-GitMeArgumentCompleter

# Declare the alias explicitly so PS 5.1 exports it correctly.
# The manifest AliasesToExport entry alone is not sufficient in all PS 5.1
# hosts — Set-Alias inside the module guarantees the alias is present.
Set-Alias -Name gitme -Value Invoke-Gitme -Scope Global

Export-ModuleMember -Function @('Invoke-Gitme', 'Get-GitmeTabCompletion') -Alias @('gitme')