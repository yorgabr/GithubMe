BeforeAll {
    # Import the actual module
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force

    # Define global temporary paths for the test suite
    $global:IntegrationTestRoot = Join-Path $env:TEMP "GitMe_Integration_Root"
    $global:MockServerPort = 8989
    $global:MockServerUrl = "http://localhost:$global:MockServerPort/"

    # CLEANUP GUARANTEE 1: If a previous test run aborted prematurely, clean it up now
    if (Test-Path $global:IntegrationTestRoot) {
        Remove-Item $global:IntegrationTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $global:IntegrationTestRoot -Force

    # Background HTTP Server Initialization (.NET HttpListener)
    $global:Listener = [System.Net.HttpListener]::new()
    $global:Listener.Prefixes.Add($global:MockServerUrl)
    $global:Listener.Start()

    # ScriptBlock acting as the engine for GitHub and GitLab APIs.
    # The mock server responds with local bare repo paths as CloneUrls,
    # enabling real git push operations against the local filesystem.
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

                # GitHub emulation: GET /user returns identity
                if ($Path -match "/user$" -and $Method -eq "GET") {
                    $ResponseBody = '{"login": "gitme-integration-user"}'
                }
                # GitHub emulation: POST /user/repos creates a repository
                elseif ($Path -match "/user/repos$" -and $Method -eq "POST") {
                    $Response.StatusCode = 201
                    $TargetBare = (Join-Path $IntegrationTestRoot "remotes\github-repo.git").Replace("\", "/")
                    # Return a file:// URI so git can push to the local bare repo
                    $CloneUrl = "file:///$TargetBare"
                    $ResponseBody = '{"clone_url": "' + $CloneUrl + '", "html_url": "http://github.com/gitme-integration-user/github-repo"}'
                }
                # GitLab emulation: POST /api/v4/projects creates a project
                elseif ($Path -match "/api/v4/projects$" -and $Method -eq "POST") {
                    $Response.StatusCode = 201
                    $TargetBare = (Join-Path $IntegrationTestRoot "remotes\gitlab-repo.git").Replace("\", "/")
                    $CloneUrl = "file:///$TargetBare"
                    $ResponseBody = '{"http_url_to_repo": "' + $CloneUrl + '", "web_url": "http://gitlab.com/gitme-integration-user/gitlab-repo"}'
                }
                else {
                    # Fallback: return 404 for unhandled routes
                    $Response.StatusCode = 404
                    $ResponseBody = '{"message": "Not Found"}'
                }

                # Write the HTTP response
                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.ContentType = "application/json"
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
            }
        }
        catch {
            # Suppressed to allow smooth termination when the Listener stops
        }
    }

    # Run the server in a separate Runspace/Thread to avoid blocking Pester.
    # Pass IntegrationTestRoot explicitly since $global: is not visible in child runspaces.
    $global:ServerPowerShell = [PowerShell]::Create().AddScript($ServerScript).AddArgument($global:Listener).AddArgument($global:IntegrationTestRoot)
    $global:ServerAsyncResult = $global:ServerPowerShell.BeginInvoke()
}

AfterAll {
    # CLEANUP GUARANTEE 2: Always executed at the end, even if tests fail
    try {
        # Shut down the Mock HTTP Server
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
        # Return to the original directory before deleting the temporary folder
        Set-Location $PSScriptRoot

        # Remove all created local repositories and files
        if (Test-Path $global:IntegrationTestRoot) {
            # Force release of Git handles before deletion
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500
            Remove-Item $global:IntegrationTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "GitMe - End-to-End Integration Tests" {
    Context "Full Workflow Using Locally Emulated Infrastructure" {
        BeforeEach {
            # Create isolated subfolders for this specific scenario
            $script:ContextId = [System.IO.Path]::GetRandomFileName()
            $script:LocalRepoPath = Join-Path $global:IntegrationTestRoot "local-$($script:ContextId)"
            $script:RemoteRepoPath = Join-Path $global:IntegrationTestRoot "remotes"

            $null = New-Item -ItemType Directory -Path $script:LocalRepoPath -Force
            $null = New-Item -ItemType Directory -Path $script:RemoteRepoPath -Force

            # Create the local BARE repositories (simulating the server side).
            # The HTTP mocks return file:// URIs pointing to these bare folders.
            $GitHubBarePath = Join-Path $script:RemoteRepoPath "github-repo.git"
            $GitLabBarePath = Join-Path $script:RemoteRepoPath "gitlab-repo.git"

            # Only initialize if not already a bare repo (avoids re-init warnings)
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

            # Enter the local repository folder where the main command will be tested
            Set-Location $script:LocalRepoPath
        }

        It "Should create a remote repository on emulated GitHub and successfully push the initial commit" {
            # The -ApiBaseUrl parameter directs all API calls to our local mock server
            # instead of the real GitHub API. This enables fully offline testing.
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

            # Verify the remote was configured correctly
            $remoteUrl = git remote get-url origin 2>&1
            $remoteUrl | Should -Not -BeNullOrEmpty

            # Verify that commits exist in the bare repository
            Push-Location (Join-Path $script:RemoteRepoPath "github-repo.git")
            $GitLog = git log --all --oneline 2>&1
            Pop-Location

            $GitLog | Should -Not -BeNullOrEmpty
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

            # Verify the remote was configured correctly
            $remoteUrl = git remote get-url origin 2>&1
            $remoteUrl | Should -Not -BeNullOrEmpty

            # Verify that commits exist in the bare repository
            Push-Location (Join-Path $script:RemoteRepoPath "gitlab-repo.git")
            $GitLog = git log --all --oneline 2>&1
            Pop-Location

            $GitLog | Should -Not -BeNullOrEmpty
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

            # Verify the bare repository was created
            $bareRepoPath = Join-Path $localRemotePath "local-project.git"
            Test-Path (Join-Path $bareRepoPath 'HEAD') | Should -Be $true

            # Verify the remote was set
            $remoteUrl = git remote get-url origin 2>&1
            $remoteUrl | Should -Not -BeNullOrEmpty
        }
    }
}
