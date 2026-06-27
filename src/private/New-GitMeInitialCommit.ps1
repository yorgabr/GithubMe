function New-GitMeInitialCommit {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$RepoName,
        [Parameter(Mandatory)][string]$PackVersion,
        [string]$DevName,
        [string]$DevEmail
    )
    if (-not $PSCmdlet.ShouldProcess($RepoName, 'Create initial git commit')) { return }

    # ── Guard: abort if the working directory contains no files to commit ─────
    # git add returns exit code 128 on a completely empty tree.  Rather than
    # letting a cryptic native error surface, we detect the condition early and
    # emit an actionable message.
    Write-GitMeLog -Level Debug -Message "Scanning working tree for committable files in '$(Get-Location)'."

    $items = Get-ChildItem -Path (Get-Location) -Force |
        Where-Object { $_.Name -ne '.git' }

    Write-GitMeLog -Level Debug -Message "Items found (excluding .git): $($items.Count)"

    if (-not $items) {
        throw "The directory '$(Get-Location)' is empty. Add at least one file before running gitme."
    }

    Write-GitMeLog -Level Info -Message 'Staging all files...'
    $add = Invoke-GitMeNative @('add', '.')

    Write-GitMeLog -Level Debug -Message "git add exit code: $($add.ExitCode)"
    Write-GitMeLog -Level Debug -Message "git add output: $($add.Output -join ' ')"

    if ($add.ExitCode -ne 0) {
        $detail = ($add.Output -join ' ').Trim()
        throw "git add failed (exit $($add.ExitCode))$(if ($detail) { ": $detail" })"
    }

    $author  = if ($DevEmail) { "$DevName <$DevEmail>" } else { $DevName }
    $message = "feat: initial commit`n`n- Project: $RepoName`n- Version: $PackVersion`n- Author: $author"

    Write-GitMeLog -Level Info    -Message 'Creating initial commit...'
    Write-GitMeLog -Level Debug   -Message "Commit message: $($message -replace "`n", ' | ')"

    $commit = Invoke-GitMeNative @('commit', '-m', $message)

    Write-GitMeLog -Level Debug -Message "git commit exit code: $($commit.ExitCode)"
    Write-GitMeLog -Level Debug -Message "git commit output: $($commit.Output -join ' ')"

    if ($commit.ExitCode -eq 0) {
        Write-GitMeLog -Level Success -Message 'Initial commit created.'
    }
    else {
        Write-GitMeLog -Level Warn -Message 'Nothing to commit or commit failed (working tree may be clean).'
    }
}
