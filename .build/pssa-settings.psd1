@{
    Rules = @{
        PSPlaceOpenBrace           = @{
            Enable      = $true
            OnSameLine  = $true
            NewLineAfter = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentWhitespace  = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $false
            CheckSeparator                          = $true
            CheckParameter                          = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
        PSAlignAssignmentStatement = @{
            Enable = $false
        }
        PSAvoidUsingCmdletAliases  = @{ Enable = $true }
        PSAvoidUsingPlainTextForPassword = @{ Enable = $true }
        PSAvoidUsingConvertToSecureStringWithPlainText = @{ Enable = $true }
        PSAvoidUsingInvokeExpression = @{ Enable = $true }
    }
    ExcludeRules = @(
        'PSUseSingularNouns'
        'PSReviewUnusedParameter'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
