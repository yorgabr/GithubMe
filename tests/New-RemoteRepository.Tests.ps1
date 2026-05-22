BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force
}

Describe "New-RemoteRepository" {
    Context "GitHub Platform API integrations" {
        BeforeEach {
            # Clear log overrides to prevent console pollution
            Mock Write-GitMeLog {}
        }

        It "Should return repository payload structure on successful GitHub creation" {
            # Mock Invoke-RestMethod for user validation and repo post
            Mock Invoke-RestMethod { 
                return [pscustomobject]@{ login = "yorgabr" } 
            } -ParameterFilter { $Uri -match "/user$" }

            Mock Invoke-RestMethod {
                return [pscustomobject]@{
                    clone_url = "https://github.com/yorgabr/TestRepo.git"
                    html_url  = "https://github.com/yorgabr/TestRepo"
                }
            } -ParameterFilter { $Uri -match "/user/repos$" }

            $result = New-RemoteRepository -Provider "GitHub" -Owner "yorgabr" -Name "TestRepo" -Token "secret"
            
            $result.Provider | Should -Be "GitHub"
            $result.CloneUrl | Should -Be "https://github.com/yorgabr/TestRepo.git"
            $result.HtmlUrl  | Should -Be "https://github.com/yorgabr/TestRepo"
        }

        It "Should gracefully handle a 422 unprocessable entity exception" {
            Mock Invoke-RestMethod { return [pscustomobject]@{ login = "yorgabr" } } -ParameterFilter { $Uri -match "/user$" }
            
            # Generate a mock exception mapping a 422 status code response
            Mock Invoke-RestMethod {
                $response = [System.Net.HttpWebResponse]::new()
                # Use reflection to assign internal status code if required or pass a fallback structure
                $exception = [System.Management.Automation.RuntimeException]::new("Repository already exists")
                throw $exception
            } -ParameterFilter { $Uri -match "/user/repos$" }

            { New-RemoteRepository -Provider "GitHub" -Owner "yorgabr" -Name "DuplicateRepo" -Token "secret" } | Should -Throw
        }
    }

    Context "GitLab Platform API integrations" {
        BeforeEach {
            Mock Write-GitMeLog {}
        }

        It "Should return repository payload structure on successful GitLab creation" {
            Mock Invoke-RestMethod {
                return [pscustomobject]@{
                    http_url_to_repo = "https://gitlab.com/yorgabr/GitLabRepo.git"
                    web_url          = "https://gitlab.com/yorgabr/GitLabRepo"
                }
            }

            $result = New-RemoteRepository -Provider "GitLab" -Owner "yorgabr" -Name "GitLabRepo" -Token "secret"

            $result.Provider | Should -Be "GitLab"
            $result.CloneUrl | Should -Be "https://gitlab.com/yorgabr/GitLabRepo.git"
            $result.HtmlUrl  | Should -Be "https://gitlab.com/yorgabr/GitLabRepo"
        }
    }
}