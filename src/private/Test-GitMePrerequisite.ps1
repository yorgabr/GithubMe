function Test-GitMePrerequisite {
    [CmdletBinding()]
    param()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { throw 'Git is not installed or not in PATH.' }
    $ver = Get-GitMeVersion
    if (-not $ver -or $ver -lt [version]'2.50.0') {
        throw "Git version $ver is below the required 2.50.0. Please upgrade Git."
    }
    Write-GitMeLog -Level Info -Message "Git $ver detected."
}