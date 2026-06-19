function New-GitMeInitialCommit {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$RepoName,
        [Parameter(Mandatory)][string]$PackVersion,
        [string]$DevName,
        [string]$DevEmail
    )
    if (-not $PSCmdlet.ShouldProcess($RepoName, 'Create initial git commit')) { return }

    Write-GitMeLog -Level Info -Message 'Staging all files...'
    $add = Invoke-GitMeNative @('add', '.')
    if ($add.ExitCode -ne 0) { throw 'git add failed' }

    $author = if ($DevEmail) { "$DevName <$DevEmail>" } else { $DevName }
    # Use Conventional Commits format for the initial commit message.
    # This ensures compatibility with automatic version bumping tools.
    $message = "feat: initial commit`n`n- Project: $RepoName`n- Version: $PackVersion`n- Author: $author"

    Write-GitMeLog -Level Info -Message 'Creating initial commit...'
    $commit = Invoke-GitMeNative @('commit', '-m', $message)
    if ($commit.ExitCode -eq 0) {
        Write-GitMeLog -Level Success -Message 'Initial commit created.'
    }
    else {
        Write-GitMeLog -Level Warn -Message 'Nothing to commit or commit failed (working tree may be clean).'
    }
}
