function New-GitMeVersionTag {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$PackVersion,
        [Parameter(Mandatory)][string]$RepoName,
        [string]$DevName,
        [string]$DevEmail,
        [switch]$Force
    )
    if (-not $PSCmdlet.ShouldProcess("v$PackVersion", 'Create annotated git tag')) { return }

    Write-GitMeLog -Level Info -Message "Tagging repository as v$PackVersion..."

    $existing = (Invoke-GitMeNative @('tag', '-l', "v$PackVersion")).Output
    if ($existing) {
        if ($Force) {
            Write-GitMeLog -Level Warn -Message "Tag v$PackVersion exists — deleting (-Force set)."
            $del = Invoke-GitMeNative @('tag', '-d', "v$PackVersion")
            if ($del.ExitCode -ne 0) {
                Write-GitMeLog -Level Warn -Message 'Could not delete existing tag; skipping tag creation.'
                return
            }
        }
        else {
            Write-GitMeLog -Level Warn -Message "Tag v$PackVersion already exists. Use -Force to recreate."
            return
        }
    }

    $author = if ($DevEmail) { "$DevName <$DevEmail>" } else { $DevName }
    $tagMessage = "Release v$PackVersion`n`nInitial release of $RepoName.`nAuthor: $author"

    $tag = Invoke-GitMeNative @('tag', '-a', "v$PackVersion", '-m', $tagMessage)
    if ($tag.ExitCode -eq 0) {
        Write-GitMeLog -Level Success -Message "Tag v$PackVersion created."
    }
    else {
        # Non-fatal: tag creation can fail if there are no commits yet
        Write-GitMeLog -Level Warn -Message "Failed to create tag v$PackVersion."
    }
}
