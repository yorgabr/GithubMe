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

    # ScriptBlock acting as the engine for GitHub and GitLab APIs
    $ServerScript = {
        param($Listener)
        try {
            while ($Listener.IsListening) {
                $Context = $Listener.GetContext()
                $Request = $Context.Request
                $Response = $Context.Response
                
                $Path = $Request.Url.LocalPath.ToLower()
                $Method = $Request.HttpMethod
                $ResponseBody = ""
                $Response.StatusCode = 200

                # Github emulation
                if ($Path -match "/user$" -and $Method -eq "GET") {
                    $ResponseBody = '{"login": "gitme-integration-user"}'
                }
                elseif ($Path -match "/user/repos$" -and $Method -eq "POST") {
                    $Response.StatusCode = 201
                    $ResponseBody = '{"clone_url": "http://localhost:8989/remotes/github-repo.git", "html_url": "http://github.com/gitme-integration-user/github-repo"}'
                }
                
                # Gitlab emulation
                elseif ($Path -match "/api/v4/projects$" -and $Method -eq "POST") {
                    $Response.StatusCode = 201
                    $ResponseBody = '{"http_url_to_repo": "http://localhost:8989/remotes/gitlab-repo.git", "web_url": "http://gitlab.com/gitme-integration-user/gitlab-repo"}'
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

    # Run the server in a separate Runspace/Thread to avoid blocking Pester
    $global:ServerPowerShell = [PowerShell]::Create().AddScript($ServerScript).AddArgument($global:Listener)
    $global:ServerAsyncResult = $global:ServerPowerShell.BeginInvoke()

    # Redirect the module to use our local server instead of the internet
    $env:GITME_API_BASE_URL = "http://localhost:$global:MockServerPort"
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
            $global:ServerPowerShell.EndInvoke($global:ServerAsyncResult)
            $global:ServerPowerShell.Dispose()
        }
    }
    finally {
        # Restore environment variables
        Remove-Item Env:\GITME_API_BASE_URL -ErrorAction SilentlyContinue

        # Return to the original directory before deleting the temporary folder
        Set-Location $PSScriptRoot

        # Remove all created local repositories and files
        if (Test-Path $global:IntegrationTestRoot) {
            # Force release of Git handles before deletion
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Remove-Item $global:IntegrationTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "GitMe - End-to-End Integration Tests" {
    Context "Full Workflow Using Locally Emulated Infrastructure" {
        BeforeEach {
            # Create isolated subfolders for this specific scenario
            $ContextId = [System.IO.Path]::GetRandomFileName()
            $LocalRepoPath = Join-Path $global:IntegrationTestRoot "local-$ContextId"
            $RemoteRepoPath = Join-Path $global:IntegrationTestRoot "remotes"
            
            $null = New-Item -ItemType Directory -Path $LocalRepoPath -Force
            $null = New-Item -ItemType Directory -Path $RemoteRepoPath -Force

            # Create the local BARE repository (Simulating the GitHub/GitLab server side)
            # Our HTTP mocks point the CloneUrl exactly to these local bare folders
            $GitHubBarePath = Join-Path $RemoteRepoPath "github-repo.git"
            $GitLabBarePath = Join-Path $RemoteRepoPath "gitlab-repo.git"

            $null = New-Item -ItemType Directory -Path $GitHubBarePath -Force
            $null = New-Item -ItemType Directory -Path $GitLabBarePath -Force

            Set-Location $GitHubBarePath
            git init --bare --initial-branch=main | Out-Null

            Set-Location $GitLabBarePath
            git init --bare --initial-branch=main | Out-Null

            # Enter the local repository folder where the main command will be tested
            Set-Location $LocalRepoPath
            git init --initial-branch=main | Out-Null

            # Configure LOCAL Git scope to avoid dependency on the runner's environment
            git config user.name "Integration Test Bot"
            git config user.email "bot@integration.test"
        }

        It "Should create a remote repository on emulated GitHub and successfully push the initial commit" {
            # Simulate local files that GitMe needs to process
            $null = New-Item -ItemType File -Path "README.md" -Value "# Integration Target" -Force
            git add README.md

            # Execute the actual module command. It will trigger the HTTP call to localhost
            # and configure the remote pointing to our local bare repository.
            Invoke-Gitme -RepoName "github-repo" -Provider "GitHub" -CreateRemote -Token "fake-token-123"

            # Invoke-Gitme internally commits and adds the remote.
            # Force a real push to validate that the connection to the bare repository works.
            git push origin main 2>&1 | Out-Null

            # Integration Assertion: The Bare repository must have received the commit history
            $GitLog = git log origin/main --oneline
            $GitLog | Should -Not -BeNullOrEmpty
            $GitLog[0] | Should -Match "feat: initial commit"
        }

        It "Should create a remote repository on emulated GitLab and mirror the Git workflow" {
            $null = New-Item -ItemType File -Path "README.md" -Value "# GitLab Integration Target" -Force
            git add README.md

            Invoke-Gitme -RepoName "gitlab-repo" -Provider "GitLab" -CreateRemote -Token "fake-token-456"
            
            git push origin main 2>&1 | Out-Null

            $GitLog = git log origin/main --oneline
            $GitLog | Should -Not -BeNullOrEmpty
            $GitLog[0] | Should -Match "feat: initial commit"
        }
    }
}