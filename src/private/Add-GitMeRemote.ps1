function Add-GitMeRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RemoteUrl,
        [Parameter(Mandatory)][string]$PackVersion
    )
    Write-GitMeLog -Level Info -Message "Setting remote origin to $RemoteUrl..."

    $add = Invoke-GitMeNative @('remote', 'add', 'origin', $RemoteUrl)
    if ($add.ExitCode -ne 0) {
        Invoke-GitMeNative @('remote', 'set-url', 'origin', $RemoteUrl) | Out-Null
    }

    $branchResult = Invoke-GitMeNative @('branch', '--show-current')
    $branch = if ($branchResult.ExitCode -eq 0 -and $branchResult.Output) { $branchResult.Output } else { 'main' }

    Write-GitMeLog -Level Info -Message "Pushing branch '$branch'..."
    $pushBranch = Invoke-GitMeNative @('push', '-u', 'origin', $branch)
    if ($pushBranch.ExitCode -eq 0) { Write-GitMeLog -Level Success -Message "Branch '$branch' pushed." }
    else { Write-GitMeLog -Level Warn -Message "Failed to push branch '$branch'." }

    Write-GitMeLog -Level Info -Message "Pushing tag v$PackVersion..."
    $pushTag = Invoke-GitMeNative @('push', 'origin', "v$PackVersion")
    if ($pushTag.ExitCode -eq 0) { Write-GitMeLog -Level Success -Message "Tag v$PackVersion pushed." }
    else { Write-GitMeLog -Level Warn -Message "Failed to push tag v$PackVersion." }
}