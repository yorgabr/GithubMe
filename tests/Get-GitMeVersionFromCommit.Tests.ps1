BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force
}

Describe "Get-GitMeVersionFromCommit" {
    Context "Conventional Commits Version Bumping Rules" {
        It "Should return major bump when a breaking change exclamation is present" {
            Mock Invoke-GitMeNative {
                return [pscustomobject]@{ 
                    Output = @("feat(core)!: break the contract", "fix: minor fix"); 
                    ExitCode = 0 
                }
            } -ParameterFilter { $Arguments -contains "log" }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3"
            $result | Should -Be "2.0.0"
        }

        It "Should return major bump when BREAKING CHANGE footer note is found" {
            Mock Invoke-GitMeNative {
                return [pscustomobject]@{ 
                    Output = @("refactor: change internal api", "", "BREAKING CHANGE: everything changed"); 
                    ExitCode = 0 
                }
            } -ParameterFilter { $Arguments -contains "log" }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3"
            $result | Should -Be "2.0.0"
        }

        It "Should return minor bump when a new feature prefix is detected" {
            Mock Invoke-GitMeNative {
                return [pscustomobject]@{ 
                    Output = @("feat: add validation rules", "fix: minor adjustments"); 
                    ExitCode = 0 
                }
            } -ParameterFilter { $Arguments -contains "log" }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3"
            $result | Should -Be "1.3.0"
        }

        It "Should return patch bump when only fixes are present" {
            Mock Invoke-GitMeNative {
                return [pscustomobject]@{ 
                    Output = @("fix: solve null reference pointer", "docs: update readme file"); 
                    ExitCode = 0 
                }
            } -ParameterFilter { $Arguments -contains "log" }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3"
            $result | Should -Be "1.2.4"
        }

        It "Should return unchanged version if no conventional patterns match" {
            Mock Invoke-GitMeNative {
                return [pscustomobject]@{ 
                    Output = @("chore: tidy up files", "docs: minor typo fixes"); 
                    ExitCode = 0 
                }
            } -ParameterFilter { $Arguments -contains "log" }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3"
            $result | Should -Be "1.2.3"
        }
    }
}