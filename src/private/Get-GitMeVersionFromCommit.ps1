function Get-GitMeVersionFromCommit {
    <#
    .SYNOPSIS
        Determines the next SemVer version based on Conventional Commits since the latest tag.
    .DESCRIPTION
        Reads git log since the most recent tag. If a BREAKING CHANGE, ! after type, or
        'BREAKING CHANGE:' footer is found, bumps MAJOR. If 'feat:' found, bumps MINOR.
        If 'fix:' found, bumps PATCH. Otherwise returns the current tag or 0.1.0.
    #>
    [CmdletBinding()]
    param([string]$CurrentVersion = '0.1.0')

    $latestTag = (Invoke-GitMeNative @('describe', '--tags', '--abbrev=0')).Output
    $range = if ($latestTag) { "$latestTag..HEAD" } else { 'HEAD' }

    # Use %B to include commit bodies and footers where breaking changes are specified
    $log = Invoke-GitMeNative @('log', $range, '--pretty=format:%B')
    if ($log.ExitCode -ne 0 -or -not $log.Output) { return $CurrentVersion }

    $commits = $log.Output
    $hasBreaking = $false
    $hasFeature = $false
    $hasFix = $false

    foreach ($line in $commits) {
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