#Requires -Modules @{ModuleName='InvokeBuild';ModuleVersion='5.0.0'}, @{ModuleName='Pester';ModuleVersion='5.0.0'}
param(
    [string]$Configuration = 'Release',
    [string]$Repository    = 'PSGallery'
)

$ProjectRoot  = Split-Path -Parent $PSScriptRoot
$SrcRoot      = Join-Path $ProjectRoot 'src'
$TestsRoot    = Join-Path $ProjectRoot 'tests'
$OutRoot      = Join-Path $ProjectRoot 'out'
$DocsRoot     = Join-Path $ProjectRoot 'docs'
$ManifestRoot = Join-Path $ProjectRoot 'manifests'

# --- Version resolution ------------------------------------------------------
$script:ModuleVersion = (Import-PowerShellDataFile (Join-Path $SrcRoot 'GitMe.psd1')).ModuleVersion

# --- Entry task --------------------------------------------------------------
task . Clean, Format, Analyze, Security, Test, Build, Package

# --- Clean -------------------------------------------------------------------
task Clean {
    Remove-Item $OutRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null
}

# --- Format ------------------------------------------------------------------
# Formats only .ps1 and .psm1 files (NOT .psd1) using the full formatting ruleset.
# Formatting .psd1 files triggers a known PSScriptAnalyzer bug with nested hashtables.
task Format {
    $settings = Join-Path $PSScriptRoot 'pssa-settings.psd1'
    $files = Get-ChildItem -Path $SrcRoot -Include '*.ps1', '*.psm1' -Recurse
    foreach ($file in $files) {
        $content   = Get-Content -Raw -Path $file.FullName
        $formatted = Invoke-Formatter -ScriptDefinition $content -Settings $settings
        if ($formatted -ne $content) {
            Set-Content -Path $file.FullName -Value $formatted -Encoding UTF8 -NoNewline
            Write-Build Yellow "Formatted $($file.Name)"
        }
    }
}

