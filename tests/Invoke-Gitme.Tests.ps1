BeforeAll {
    # Import the module explicitly before running tests
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force
}

Describe "Invoke-Gitme" {
    Context "Local repository execution" {
        BeforeEach {
            # Mock prerequisites and core internal steps to isolate the orchestrator
            Mock Test-GitMePrerequisite {}
            Mock Get-GitMeConfig { return "mocked-user" } -ParameterFilter { $Key -eq "user.name" }
            Mock Get-GitMeConfig { return "mocked@email.com" } -ParameterFilter { $Key -eq "user.email" }
            Mock Invoke-GitMeNative { 
                return [pscustomobject]@{ Output = "v0.1.0"; ExitCode = 0 } 
            } -ParameterFilter { $Arguments -contains "describe" }

            Mock Initialize-GitMeRepository {}
            Mock New-GitMeInitialCommit {}
            Mock New-GitMeVersionTag {}
            Mock Show-GitMeInstruction {}
            Mock Push-Location {}
            Mock Pop-Location {}
        }

        It "Should run the complete pipeline with default parameters" {
            Invoke-Gitme -RepoName "UnitTestRepo" -VerboseOutput:$false -Provider "GitHub"

            # Assert that core functions were invoked exactly once
            Assert-MockCalled Initialize-GitMeRepository -Times 1 -Exactly
            Assert-MockCalled New-GitMeInitialCommit -Times 1 -Exactly
            Assert-MockCalled New-GitMeVersionTag -Times 1 -Exactly
            Assert-MockCalled Show-GitMeInstruction -Times 1 -Exactly
        }

        It "Should output module version and exit when -Version parameter is passed" {
            $output = Invoke-Gitme -Version
            $output | Should -Match "GitMe version"
        }
    }

    Context "Remote repository creation triggers" {
        BeforeEach {
            Mock Test-GitMePrerequisite {}
            Mock Get-GitMeConfig { return "mocked-user" }
            Mock Invoke-GitMeNative { return [pscustomobject]@{ Output = ""; ExitCode = 0 } }
            Mock Initialize-GitMeRepository {}
            Mock New-GitMeInitialCommit {}
            Mock New-GitMeVersionTag {}
            Mock New-GitMeReleaseNote {}
            Mock Add-GitMeRemote {}
            Mock Push-Location {}
            Mock Pop-Location {}
            
            # Mock the API calling function to return a clean PSCustomObject
            Mock New-RemoteRepository {
                return [pscustomobject]@{ CloneUrl = "https://github.com/mock/repo.git"; HtmlUrl = "https://github.com/mock/repo"; Provider = "GitHub" }
            }
        }

        It "Should call New-RemoteRepository when -CreateRemote is present" {
            Invoke-Gitme -RepoName "RemoteRepo" -Provider "GitHub" -CreateRemote -Token "mock-token"

            Assert-MockCalled New-RemoteRepository -Times 1 -Exactly
            Assert-MockCalled Add-GitMeRemote -Times 1 -Exactly
        }

        It "Should throw an exception if -CreateRemote is specified but Token is missing" {
            { Invoke-Gitme -RepoName "RemoteRepo" -Provider "GitHub" -CreateRemote } | Should -Throw "*Token is required*"
        }
    }
}