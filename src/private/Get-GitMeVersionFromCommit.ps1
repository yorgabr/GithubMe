function Get-GitMeVersionFromCommit {
    [CmdletBinding()]
    param(
        [string]$CurrentVersion = '0.1.0',

        [scriptblock]$GitInvoker = {
            param(
                [Parameter(Mandatory = $false)]
                [string[]]$Arguments
            )
            Invoke-GitMeNative -Arguments $Arguments
        }
    )

    #---
    # Get latest tag
    #---
    $describeArgs = @('describe', '--tags', '--abbrev=0')
    $latestTagResult = & $GitInvoker $describeArgs

    $latestTag = $latestTagResult.Output

    $range = if ($latestTag) { "$latestTag..HEAD" } else { 'HEAD' }

    #---
    # Get commit log
    #---
    $logArgs = @('log', $range, '--pretty=format:%B')
    $log = & $GitInvoker $logArgs

    if ($log.ExitCode -ne 0 -or -not $log.Output) {
        return $CurrentVersion
    }

    #---
    # Analyze commits
    #---
    $hasBreaking = $false
    $hasFeature = $false
    $hasFix = $false

    foreach ($line in $log.Output) {
        if ($line -match '^[a-z]+(\(.+\))?!:') { $hasBreaking = $true }
        if ($line -match 'BREAKING CHANGE') { $hasBreaking = $true }
        if ($line -match '^feat(\(.+\))?:') { $hasFeature = $true }
        if ($line -match '^fix(\(.+\))?:') { $hasFix = $true }
    }

    try { $v = [version]$CurrentVersion }
    catch { $v = [version]'0.1.0' }

    if ($hasBreaking) {
        return "$($v.Major + 1).0.0"
    }
    elseif ($hasFeature) {
        return "$($v.Major).$($v.Minor + 1).0"
    }
    elseif ($hasFix) {
        return "$($v.Major).$($v.Minor).$($v.Build + 1)"
    }
    else {
        return $CurrentVersion
    }
}
