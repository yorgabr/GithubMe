BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force

    # Dot-source private functions to make them discoverable by Pester's Mock engine.
    # Without this, Pester 5.x throws CommandNotFoundException on private helpers.
    $PrivateRoot = Join-Path $PSScriptRoot "..\src\private"
    Get-ChildItem -Path "$PrivateRoot\*.ps1" | ForEach-Object { . $_.FullName }
}

Describe "New-RemoteRepository" {
    Context "GitHub Platform API integrations" {
        BeforeEach {
            # Suppress log output during tests
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
            Mock Invoke-RestMethod {
                return [pscustomobject]@{ login = "yorgabr" }
            } -ParameterFilter { $Uri -match "/user$" }

            # Simulate an HTTP 422 error with a response object that matches
            # the hybrid status code parsing logic in New-RemoteRepository
            Mock Invoke-RestMethod {
                $mockResponse = New-Object PSObject -Property @{
                    StatusCode = [System.Net.HttpStatusCode]::UnprocessableEntity
                }
                $exception = [System.Net.WebException]::new("422 Unprocessable Entity")
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'WebException', 'InvalidOperation', $null
                )
                # Attach the Response property to the ErrorRecord so the catch block
                # can extract the status code via $_.Exception.Response
                $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse
                throw $errorRecord
            } -ParameterFilter { $Uri -match "/user/repos$" }

            { New-RemoteRepository -Provider "GitHub" -Owner "yorgabr" -Name "DuplicateRepo" -Token "secret" } | Should -Throw
        }

        It "Should use organization endpoint when Owner differs from authenticated user" {
            Mock Invoke-RestMethod {
                return [pscustomobject]@{ login = "personal-user" }
            } -ParameterFilter { $Uri -match "/user$" }

            Mock Invoke-RestMethod {
                return [pscustomobject]@{
                    clone_url = "https://github.com/my-org/OrgRepo.git"
                    html_url  = "https://github.com/my-org/OrgRepo"
                }
            } -ParameterFilter { $Uri -match "/orgs/my-org/repos$" }

            $result = New-RemoteRepository -Provider "GitHub" -Owner "my-org" -Name "OrgRepo" -Token "secret"

            $result.CloneUrl | Should -Be "https://github.com/my-org/OrgRepo.git"
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

        It "Should handle GitLab 400 error for duplicate project" {
            Mock Invoke-RestMethod {
                $mockResponse = New-Object PSObject -Property @{
                    StatusCode = [System.Net.HttpStatusCode]::BadRequest
                }
                $exception = [System.Net.WebException]::new("400 Bad Request")
                $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'WebException', 'InvalidOperation', $null
                )
                throw $errorRecord
            }

            { New-RemoteRepository -Provider "GitLab" -Owner "yorgabr" -Name "DuplicateProject" -Token "secret" } | Should -Throw
        }
    }
}
