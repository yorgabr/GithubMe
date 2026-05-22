BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force
}

Describe "Invoke-GitMeNative" {
    Context "Wrapper protection layer" {
        It "Should correctly extract output records and execution codes from normal flows" {
            # Mock the native git command inside the module namespace using Pester's alias mapping support
            Mock git { return "git version 2.50.0" }
            
            $result = Invoke-GitMeNative -Arguments @('--version')
            $result.ExitCode | Should -Be 0
            $result.Output   | Should -Be "git version 2.50.0"
        }

        It "Should capture standard error streams safely without breaking automation threads" {
            # Simulate a native error emitting standard error responses
            Mock git { 
                $LASTEXITCODE = 128
                return "fatal: not a git repository" 
            }

            $result = Invoke-GitMeNative -Arguments @('status')
            $result.ExitCode | Should -Be 128
            $result.Output   | Should -Match "fatal"
        }
    }
}