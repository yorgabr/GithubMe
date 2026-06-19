BeforeAll {
    $PrivateScriptPath = Join-Path $PSScriptRoot "..\src\private\Get-GitMeVersionFromCommit.ps1"
    . $PrivateScriptPath
}

Describe "Get-GitMeVersionFromCommit" {

    Context "Conventional Commits Version Bumping Rules" {

        It "Should return major bump when ! is present" {
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    return New-Object PSObject -Property @{
                        Output   = @("feat(core)!: break API", "fix: patch")
                        ExitCode = 0
                    }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3" -GitInvoker $git
            $result | Should -Be "2.0.0"
        }

        It "Should return major bump when BREAKING CHANGE exists" {
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    return New-Object PSObject -Property @{
                        Output   = @("refactor: change api", "", "BREAKING CHANGE: all broke")
                        ExitCode = 0
                    }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3" -GitInvoker $git
            $result | Should -Be "2.0.0"
        }

        It "Should return minor bump for feat" {
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    return New-Object PSObject -Property @{
                        Output   = @("feat: new feature", "fix: adjustment")
                        ExitCode = 0
                    }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3" -GitInvoker $git
            $result | Should -Be "1.3.0"
        }

        It "Should return patch bump for fix only" {
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    return New-Object PSObject -Property @{
                        Output   = @("fix: bug one", "docs: change readme")
                        ExitCode = 0
                    }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3" -GitInvoker $git
            $result | Should -Be "1.2.4"
        }

        It "Should return unchanged version when no relevant commits" {
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    return New-Object PSObject -Property @{
                        Output   = @("chore: cleanup", "docs: typo")
                        ExitCode = 0
                    }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "1.2.3" -GitInvoker $git
            $result | Should -Be "1.2.3"
        }

        It "Should return current version when git log returns no output" {
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "2.0.0" -GitInvoker $git
            $result | Should -Be "2.0.0"
        }

        It "Should fallback to 0.1.0 when CurrentVersion is invalid" {
            $git = {
                param([string[]]$Arguments)
                if ($Arguments -contains 'describe') {
                    return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
                }
                if ($Arguments -contains 'log') {
                    return New-Object PSObject -Property @{
                        Output   = @("feat: something new")
                        ExitCode = 0
                    }
                }
                return New-Object PSObject -Property @{ Output = @(); ExitCode = 0 }
            }

            $result = Get-GitMeVersionFromCommit -CurrentVersion "not-a-version" -GitInvoker $git
            $result | Should -Be "0.2.0"
        }
    }
}
