BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\src\GitMe.psd1"
    Import-Module $ModulePath -Force

    # Dot-source the private function directly so it is callable in the test scope.
    # The module only exports public functions; private helpers need explicit loading.
    $PrivateFunctionPath = Join-Path $PSScriptRoot "..\src\private\Invoke-GitMeNative.ps1"
    . $PrivateFunctionPath
}

Describe "Invoke-GitMeNative" {
    Context "Wrapper protection layer" {
        It "Should correctly extract output records and execution codes from normal flows" {
            # Execute a real git --version call since we need the actual binary interaction.
            # This validates the wrapper's ability to capture stdout and exit codes.
            $result = Invoke-GitMeNative -Arguments @('--version')

            $result.ExitCode | Should -Be 0
            # Git is installed (prerequisite), so output must contain version info
            ($result.Output -join '') | Should -Match "git version"
        }

        It "Should capture standard error streams safely without breaking automation threads" {
            # Trigger a guaranteed failure by querying status in a non-repo directory
            $tempDir = Join-Path $env:TEMP "GitMeNativeTest_$([System.IO.Path]::GetRandomFileName())"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                Push-Location $tempDir
                $result = Invoke-GitMeNative -Arguments @('status')

                # git status outside a repository returns exit code 128
                $result.ExitCode | Should -Be 128
                ($result.Output -join '') | Should -Match "fatal"
            }
            finally {
                Pop-Location
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
