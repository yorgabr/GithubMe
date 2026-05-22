[CmdletBinding()]
param([string]$CurrentVersion = '0.1.0')

$latestTag = (git describe --tags --abbrev=0 2>$null)
$range = if ($latestTag) { "$latestTag..HEAD" } else { 'HEAD' }
$commits = git log $range --pretty=format:%s 2>$null
if (-not $commits) { return $CurrentVersion }

$hasBreaking = $false
$hasFeature  = $false
$hasFix      = $false

foreach ($line in $commits) {
    if ($line -match '^[a-z]+(\(.+\))?!:') { $hasBreaking = $true }
    if ($line -match 'BREAKING CHANGE')      { $hasBreaking = $true }
    if ($line -match '^feat(\(.+\))?:')     { $hasFeature  = $true }
    if ($line -match '^fix(\(.+\))?:')      { $hasFix      = $true }
}

$v = [version]$CurrentVersion
if ($hasBreaking)      { return "$($v.Major + 1).0.0" }
elseif ($hasFeature)   { return "$($v.Major).$($v.Minor + 1).0" }
elseif ($hasFix)       { return "$($v.Major).$($v.Minor).$($v.Build + 1)" }
else                   { return $CurrentVersion }