# --- Lint / Static Analysis --------------------------------------------------
# Uses a lint-only settings file (no formatting rules) and targets only .ps1/.psm1
# files explicitly, avoiding the PSScriptAnalyzer enumeration bug on .psd1 files.
task Analyze {
    $settings = Join-Path $PSScriptRoot 'pssa-lint.psd1'

    # Collect .ps1 and .psm1 files explicitly instead of passing the directory,
    # so PSScriptAnalyzer never attempts to parse .psd1 manifest files.
    $files = Get-ChildItem -Path $SrcRoot -Include '*.ps1', '*.psm1' -Recurse |
        Select-Object -ExpandProperty FullName

    if (-not $files) {
        Write-Build Green "No PowerShell script files found to analyze."
        return
    }

    $results = @()
    foreach ($file in $files) {
        $fileResults = Invoke-ScriptAnalyzer `
            -Path $file `
            -Settings $settings `
            -Severity @('Error', 'Warning')
        if ($fileResults) {
            $results += $fileResults
        }
    }

    if ($results) {
        $results | Format-Table -AutoSize
        throw "PSScriptAnalyzer found $($results.Count) issues."
    }
    Write-Build Green "PSScriptAnalyzer passed."
}

# --- Security Scan -----------------------------------------------------------
task Security {
    $secRules = Get-ScriptAnalyzerRule |
        Where-Object { $_.RuleName -match 'Credential|Password|SecureString|Injection|Unsafe|Shell' }

    $files = Get-ChildItem -Path $SrcRoot -Include '*.ps1', '*.psm1' -Recurse |
        Select-Object -ExpandProperty FullName

    if (-not $files) {
        Write-Build Green "No PowerShell script files found for security scan."
        return
    }

    $secResults = @()
    foreach ($file in $files) {
        $fileResults = Invoke-ScriptAnalyzer `
            -Path $file `
            -IncludeRule $secRules.RuleName
        if ($fileResults) {
            $secResults += $fileResults
        }
    }

    if ($secResults) {
        $secResults | Format-Table -AutoSize
        throw "Security scan found $($secResults.Count) issues."
    }
    Write-Build Green "Security scan passed."
}

# --- Test --------------------------------------------------------------------
task Test {
    $config = New-PesterConfiguration
    $config.Run.Path                           = $TestsRoot
    $config.CodeCoverage.Enabled               = $true
    $config.CodeCoverage.Path                  = "$SrcRoot\*.ps1", "$SrcRoot\*\*.ps1"
    $config.CodeCoverage.OutputFormat          = 'JaCoCo'
    $config.CodeCoverage.OutputPath            = "$OutRoot\coverage.xml"
    $config.CodeCoverage.CoveragePercentTarget = 80
    $config.TestResult.Enabled                 = $true
    $config.TestResult.OutputPath              = "$OutRoot\test-results.xml"
    $config.Output.Verbosity                   = 'Detailed'

    $result = Invoke-Pester -Configuration $config

    if ($result.FailedCount -gt 0) {
        throw "$($result.FailedCount) test(s) failed."
    }

    # ── Parse JaCoCo XML for coverage percentage ──────────────────────────
    [xml]$cov = Get-Content "$OutRoot\coverage.xml"

    $counter = $cov.report.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
    $covered = [int]$counter.covered
    $missed  = [int]$counter.missed
    $total   = $covered + $missed

    $pct = if ($total -gt 0) { [math]::Round(($covered / $total) * 100, 2) } else { 100 }
    Write-Build Cyan "Code coverage: $pct % ($covered / $total instructions)"

    $minimumCoverage = 80
    if ($pct -lt $minimumCoverage) {
        throw "Coverage $pct % is below the required $minimumCoverage %."
    }
}

# --- Build -------------------------------------------------------------------
task Build {
    $moduleOut = Join-Path $OutRoot "GitMe\$($script:ModuleVersion)"
    New-Item -ItemType Directory -Path $moduleOut -Force | Out-Null
    Copy-Item -Path "$SrcRoot\*" -Destination $moduleOut -Recurse -Force

    # Keep manifest version in sync
    $manifestPath = Join-Path $moduleOut 'GitMe.psd1'
    (Get-Content $manifestPath -Raw) `
        -replace "ModuleVersion\s*=\s*'[^']+'", "ModuleVersion = '$($script:ModuleVersion)'" |
        Set-Content $manifestPath -Encoding UTF8

    # Generate SHA-256 checksum manifest
    $hashes = Get-ChildItem $moduleOut -Recurse -File |
        Get-FileHash -Algorithm SHA256 |
        Select-Object Hash, @{
            N = 'Path'
            E = { $_.Path.Replace($moduleOut, '.').TrimStart('\') }
        }
    $hashes | ConvertTo-Json | Set-Content (Join-Path $OutRoot 'checksums.json') -Encoding UTF8

    Write-Build Green "Built module version $($script:ModuleVersion)"
}

# --- Version Bump (Conventional Commits) -------------------------------------
task VersionBump {
    $bumped = & (Join-Path $PSScriptRoot 'version.ps1') -CurrentVersion $script:ModuleVersion
    if ($bumped -ne $script:ModuleVersion) {
        Write-Build Yellow "Bumping version: $($script:ModuleVersion) -> $bumped"
        $script:ModuleVersion = $bumped
        $mf = Join-Path $SrcRoot 'GitMe.psd1'
        (Get-Content $mf -Raw) `
            -replace "ModuleVersion\s*=\s*'[^']+'", "ModuleVersion = '$bumped'" |
            Set-Content $mf -Encoding UTF8
    }
}

# --- Package -----------------------------------------------------------------
task Package -Jobs Build, {
    $moduleOut = Join-Path $OutRoot "GitMe\$($script:ModuleVersion)"

    # ZIP for Scoop / manual install
    $nugetOut = Join-Path $OutRoot 'nuget'
    New-Item -ItemType Directory -Path $nugetOut -Force | Out-Null
    Compress-Archive -Path "$moduleOut\*" `
        -DestinationPath (Join-Path $nugetOut "GitMe.$($script:ModuleVersion).zip") -Force

    # Winget manifest
    $wingetDir = Join-Path $OutRoot 'winget'
    New-Item -ItemType Directory -Path $wingetDir -Force | Out-Null
    $wingetSrc = Join-Path $ManifestRoot 'winget\GitMe.yaml'
    Copy-Item $wingetSrc $wingetDir
    (Get-Content (Join-Path $wingetDir 'GitMe.yaml') -Raw) `
        -replace '{{VERSION}}', $script:ModuleVersion |
        Set-Content (Join-Path $wingetDir 'GitMe.yaml') -Encoding UTF8

    # Scoop manifest
    $scoopDir = Join-Path $OutRoot 'scoop'
    New-Item -ItemType Directory -Path $scoopDir -Force | Out-Null
    $scoopSrc = Join-Path $ManifestRoot 'scoop\gitme.json'
    Copy-Item $scoopSrc $scoopDir
    (Get-Content (Join-Path $scoopDir 'gitme.json') -Raw) `
        -replace '{{VERSION}}', $script:ModuleVersion |
        Set-Content (Join-Path $scoopDir 'gitme.json') -Encoding UTF8

    # irm | iex installer
    $installScript = Join-Path $OutRoot 'install.ps1'
    Copy-Item (Join-Path $ProjectRoot 'scripts\install.ps1') $installScript
    (Get-Content $installScript -Raw) `
        -replace '{{VERSION}}', $script:ModuleVersion |
        Set-Content $installScript -Encoding UTF8

    Write-Build Green "Packaging complete."
}

# --- Publish -----------------------------------------------------------------
task Publish -Jobs Package, {
    param([string]$NuGetApiKey)
    if (-not $NuGetApiKey) { throw 'NuGetApiKey is required for publish.' }
    $moduleOut = Join-Path $OutRoot "GitMe\$($script:ModuleVersion)"
    Publish-Module -Path $moduleOut -Repository $Repository -NuGetApiKey $NuGetApiKey -Force
    Write-Build Green "Published to $Repository."
}
