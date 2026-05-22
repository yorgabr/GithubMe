function Show-GitMeInstruction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$PackVersion,
        [string]$RemoteUrl
    )
    [Console]::Out.WriteLine('')
    Write-GitMeLog -Level Info -Message 'Manual steps to connect to remote:'
    if ($Provider -eq 'Local') {
        Write-GitMeLog -Level Info -Message "  git remote add origin '$RemoteUrl'"
    }
    else {
        Write-GitMeLog -Level Info -Message "  git remote add origin https://$Provider.com/$User/$Repo.git"
    }
    Write-GitMeLog -Level Info -Message '  git push -u origin main'
    Write-GitMeLog -Level Info -Message "  git push origin v$PackVersion"
    [Console]::Out.WriteLine('')

    $currentName = (Invoke-GitMeNative @('config', 'user.name')).Output
    $currentEmail = (Invoke-GitMeNative @('config', 'user.email')).Output
    Write-GitMeLog -Level Info -Message "Active git identity: $currentName <$currentEmail>"
}