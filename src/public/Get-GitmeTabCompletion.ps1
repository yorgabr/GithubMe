function Get-GitmeTabCompletion {
    <#
    .SYNOPSIS
        Returns the list of supported providers for tab-completion scripting.
    #>
    [CmdletBinding()]
    param()
    return @('GitHub', 'GitLab', 'Local')
}