#Requires -Version 5.1
Set-StrictMode -Version Latest

# Force TLS 1.2 and TLS 1.3 for modern API compatibility on older .NET hosts
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$script:GitMeVersion = '1.0.0'
$script:GitMeLogLevel = 'Info'

# Load helpers in deterministic alphabetical order
$scripts = Get-ChildItem -Path "$PSScriptRoot\*.ps1" -Recurse | Sort-Object FullName

foreach ($file in $scripts) {
    try { . $file.FullName }
    catch { throw "Failed to import $($file.FullName): $_" }
}

# Register tab completion once at module load
Register-GitMeArgumentCompleter

Export-ModuleMember -Function @('Invoke-Gitme', 'Get-GitmeTabCompletion') -Alias @('gitme')