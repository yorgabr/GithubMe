function Get-GitMeVersion {
    [CmdletBinding()]
    param()
    $result = Invoke-GitMeNative @('--version')
    if ($result.ExitCode -ne 0) { return $null }
    if ($result.Output -match '(\d+\.\d+\.\d+)') {
        return [version]$Matches[1]
    }
    return $null
}