@{
    Rules = @{
        PSAvoidUsingCmdletAliases                      = @{ Enable = $true }
        PSAvoidUsingPlainTextForPassword               = @{ Enable = $true }
        PSAvoidUsingConvertToSecureStringWithPlainText = @{ Enable = $true }
        PSAvoidUsingInvokeExpression                   = @{ Enable = $true }
    }
    ExcludeRules = @(
        'PSUseSingularNouns'
        'PSReviewUnusedParameter'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
