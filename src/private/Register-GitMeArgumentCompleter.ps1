function Register-GitMeArgumentCompleter {
    [CmdletBinding()]
    param()
    $scriptBlock = {
        param(
            $commandName,
            $parameterName,
            $wordToComplete,
            $commandAst,
            $fakeBoundParameters
        )
        switch ($parameterName) {
            'Provider' {
                'GitHub', 'GitLab', 'Local' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
            'ApiBaseUrl' {
                'https://api.github.com', 'https://gitlab.com/api/v4' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
        }
    }
    Register-ArgumentCompleter -CommandName 'Invoke-Gitme', 'gitme' -ParameterName 'Provider'   -ScriptBlock $scriptBlock
    Register-ArgumentCompleter -CommandName 'Invoke-Gitme', 'gitme' -ParameterName 'ApiBaseUrl' -ScriptBlock $scriptBlock
}