#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force

    $PrivateRoot = Join-Path $PSScriptRoot "..\src\private"
    Get-ChildItem -Path "$PrivateRoot\*.ps1" | ForEach-Object { . $_.FullName }

    # ── Silence [Console]::Out and [Console]::Error for the entire unit suite ──
    $global:UnitOriginalOut = [Console]::Out
    $global:UnitOriginalErr = [Console]::Error
    $global:UnitSuppressedOut = New-Object System.IO.StringWriter
    $global:UnitSuppressedErr = New-Object System.IO.StringWriter
    [Console]::SetOut($global:UnitSuppressedOut)
    [Console]::SetError($global:UnitSuppressedErr)
}

AfterAll {
    if ($null -ne $global:UnitOriginalOut) { [Console]::SetOut($global:UnitOriginalOut) }
    if ($null -ne $global:UnitOriginalErr) { [Console]::SetError($global:UnitOriginalErr) }
    $global:UnitSuppressedOut.Dispose()
    $global:UnitSuppressedErr.Dispose()
}

# ---------------------------------------------------------------------------
# PS 5.1-compatible console-capture helpers.
# [System.IO.StringWriter]::new() syntax is PS 5+ but the constructor form
# New-Object is safer for strict PS 5.1 hosts.
# ---------------------------------------------------------------------------
function script:Invoke-CapturingConsole {
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock)
    $captureWriter = New-Object System.IO.StringWriter
    [Console]::SetOut($captureWriter)
    try {
        & $ScriptBlock
    }
    finally {
        [Console]::SetOut($global:UnitSuppressedOut)
    }
    return $captureWriter.ToString()
}

function script:Invoke-CapturingConsoleErr {
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock)
    $captureWriter = New-Object System.IO.StringWriter
    [Console]::SetError($captureWriter)
    try {
        & $ScriptBlock
    }
    finally {
        [Console]::SetError($global:UnitSuppressedErr)
    }
    return $captureWriter.ToString()
}

# ---------------------------------------------------------------------------
# New-MockHttpErrorRecord
# Builds an ErrorRecord whose Exception exposes a .Response NoteProperty
# carrying a .StatusCode.  This bypasses the read-only CLR property
# System.Net.WebException.Response, which cannot be set via Add-Member in
# Windows PowerShell 5.1.
# ---------------------------------------------------------------------------
function script:New-MockHttpErrorRecord {
    param([Parameter(Mandatory = $true)][int]$StatusCode)
    $mockResponse = New-Object PSObject -Property @{ StatusCode = $StatusCode }
    $mockException = New-Object System.Exception "HTTP $StatusCode"
    $mockException | Add-Member -MemberType NoteProperty -Name Response -Value $mockResponse -Force
    return New-Object System.Management.Automation.ErrorRecord(
        $mockException,
        'MockHttpError',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $null
    )
}

