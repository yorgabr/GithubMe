BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force

    $global:IntegrationTestRoot = Join-Path $env:TEMP "GitMe_Integration_Root"
    $global:MockServerPort = 8989
    $global:MockServerUrl = "http://localhost:$global:MockServerPort/"

    if (Test-Path $global:IntegrationTestRoot) {
        Remove-Item $global:IntegrationTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $global:IntegrationTestRoot -Force

    # ── Silence [Console]::Out and [Console]::Error for the entire suite ──
    # Write-GitMeLog writes directly to the .NET Console, bypassing PowerShell
    # streams.  We replace both writers with StringWriters so integration test
    # output never pollutes the Pester console.  The original writers are
    # restored in AfterAll.
    $global:OriginalConsoleOut = [Console]::Out
    $global:OriginalConsoleErr = [Console]::Error
    $global:SuppressedOut = [System.IO.StringWriter]::new()
    $global:SuppressedErr = [System.IO.StringWriter]::new()
    [Console]::SetOut($global:SuppressedOut)
    [Console]::SetError($global:SuppressedErr)

    $global:Listener = [System.Net.HttpListener]::new()
    $global:Listener.Prefixes.Add($global:MockServerUrl)
    $global:Listener.Start()

    $ServerScript = {
        param($Listener, $IntegrationTestRoot)
        try {
            while ($Listener.IsListening) {
                $Context = $Listener.GetContext()
                $Request = $Context.Request
                $Response = $Context.Response

                $Path = $Request.Url.LocalPath.ToLower()
                $Method = $Request.HttpMethod
                $ResponseBody = ""
                $Response.StatusCode = 200

                if ($Path -match "/user$" -and $Method -eq "GET") {
                    $ResponseBody = '{"login": "gitme-integration-user"}'
                }
                elseif ($Path -match "/user/repos$" -and $Method -eq "POST") {
                    $Response.StatusCode = 201
                    $TargetBare = (Join-Path $IntegrationTestRoot "remotes\github-repo.git").Replace("\", "/")
                    $CloneUrl = "file:///$TargetBare"
                    $ResponseBody = '{"clone_url": "' + $CloneUrl + '", "html_url": "http://github.com/gitme-integration-user/github-repo"}'
                }
                elseif ($Path -match "/api/v4/projects$" -and $Method -eq "POST") {
                    $Response.StatusCode = 201
                    $TargetBare = (Join-Path $IntegrationTestRoot "remotes\gitlab-repo.git").Replace("\", "/")
                    $CloneUrl = "file:///$TargetBare"
                    $ResponseBody = '{"http_url_to_repo": "' + $CloneUrl + '", "web_url": "http://gitlab.com/gitme-integration-user/gitlab-repo"}'
                }
                else {
                    $Response.StatusCode = 404
                    $ResponseBody = '{"message": "Not Found"}'
                }

                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.ContentType = "application/json"
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
            }
        }
        catch { }
    }

    $global:ServerPowerShell = [PowerShell]::Create().AddScript($ServerScript).AddArgument($global:Listener).AddArgument($global:IntegrationTestRoot)
    $global:ServerAsyncResult = $global:ServerPowerShell.BeginInvoke()
}

AfterAll {
    # Restore console writers FIRST so Pester can print its own summary
    if ($global:OriginalConsoleOut) { [Console]::SetOut($global:OriginalConsoleOut) }
    if ($global:OriginalConsoleErr) { [Console]::SetError($global:OriginalConsoleErr) }
    $global:SuppressedOut.Dispose()
    $global:SuppressedErr.Dispose()

    try {
        if ($global:Listener -and $global:Listener.IsListening) {
            $global:Listener.Stop()
            $global:Listener.Close()
        }
        if ($global:ServerPowerShell) {
            try { $global:ServerPowerShell.EndInvoke($global:ServerAsyncResult) } catch {}
            $global:ServerPowerShell.Dispose()
        }
    }
    finally {
        Set-Location $PSScriptRoot
        if (Test-Path $global:IntegrationTestRoot) {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500
            Remove-Item $global:IntegrationTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "GitMe - End-to-End Integration Tests" {
    BeforeAll {
        # Console-capture helper: temporarily restores the REAL stdout so we can
        # collect what Write-GitMeLog emits, then re-silences it afterwards.
        function script:Invoke-WithConsoleCapture {
            param([Parameter(Mandatory)][scriptblock]$ScriptBlock)
            $captureWriter = [System.IO.StringWriter]::new()
            # Point console to the capture writer (temporarily overrides the suppressor)
            [Console]::SetOut($captureWriter)
            try {
                & $ScriptBlock
            }
            finally {
                # Return to the suite-level suppressor (not the original terminal)
                [Console]::SetOut($global:SuppressedOut)
            }
            return $captureWriter.ToString()
        }
    }

    Context "Full Workflow Using Locally Emulated Infrastructure" {
        BeforeEach {
            $script:ContextId = [System.IO.Path]::GetRandomFileName()
            $script:LocalRepoPath = Join-Path $global:IntegrationTestRoot "local-$($script:ContextId)"
            $script:RemoteRepoPath = Join-Path $global:IntegrationTestRoot "remotes"

            $null = New-Item -ItemType Directory -Path $script:LocalRepoPath -Force
            $null = New-Item -ItemType Directory -Path $script:RemoteRepoPath -Force

            $GitHubBarePath = Join-Path $script:RemoteRepoPath "github-repo.git"
            $GitLabBarePath = Join-Path $script:RemoteRepoPath "gitlab-repo.git"

            if (-not (Test-Path (Join-Path $GitHubBarePath 'HEAD'))) {
                $null = New-Item -ItemType Directory -Path $GitHubBarePath -Force
                Push-Location $GitHubBarePath
                git init --bare --initial-branch=main 2>&1 | Out-Null
                Pop-Location
            }

            if (-not (Test-Path (Join-Path $GitLabBarePath 'HEAD'))) {
                $null = New-Item -ItemType Directory -Path $GitLabBarePath -Force
                Push-Location $GitLabBarePath
                git init --bare --initial-branch=main 2>&1 | Out-Null
                Pop-Location
            }

            Set-Content -Path (Join-Path $script:LocalRepoPath "README.md") `
                -Value "# Integration test repo`n" -Encoding UTF8

            Set-Location $script:LocalRepoPath
        }

        It "Should create a remote repository on emulated GitHub and successfully push the initial commit" {
            Invoke-Gitme `
                -RepoName "github-repo" `
                -Provider "GitHub" `
                -CreateRemote `
                -Token "fake-token-123" `
                -UserName "gitme-integration-user" `
                -UserEmail "bot@integration.test" `
                -ApiBaseUrl "http://localhost:$global:MockServerPort" `
                -PackVersion "0.1.0" `
                -VerboseOutput

            $remoteUrl = git remote get-url origin 2>&1
            $remoteUrl | Should -Not -BeNullOrEmpty

            Push-Location (Join-Path $script:RemoteRepoPath "github-repo.git")
            $gitLog = git log --all --oneline 2>&1
            Pop-Location

            $gitLog | Should -Not -BeNullOrEmpty
            ($gitLog -join '') | Should -Match 'feat: initial commit'
        }

        It "Should create a remote repository on emulated GitLab and mirror the Git workflow" {
            Invoke-Gitme `
                -RepoName "gitlab-repo" `
                -Provider "GitLab" `
                -CreateRemote `
                -Token "fake-token-456" `
                -UserName "gitme-integration-user" `
                -UserEmail "bot@integration.test" `
                -ApiBaseUrl "http://localhost:$global:MockServerPort/api/v4" `
                -PackVersion "0.1.0" `
                -VerboseOutput

            $remoteUrl = git remote get-url origin 2>&1
            $remoteUrl | Should -Not -BeNullOrEmpty

            Push-Location (Join-Path $script:RemoteRepoPath "gitlab-repo.git")
            $gitLog = git log --all --oneline 2>&1
            Pop-Location

            $gitLog | Should -Not -BeNullOrEmpty
            ($gitLog -join '') | Should -Match 'feat: initial commit'
        }

        It "Should handle Local provider with a bare repository on the filesystem" {
            $localRemotePath = Join-Path $global:IntegrationTestRoot "local-bare-$($script:ContextId)"
            $null = New-Item -ItemType Directory -Path $localRemotePath -Force

            Invoke-Gitme `
                -RepoName "local-project" `
                -Provider "Local" `
                -RemotePath $localRemotePath `
                -UserName "local-user" `
                -UserEmail "local@test.dev" `
                -PackVersion "1.0.0" `
                -VerboseOutput

            $bareRepoPath = Join-Path $localRemotePath "local-project.git"
            Test-Path (Join-Path $bareRepoPath 'HEAD') | Should -Be $true

            $remoteUrl = git remote get-url origin 2>&1
            $remoteUrl | Should -Not -BeNullOrEmpty

            Push-Location $bareRepoPath
            $gitLog = git log --all --oneline 2>&1
            Pop-Location

            $gitLog | Should -Not -BeNullOrEmpty
            ($gitLog -join '') | Should -Match 'feat: initial commit'
        }

        It "Should emit WARN when working tree is clean (idempotent re-run)" {
            Invoke-Gitme `
                -RepoName "github-repo" `
                -Provider "GitHub" `
                -CreateRemote `
                -Token "fake-token-123" `
                -UserName "gitme-integration-user" `
                -UserEmail "bot@integration.test" `
                -ApiBaseUrl "http://localhost:$global:MockServerPort" `
                -PackVersion "0.1.0" `
                -VerboseOutput

            $consoleOutput = Invoke-WithConsoleCapture {
                Invoke-Gitme `
                    -RepoName "github-repo" `
                    -Provider "GitHub" `
                    -CreateRemote `
                    -Token "fake-token-123" `
                    -UserName "gitme-integration-user" `
                    -UserEmail "bot@integration.test" `
                    -ApiBaseUrl "http://localhost:$global:MockServerPort" `
                    -PackVersion "0.1.0" `
                    -Force `
                    -VerboseOutput
            }

            $consoleOutput | Should -Match '\[WARN\]'
            $consoleOutput | Should -Match 'Nothing to commit|working tree may be clean'
        }
    }
}
