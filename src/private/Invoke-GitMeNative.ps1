function Invoke-GitMeNative {
    <#
    .SYNOPSIS
        Invokes git with stderr merged into stdout, immune to PS 5.1 NativeCommandError.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments
    )
    $savedEA = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedEA
    }
    # Flatten ErrorRecords to strings for PS 5.1 compatibility
    $flat = $output | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ }
    }
    return [pscustomobject]@{ Output = $flat; ExitCode = $exitCode }
}