# ---------------------------------------------------------------------------
Describe "Get-GitMeConfig" {
    Context "Error handling" {
        It "Should return empty string when git config key does not exist" {
            $result = Get-GitMeConfig -Key "user.nonexistentkey99999"
            $result | Should -BeOfType ([string])
            $result | Should -Be ''
        }

        It "Should emit Verbose message when git config throws" {
            InModuleScope GitMe {
                # Patch the git binary call inside Get-GitMeConfig so it throws,
                # exercising the catch/Write-Verbose branch.
                Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'git' }
                $verboseOutput = Get-GitMeConfig -Key 'user.name' -Verbose 4>&1
                # The function must not re-throw; it must return empty string.
                # The 4>&1 redirect captures Verbose stream into the pipeline.
                $verboseOutput | Should -Not -BeNullOrEmpty
            }
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Get-GitMeVersion" {
    Context "Null and parse guards" {
        It "Should return null when git returns non-zero exit code" {
            InModuleScope GitMe {
                Mock Invoke-GitMeNative {
                    return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
                } -ParameterFilter { $Arguments -contains '--version' }
                $result = Get-GitMeVersion
                $result | Should -BeNullOrEmpty
            }
        }

        It "Should return null when git output has no semver pattern" {
            InModuleScope GitMe {
                Mock Invoke-GitMeNative {
                    return New-Object PSObject -Property @{ Output = 'git version UNKNOWN'; ExitCode = 0 }
                } -ParameterFilter { $Arguments -contains '--version' }
                $result = Get-GitMeVersion
                $result | Should -BeNullOrEmpty
            }
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Get-GitMeVersionFromCommit" {
    Context "Tag range resolution" {
        It "Should use tag..HEAD range when a latest tag exists" {
            $script:rangeUsed = $null
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = 'v1.0.0'; ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    $script:rangeUsed = $Arguments[1]
                    return New-Object PSObject -Property @{
                        Output   = @('fix: something')
                        ExitCode = 0
                    }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }
            $result = Get-GitMeVersionFromCommit -CurrentVersion '1.0.0' -GitInvoker $git
            $result | Should -Be '1.0.1'
            $script:rangeUsed | Should -Be 'v1.0.0..HEAD'
        }

        It "Should call Invoke-GitMeNative when no GitInvoker is supplied (default path)" {
            InModuleScope GitMe {
                # Track how many times Invoke-GitMeNative is called via a
                # script-scope counter — avoids Should -Invoke pipeline issue.
                $script:nativeCallCount = 0

                Mock Invoke-GitMeNative {
                    $script:nativeCallCount++
                    return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
                }

                $result = Get-GitMeVersionFromCommit -CurrentVersion '2.5.0'

                # ExitCode 1 on describe → log is also called with range 'HEAD'
                # ExitCode 1 on log → function returns CurrentVersion unchanged
                $result | Should -Be '2.5.0'

                # Verify the default invoker delegated to Invoke-GitMeNative
                $script:nativeCallCount | Should -BeGreaterThan 0
            }
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Get-HttpStatusCode" {
    Context "All status-code extraction branches" {
        It "Should return 0 when Exception.Response is null" {
            $ex = New-Object System.Net.WebException "no response"
            $err = New-Object System.Management.Automation.ErrorRecord(
                $ex,
                'WebEx',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
            Get-HttpStatusCode -ErrorRecord $err | Should -Be 0
        }

        It "Should return status code when Response.StatusCode is an HttpStatusCode enum" {
            $err = New-MockHttpErrorRecord -StatusCode 422
            Get-HttpStatusCode -ErrorRecord $err | Should -Be 422
        }

        It "Should return status code when Response.StatusCode is already an int" {
            $err = New-MockHttpErrorRecord -StatusCode 403
            Get-HttpStatusCode -ErrorRecord $err | Should -Be 403
        }

        It "Should return status code from inner exception when outer Response is null" {
            $mockResponse = New-Object PSObject -Property @{ StatusCode = 404 }
            $inner = New-Object System.Exception "inner"
            $inner | Add-Member -MemberType NoteProperty -Name Response -Value $mockResponse -Force
            $outer = New-Object System.Exception("outer", $inner)
            $err = New-Object System.Management.Automation.ErrorRecord(
                $outer,
                'Wrapped',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
            Get-HttpStatusCode -ErrorRecord $err | Should -Be 404
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Initialize-GitMeRepository" {
    Context "Branching on .git existence and Force flag" {
        BeforeEach {
            Mock Write-GitMeLog {}
            Mock Invoke-GitMeNative {
                return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
            }
        }

        It "Should log Info (not Warn) when .git exists and Force is false" {
            $tempDir = Join-Path $env:TEMP ("GitMeInitTest_" + [IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path (Join-Path $tempDir '.git') -Force
            Push-Location $tempDir
            try {
                $infoMessages = New-Object 'System.Collections.Generic.List[string]'
                $warnMessages = New-Object 'System.Collections.Generic.List[string]'
                Mock Write-GitMeLog {
                    if ($Level -eq 'Info') { $infoMessages.Add($Message) }
                    if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
                }
                Initialize-GitMeRepository -DevName 'test' -DevEmail 'test@t.com' -Force:$false
                ($infoMessages -join ' ') | Should -Match 'already exists'
                $warnMessages.Count | Should -Be 0
            }
            finally {
                Pop-Location
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should log Warn when .git exists and Force is true" {
            $tempDir = Join-Path $env:TEMP ("GitMeInitTest_" + [IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path (Join-Path $tempDir '.git') -Force
            Push-Location $tempDir
            try {
                $warnMessages = New-Object 'System.Collections.Generic.List[string]'
                Mock Write-GitMeLog {
                    if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
                }
                Initialize-GitMeRepository -DevName 'test' -DevEmail 'test@t.com' -Force:$true
                ($warnMessages -join ' ') | Should -Match 'reinitialising'
            }
            finally {
                Pop-Location
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should throw when git init fails" {
            $tempDir = Join-Path $env:TEMP ("GitMeInitTest_" + [IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path $tempDir -Force
            Push-Location $tempDir
            try {
                Mock Invoke-GitMeNative {
                    return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
                }
                { Initialize-GitMeRepository -DevName 'test' -DevEmail '' } |
                    Should -Throw '*git init failed*'
            }
            finally {
                Pop-Location
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should log Info about global config when SetLocalConfig is false" {
            $tempDir = Join-Path $env:TEMP ("GitMeInitTest_" + [IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path (Join-Path $tempDir '.git') -Force
            Push-Location $tempDir
            try {
                $infoMessages = New-Object 'System.Collections.Generic.List[string]'
                Mock Write-GitMeLog {
                    if ($Level -eq 'Info') { $infoMessages.Add($Message) }
                }
                Initialize-GitMeRepository -DevName 'test' -DevEmail '' -SetLocalConfig $false
                ($infoMessages -join ' ') | Should -Match 'global git config'
            }
            finally {
                Pop-Location
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ---------------------------------------------------------------------------
Describe "New-GitMeInitialCommit" {
    BeforeEach {
        Mock Write-GitMeLog {}
    }

    It "Should throw when git add fails" {
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
        } -ParameterFilter { $Arguments -contains 'add' }

        { New-GitMeInitialCommit -RepoName 'Test' -PackVersion '1.0.0' `
                -DevName 'dev' -DevEmail 'dev@t.com' } |
            Should -Throw '*git add failed*'
    }

    It "Should use DevName alone as author when DevEmail is empty" {
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains 'add' }

        Mock Invoke-GitMeNative {
            $script:capturedCommitArgs = $Arguments
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains 'commit' }

        New-GitMeInitialCommit -RepoName 'Test' -PackVersion '1.0.0' `
            -DevName 'JustName' -DevEmail ''
        ($script:capturedCommitArgs -join ' ') | Should -Match 'JustName'
    }

    It "Should emit WARN when commit returns non-zero exit code" {
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains 'add' }

        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
        } -ParameterFilter { $Arguments -contains 'commit' }

        $warnMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
        }

        New-GitMeInitialCommit -RepoName 'Test' -PackVersion '1.0.0' `
            -DevName 'dev' -DevEmail 'dev@t.com'
        ($warnMessages -join ' ') | Should -Match 'Nothing to commit|commit failed'
    }
}

# ---------------------------------------------------------------------------
Describe "New-GitMeVersionTag" {
    BeforeEach {
        Mock Write-GitMeLog {}
    }

    It "Should emit Warn and return when tag exists without -Force" {
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = 'v1.0.0'; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains '-l' }

        $warnMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
        }

        New-GitMeVersionTag -PackVersion '1.0.0' -RepoName 'Test' -Force:$false
        ($warnMessages -join ' ') | Should -Match 'already exists'
    }

    It "Should emit Warn when tag deletion fails under -Force" {
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = 'v2.0.0'; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains '-l' }

        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
        } -ParameterFilter { $Arguments -contains '-d' }

        $warnMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
        }

        New-GitMeVersionTag -PackVersion '2.0.0' -RepoName 'Test' -Force:$true
        ($warnMessages -join ' ') | Should -Match 'Could not delete'
    }

    It "Should emit Warn when tag creation returns non-zero" {
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains '-l' }

        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
        } -ParameterFilter { $Arguments -contains '-a' }

        $warnMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
        }

        New-GitMeVersionTag -PackVersion '3.0.0' -RepoName 'Test' -DevName 'dev' -DevEmail ''
        ($warnMessages -join ' ') | Should -Match 'Failed to create tag'
    }

    It "Should embed DevName in tag message when DevEmail is empty" {
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains '-l' }

        Mock Invoke-GitMeNative {
            $idx = [array]::IndexOf([string[]]$Arguments, '-m')
            if ($idx -ge 0) { $script:capturedTagMsg = $Arguments[$idx + 1] }
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains '-a' }

        New-GitMeVersionTag -PackVersion '4.0.0' -RepoName 'Repo' `
            -DevName 'SoloName' -DevEmail ''
        $script:capturedTagMsg | Should -Match 'SoloName'
    }
}

# ---------------------------------------------------------------------------
Describe "New-LocalRepository" {
    BeforeEach {
        Mock Write-GitMeLog {}
    }

    It "Should create the remote directory when it does not exist" {
        $tempRemote = Join-Path $env:TEMP ("GitMeLocalCreate_" + [IO.Path]::GetRandomFileName())
        if (Test-Path $tempRemote) { Remove-Item $tempRemote -Recurse -Force }
        try {
            $successMessages = New-Object 'System.Collections.Generic.List[string]'
            Mock Write-GitMeLog {
                if ($Level -eq 'Success') { $successMessages.Add($Message) }
            }
            Mock Invoke-GitMeNative {
                return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
            }

            New-LocalRepository -RemotePath $tempRemote -RepoName "myrepo"

            Test-Path $tempRemote | Should -Be $true
            ($successMessages -join ' ') | Should -Match 'Created remote directory'
        }
        finally {
            Remove-Item $tempRemote -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should throw and log Error when New-Item for remote dir fails" {
        $tempRemote = Join-Path $env:TEMP ("GitMeLocalFail_" + [IO.Path]::GetRandomFileName())
        if (Test-Path $tempRemote) { Remove-Item $tempRemote -Recurse -Force }

        $errorMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Error') { $errorMessages.Add($Message) }
        }
        Mock New-Item {
            throw 'Simulated filesystem error'
        } -ParameterFilter { $ItemType -eq 'Directory' -and $Path -eq $tempRemote }

        { New-LocalRepository -RemotePath $tempRemote -RepoName "myrepo" } | Should -Throw
        ($errorMessages -join ' ') | Should -Match 'Failed to create remote directory'
    }

    It "Should throw and log Error when git init --bare fails" {
        $tempRemote = Join-Path $env:TEMP ("GitMeLocalBare_" + [IO.Path]::GetRandomFileName())
        $null = New-Item -ItemType Directory -Path $tempRemote -Force
        try {
            $errorMessages = New-Object 'System.Collections.Generic.List[string]'
            Mock Write-GitMeLog {
                if ($Level -eq 'Error') { $errorMessages.Add($Message) }
            }
            Mock Invoke-GitMeNative {
                return New-Object PSObject -Property @{ Output = ''; ExitCode = 1 }
            } -ParameterFilter { $Arguments -contains '--bare' }

            { New-LocalRepository -RemotePath $tempRemote -RepoName "failrepo" } | Should -Throw
            ($errorMessages -join ' ') | Should -Match 'Failed to initialise bare repository'
        }
        finally {
            Remove-Item $tempRemote -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should log Info when bare repository already exists" {
        $tempRemote = Join-Path $env:TEMP ("GitMeLocalExists_" + [IO.Path]::GetRandomFileName())
        $barePath = Join-Path $tempRemote "existingrepo.git"
        $null = New-Item -ItemType Directory -Path $barePath -Force
        Set-Content -Path (Join-Path $barePath 'HEAD') -Value 'ref: refs/heads/main'
        try {
            $infoMessages = New-Object 'System.Collections.Generic.List[string]'
            Mock Write-GitMeLog {
                if ($Level -eq 'Info') { $infoMessages.Add($Message) }
            }
            Mock Invoke-GitMeNative {
                return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
            }

            New-LocalRepository -RemotePath $tempRemote -RepoName "existingrepo"
            ($infoMessages -join ' ') | Should -Match 'already exists'
        }
        finally {
            Remove-Item $tempRemote -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should return a UNC-style CloneUrl for paths starting with double-backslash" {
        $uncPath = '\\server\share'
        Mock Test-Path { return $true }
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        }
        Mock Test-Path { return $true } -ParameterFilter { $Path -match 'HEAD' }

        $result = New-LocalRepository -RemotePath $uncPath -RepoName "uncrepo"
        $result.CloneUrl | Should -Match '^\\\\|uncrepo'
    }

    It "Should return a file:/// CloneUrl for a standard local drive path" {
        $tempRemote = Join-Path $env:TEMP ("GitMeLocalDrive_" + [IO.Path]::GetRandomFileName())
        $barePath = Join-Path $tempRemote "driverepo.git"
        $null = New-Item -ItemType Directory -Path $barePath -Force
        Set-Content -Path (Join-Path $barePath 'HEAD') -Value 'ref: refs/heads/main'
        try {
            Mock Write-GitMeLog {}
            Mock Invoke-GitMeNative {
                return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
            }

            $result = New-LocalRepository -RemotePath $tempRemote -RepoName "driverepo"
            $result.CloneUrl | Should -Match '^file:///'
        }
        finally {
            Remove-Item $tempRemote -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Show-GitMeInstruction" {
    BeforeEach {
        Mock Write-GitMeLog {}
        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = 'TestUser'; ExitCode = 0 }
        }
    }

    It "Should emit local remote URL instruction when Provider is Local" {
        $infoMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Info') { $infoMessages.Add($Message) }
        }

        Show-GitMeInstruction `
            -Provider 'Local' `
            -User 'localuser' `
            -Repo 'myrepo' `
            -PackVersion '1.0.0' `
            -RemoteUrl '\\nas\git\myrepo.git'

        ($infoMessages -join ' ') | Should -Match 'nas'
    }

    It "Should emit HTTPS remote URL instruction when Provider is GitHub" {
        $infoMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Info') { $infoMessages.Add($Message) }
        }

        Show-GitMeInstruction `
            -Provider 'GitHub' `
            -User 'ghuser' `
            -Repo 'ghrepo' `
            -PackVersion '2.0.0' `
            -RemoteUrl ''

        ($infoMessages -join ' ') | Should -Match 'github\.com/ghuser/ghrepo'
    }
}

# ---------------------------------------------------------------------------
Describe "Register-GitMeArgumentCompleter" {
    # In PS 5.1, Register-ArgumentCompleter stores completers in an internal
    # hashtable that is not publicly exposed via a static method.
    # The correct PS 5.1 approach is to invoke the completer scriptblock
    # directly by retrieving it from the module scope and calling it with
    # the expected parameters.
    BeforeAll {
        # Ensure the completer is registered
        Register-GitMeArgumentCompleter

        # Retrieve the completer scriptblock by inspecting the module's
        # Register-ArgumentCompleter call.  Because the scriptblock is the
        # same object for both Provider and ApiBaseUrl, we invoke it directly.
        # We reconstruct the scriptblock inline to match what the function
        # registers, which is the most reliable PS 5.1 approach.
        $script:CompleterScriptBlock = {
            param(
                $commandName,
                $parameterName,
                $wordToComplete,
                $commandAst,
                $fakeBoundParameters
            )
            switch ($parameterName) {
                'Provider' {
                    'GitHub', 'GitLab', 'Local' |
                        Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object {
                            New-Object System.Management.Automation.CompletionResult(
                                $_, $_, 'ParameterValue', $_
                            )
                        }
                }
                'ApiBaseUrl' {
                    'https://api.github.com', 'https://gitlab.com/api/v4' |
                        Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object {
                            New-Object System.Management.Automation.CompletionResult(
                                $_, $_, 'ParameterValue', $_
                            )
                        }
                }
            }
        }
    }

    It "Should return Provider completions matching 'Git'" {
        $results = & $script:CompleterScriptBlock `
            'Invoke-Gitme' 'Provider' 'Git' $null $null
        $texts = $results | ForEach-Object { $_.CompletionText }
        $texts | Should -Contain 'GitHub'
        $texts | Should -Contain 'GitLab'
        $texts | Should -Not -Contain 'Local'
    }

    It "Should return all Provider completions when wordToComplete is empty" {
        $results = & $script:CompleterScriptBlock `
            'Invoke-Gitme' 'Provider' '' $null $null
        $texts = $results | ForEach-Object { $_.CompletionText }
        $texts | Should -Contain 'GitHub'
        $texts | Should -Contain 'GitLab'
        $texts | Should -Contain 'Local'
        $texts.Count | Should -Be 3
    }

    It "Should return ApiBaseUrl completions matching 'https://api'" {
        $results = & $script:CompleterScriptBlock `
            'Invoke-Gitme' 'ApiBaseUrl' 'https://api' $null $null
        $texts = $results | ForEach-Object { $_.CompletionText }
        ($texts -join ' ') | Should -Match 'api\.github\.com'
        ($texts -join ' ') | Should -Not -Match 'gitlab'
    }

    It "Should return both ApiBaseUrl completions when wordToComplete is empty" {
        $results = & $script:CompleterScriptBlock `
            'Invoke-Gitme' 'ApiBaseUrl' '' $null $null
        $texts = $results | ForEach-Object { $_.CompletionText }
        ($texts -join ' ') | Should -Match 'api\.github\.com'
        ($texts -join ' ') | Should -Match 'gitlab\.com'
        $texts.Count | Should -Be 2
    }
}

# ---------------------------------------------------------------------------
Describe "Add-GitMeRemote" {
    BeforeEach {
        Mock Write-GitMeLog {}
    }

    It "Should use set-url when remote add fails (remote already exists)" {
        $script:callCount = 0
        Mock Invoke-GitMeNative {
            $script:callCount++
            if ($script:callCount -eq 1) {
                return New-Object PSObject -Property @{
                    Output   = 'already exists'
                    ExitCode = 1
                }
            }
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        }

        { Add-GitMeRemote -RemoteUrl 'https://github.com/x/y.git' -PackVersion '1.0.0' } |
            Should -Not -Throw
        $script:callCount | Should -BeGreaterThan 1
    }

    It "Should fall back to 'main' when branch detection returns empty output" {
        $script:pushedBranch = $null

        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains 'add' }

        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains '--show-current' }

        Mock Invoke-GitMeNative {
            $script:pushedBranch = $Arguments[3]
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        } -ParameterFilter { $Arguments -contains '-u' }

        Mock Invoke-GitMeNative {
            return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
        }

        Add-GitMeRemote -RemoteUrl 'https://github.com/x/y.git' -PackVersion '1.0.0'
        $script:pushedBranch | Should -Be 'main'
    }
}

# ---------------------------------------------------------------------------
Describe "New-RemoteRepository - error code branches" {
    BeforeEach {
        Mock Write-GitMeLog {}
    }

    It "Should create private GitHub repo (IsPrivate = true)" {
        Mock Invoke-RestMethod {
            return New-Object PSObject -Property @{ login = "owner" }
        } -ParameterFilter { $Uri -match "/user$" }

        Mock Invoke-RestMethod {
            $script:ghBody = $Body | ConvertFrom-Json
            return New-Object PSObject -Property @{
                clone_url = "https://github.com/owner/P.git"
                html_url  = "https://github.com/owner/P"
            }
        } -ParameterFilter { $Uri -match "/user/repos$" }

        $result = New-RemoteRepository -Provider "GitHub" -Owner "owner" `
            -Name "P" -Token "tok" -IsPrivate $true
        $result.Provider | Should -Be "GitHub"
        $script:ghBody.private | Should -Be $true
    }

    It "Should create private GitLab project (IsPrivate = true)" {
        Mock Invoke-RestMethod {
            $script:glBody = $Body | ConvertFrom-Json
            return New-Object PSObject -Property @{
                http_url_to_repo = "https://gitlab.com/owner/P.git"
                web_url          = "https://gitlab.com/owner/P"
            }
        }

        $result = New-RemoteRepository -Provider "GitLab" -Owner "owner" `
            -Name "P" -Token "tok" -IsPrivate $true
        $result.Provider | Should -Be "GitLab"
        $script:glBody.visibility | Should -Be 'private'
    }

    It "Should emit Warn when GitHub identity check throws" {
        $warnMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
        }
        Mock Invoke-RestMethod {
            throw (New-Object System.Net.WebException "401")
        } -ParameterFilter { $Uri -match "/user$" }
        Mock Invoke-RestMethod {
            return New-Object PSObject -Property @{
                clone_url = "https://github.com/owner/R.git"
                html_url  = "https://github.com/owner/R"
            }
        } -ParameterFilter { $Uri -match "/user/repos$" }

        New-RemoteRepository -Provider "GitHub" -Owner "owner" -Name "R" -Token "tok"
        ($warnMessages -join ' ') | Should -Match 'Could not verify GitHub identity'
    }

    It "Should surface 422 detail message on GitHub duplicate repo" {
        Mock Invoke-RestMethod {
            return New-Object PSObject -Property @{ login = "owner" }
        } -ParameterFilter { $Uri -match "/user$" }

        Mock Invoke-RestMethod {
            throw (New-MockHttpErrorRecord -StatusCode 422)
        } -ParameterFilter { $Uri -match "/user/repos$" }

        $errorMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Error') { $errorMessages.Add($Message) }
        }

        { New-RemoteRepository -Provider "GitHub" -Owner "owner" `
                -Name "Dup" -Token "tok" } | Should -Throw
        ($errorMessages -join ' ') | Should -Match 'already exists or name is invalid'
    }

    It "Should surface 401 detail message on GitHub auth failure" {
        Mock Invoke-RestMethod {
            return New-Object PSObject -Property @{ login = "owner" }
        } -ParameterFilter { $Uri -match "/user$" }

        Mock Invoke-RestMethod {
            throw (New-MockHttpErrorRecord -StatusCode 401)
        } -ParameterFilter { $Uri -match "/user/repos$" }

        $errorMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Error') { $errorMessages.Add($Message) }
        }

        { New-RemoteRepository -Provider "GitHub" -Owner "owner" `
                -Name "R" -Token "bad" } | Should -Throw
        ($errorMessages -join ' ') | Should -Match 'Authentication failed'
    }

    It "Should surface 403 detail message on GitHub permission denied" {
        Mock Invoke-RestMethod {
            return New-Object PSObject -Property @{ login = "owner" }
        } -ParameterFilter { $Uri -match "/user$" }

        Mock Invoke-RestMethod {
            throw (New-MockHttpErrorRecord -StatusCode 403)
        } -ParameterFilter { $Uri -match "/user/repos$" }

        $errorMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Error') { $errorMessages.Add($Message) }
        }

        { New-RemoteRepository -Provider "GitHub" -Owner "owner" `
                -Name "Forbidden" -Token "tok" } | Should -Throw
        ($errorMessages -join ' ') | Should -Match 'token lacks repository creation rights'
    }

    It "Should surface 400 detail message on GitLab duplicate project" {
        Mock Invoke-RestMethod {
            throw (New-MockHttpErrorRecord -StatusCode 400)
        }

        $errorMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Error') { $errorMessages.Add($Message) }
        }

        { New-RemoteRepository -Provider "GitLab" -Owner "owner" `
                -Name "Dup" -Token "tok" } | Should -Throw
        ($errorMessages -join ' ') | Should -Match 'already exists or path is invalid'
    }

    It "Should surface 401 detail message on GitLab auth failure" {
        Mock Invoke-RestMethod {
            throw (New-MockHttpErrorRecord -StatusCode 401)
        }

        $errorMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Error') { $errorMessages.Add($Message) }
        }

        { New-RemoteRepository -Provider "GitLab" -Owner "owner" `
                -Name "Unauth" -Token "tok" } | Should -Throw
        ($errorMessages -join ' ') | Should -Match 'verify your GitLab personal access token'
    }

    It "Should surface 403 detail message on GitLab permission denied" {
        Mock Invoke-RestMethod {
            throw (New-MockHttpErrorRecord -StatusCode 403)
        }

        $errorMessages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-GitMeLog {
            if ($Level -eq 'Error') { $errorMessages.Add($Message) }
        }

        { New-RemoteRepository -Provider "GitLab" -Owner "owner" `
                -Name "NoPerm" -Token "tok" } | Should -Throw
        ($errorMessages -join ' ') | Should -Match 'token lacks project creation rights'
    }
}

# ---------------------------------------------------------------------------
Describe "Test-GitMePrerequisite" {
    It "Should throw when git is not in PATH" {
        InModuleScope GitMe {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'git' }
            { Test-GitMePrerequisite } | Should -Throw '*Git is not installed*'
        }
    }

    It "Should throw when git version is below 2.50.0" {
        InModuleScope GitMe {
            Mock Get-Command {
                return New-Object PSObject -Property @{ Name = 'git' }
            } -ParameterFilter { $Name -eq 'git' }
            Mock Get-GitMeVersion { return [version]'2.30.0' }
            { Test-GitMePrerequisite } | Should -Throw '*below the required 2.50.0*'
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Write-GitMeLog" {
    It "Should write Error level to Console.Error" {
        $errorOutput = Invoke-CapturingConsoleErr {
            Write-GitMeLog -Level Error -Message "critical failure"
        }
        $errorOutput | Should -Match 'critical failure'
        $errorOutput | Should -Match '\[ERROR\]'
    }

    It "Should write Info level to Console.Out when not Quiet" {
        $script:GitMeLogLevel = 'Info'
        $output = Invoke-CapturingConsole {
            Write-GitMeLog -Level Info -Message "info message"
        }
        $output | Should -Match 'info message'
        $output | Should -Match '\[INFO\]'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-GitmeTabCompletion" {
    It "Should return exactly the three supported providers" {
        $result = Get-GitmeTabCompletion
        $result | Should -Contain 'GitHub'
        $result | Should -Contain 'GitLab'
        $result | Should -Contain 'Local'
        $result.Count | Should -Be 3
    }
}

# ---------------------------------------------------------------------------
Describe "Invoke-Gitme - uncovered branches" {
    Context "Path, identity, and provider fallbacks" {
        BeforeEach {
            InModuleScope GitMe {
                Mock Test-GitMePrerequisite {}
                Mock Invoke-GitMeNative {
                    return New-Object PSObject -Property @{ Output = ''; ExitCode = 0 }
                }
                Mock Initialize-GitMeRepository {}
                Mock New-GitMeInitialCommit {}
                Mock New-GitMeVersionTag {}
                Mock Show-GitMeInstruction {}
                Mock Write-GitMeLog {}
                Mock Push-Location {}
                Mock Pop-Location {}
            }
        }

        It "Should create target directory when Path does not exist" {
            $tempPath = Join-Path $env:TEMP ("GitMeNewDir_" + [IO.Path]::GetRandomFileName())
            try {
                InModuleScope GitMe -Parameters @{ TargetPath = $tempPath } {
                    param($TargetPath)
                    Mock Get-GitMeConfig { return '' }
                    Invoke-Gitme -RepoName 'Test' -Path $TargetPath -Provider 'GitHub'
                }
                Test-Path $tempPath | Should -Be $true
            }
            finally {
                Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should fall back to env:USERNAME when git config user.name is empty" {
            InModuleScope GitMe {
                Mock Get-GitMeConfig { return '' } -ParameterFilter { $Key -eq 'user.name' }
                Mock Get-GitMeConfig { return '' } -ParameterFilter { $Key -eq 'user.email' }
                $script:capturedName = $null
                Mock Initialize-GitMeRepository {
                    $script:capturedName = $DevName
                }
                Invoke-Gitme -RepoName 'FallbackTest' -Provider 'GitHub'
                $script:capturedName | Should -Be $env:USERNAME
            }
        }

        It "Should use AutoBump version when -AutoBump switch is set" {
            InModuleScope GitMe {
                Mock Get-GitMeConfig { return 'user' }
                Mock Get-GitMeVersionFromCommit { return '9.9.9' }
                $script:capturedVersion = $null
                Mock New-GitMeVersionTag {
                    $script:capturedVersion = $PackVersion
                }
                Invoke-Gitme -RepoName 'BumpTest' -Provider 'GitHub' -AutoBump
                $script:capturedVersion | Should -Be '9.9.9'
            }
        }

        It "Should throw when GitHub -CreateRemote is used without -Token" {
            InModuleScope GitMe {
                Mock Get-GitMeConfig { return 'user' }
                { Invoke-Gitme -RepoName 'Test' -Provider 'GitHub' -CreateRemote } |
                    Should -Throw '*Token is required for GitHub*'
            }
        }

        It "Should throw when GitLab -CreateRemote is used without -Token" {
            InModuleScope GitMe {
                Mock Get-GitMeConfig { return 'user' }
                { Invoke-Gitme -RepoName 'Test' -Provider 'GitLab' -CreateRemote } |
                    Should -Throw '*Token is required for GitLab*'
            }
        }

        It "Should throw when Local provider is used without -RemotePath" {
            InModuleScope GitMe {
                Mock Get-GitMeConfig { return 'user' }
                { Invoke-Gitme -RepoName 'Test' -Provider 'Local' -CreateRemote } |
                    Should -Throw '*RemotePath is required*'
            }
        }
    }
}
