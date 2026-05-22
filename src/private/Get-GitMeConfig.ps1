function Get-GitMeConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key)
    $savedEA = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $value = git config $Key 2>$null
        if ($LASTEXITCODE -eq 0 -and $value) { return $value }
    }
    catch {
        Write-Verbose "Git config query failed for key '$Key': $_"
    }
    finally { $ErrorActionPreference = $savedEA }
    return ''
}