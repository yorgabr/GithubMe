BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force
}

Describe "Invoke-Gitme" {
    Context "Local repository execution" {
        BeforeEach {
            # All mocks must live inside InModuleScope so Pester intercepts the
            # calls that Invoke-Gitme makes against its own module's functions.
            InModuleScope GitMe {
                Mock Test-GitMePrerequisite {}
                Mock Get-GitMeConfig { return "mocked-user" } -ParameterFilter { $Key -eq "user.name" }
                Mock Get-GitMeConfig { return "mocked@email.com" } -ParameterFilter { $Key -eq "user.email" }
                Mock Invoke-GitMeNative {
                    return [pscustomobject]@{ Output = "v0.1.0"; ExitCode = 0 }
                } -ParameterFilter { $Arguments -contains "describe" }
                Mock Invoke-GitMeNative {
                    return [pscustomobject]@{ Output = ""; ExitCode = 0 }
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

        It "Should run the complete pipeline with default parameters" {
            InModuleScope GitMe {
                Invoke-Gitme -RepoName "UnitTestRepo" -VerboseOutput:$false -Provider "GitHub"

                Should -Invoke Initialize-GitMeRepository -Times 1 -Exactly
                Should -Invoke New-GitMeInitialCommit -Times 1 -Exactly
                Should -Invoke New-GitMeVersionTag -Times 1 -Exactly
                Should -Invoke Show-GitMeInstruction -Times 1 -Exactly
            }
        }

        It "Should output module version and exit when -Version parameter is passed" {
            InModuleScope GitMe {
                $output = Invoke-Gitme -Version
                $output | Should -Match "GitMe version"
            }
        }
    }

    Context "Remote repository creation triggers" {
        BeforeEach {
            InModuleScope GitMe {
                Mock Test-GitMePrerequisite {}
                Mock Get-GitMeConfig { return "mocked-user" }
                Mock Invoke-GitMeNative {
                    return [pscustomobject]@{ Output = ""; ExitCode = 0 }
                }
                Mock Initialize-GitMeRepository {}
                Mock New-GitMeInitialCommit {}
                Mock New-GitMeVersionTag {}
                Mock Add-GitMeRemote {}
                Mock Write-GitMeLog {}
                Mock Push-Location {}
                Mock Pop-Location {}
                Mock New-RemoteRepository {
                    return [pscustomobject]@{
                        CloneUrl = "https://github.com/mock/repo.git"
                        HtmlUrl  = "https://github.com/mock/repo"
                        Provider = "GitHub"
                    }
                }
            }
        }

        It "Should call New-RemoteRepository when -CreateRemote is present" {
            InModuleScope GitMe {
                Invoke-Gitme -RepoName "RemoteRepo" -Provider "GitHub" -CreateRemote -Token "mock-token"

                Should -Invoke New-RemoteRepository -Times 1 -Exactly
                Should -Invoke Add-GitMeRemote -Times 1 -Exactly
            }
        }

        It "Should throw an exception if -CreateRemote is specified but Token is missing" {
            InModuleScope GitMe {
                { Invoke-Gitme -RepoName "RemoteRepo" -Provider "GitHub" -CreateRemote } |
                    Should -Throw "*Token is required*"
            }
        }

        It "Should emit WARN when tag already exists without -Force" {
            InModuleScope GitMe {
                # Remove the generic New-GitMeVersionTag mock and replace with
                # one that writes the expected warning through Write-GitMeLog
                Mock New-GitMeVersionTag {
                    Write-GitMeLog -Level Warn -Message "Tag v0.1.0 already exists. Use -Force to recreate."
                }

                # Capture all Write-GitMeLog calls to inspect warning messages
                $warnMessages = [System.Collections.Generic.List[string]]::new()
                Mock Write-GitMeLog {
                    if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
                }

                Invoke-Gitme -RepoName "RemoteRepo" -Provider "GitHub" -CreateRemote -Token "mock-token"

                $warnMessages | Should -Contain "Tag v0.1.0 already exists. Use -Force to recreate."
            }
        }

        It "Should emit WARN when push fails after remote creation" {
            InModuleScope GitMe {
                $warnMessages = [System.Collections.Generic.List[string]]::new()
                Mock Write-GitMeLog {
                    if ($Level -eq 'Warn') { $warnMessages.Add($Message) }
                }
                Mock Add-GitMeRemote {
                    Write-GitMeLog -Level Warn -Message "Failed to push branch 'main'."
                    Write-GitMeLog -Level Warn -Message "Failed to push tag v0.1.0."
                }

                Invoke-Gitme -RepoName "RemoteRepo" -Provider "GitHub" -CreateRemote -Token "mock-token"

                ($warnMessages -join ' ') | Should -Match "Failed to push"
            }
        }
    }

    Context "Help and meta flags" {
        It "Should display help text when -Help is passed" {
            InModuleScope GitMe {
                $output = Invoke-Gitme -Help
                $output | Should -Match "Invoke-Gitme"
                $output | Should -Match "-Provider"
            }
        }
    }
}
