function Initialize-GitMeRepository {
    [CmdletBinding()]
    param(
        [string]$DevName,
        [string]$DevEmail,
        [bool]$SetLocalConfig = $true,
        [switch]$Force
    )

    if (Test-Path '.git') {
        if (-not $Force) {
            Write-GitMeLog -Level Info -Message 'Git repository already exists — skipping init.'
        }
        else {
            Write-GitMeLog -Level Warn -Message 'Git repository already exists but -Force is set; reinitialising is not destructive.'
        }
    }
    else {
        Write-GitMeLog -Level Info -Message 'Initializing git repository...'
        $result = Invoke-GitMeNative @('init', '-b', 'main')
        if ($result.ExitCode -ne 0) { throw 'git init failed' }
        Write-GitMeLog -Level Success -Message 'Git repository initialized on branch main.'
    }

    if ($SetLocalConfig) {
        Write-GitMeLog -Level Info -Message 'Writing local git identity config...'
        if ($DevName) {
            $r = Invoke-GitMeNative @('config', '--local', 'user.name', $DevName)
            if ($r.ExitCode -eq 0) { Write-GitMeLog -Level Success -Message "Set local user.name = '$DevName'" }
        }
        if ($DevEmail) {
            $r = Invoke-GitMeNative @('config', '--local', 'user.email', $DevEmail)
            if ($r.ExitCode -eq 0) { Write-GitMeLog -Level Success -Message "Set local user.email = '$DevEmail'" }
        }
        $localName = (Invoke-GitMeNative @('config', '--local', 'user.name')).Output
        $localEmail = (Invoke-GitMeNative @('config', '--local', 'user.email')).Output
        Write-GitMeLog -Level Info -Message "Active local config: user.name='$localName' user.email='$localEmail'"
    }
    else {
        Write-GitMeLog -Level Info -Message 'Using global git config (local config not modified).'
    }
}