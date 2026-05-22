function New-LocalRepository {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$RepoName
    )
    if (-not $PSCmdlet.ShouldProcess($RemotePath, 'Initialize local bare git repository')) { return }

    Write-GitMeLog -Level Info -Message "Configuring local/CIFS remote at '$RemotePath'..."

    if (-not (Test-Path $RemotePath)) {
        try {
            New-Item -ItemType Directory -Path $RemotePath -Force | Out-Null
            Write-GitMeLog -Level Success -Message "Created remote directory: $RemotePath"
        }
        catch {
            Write-GitMeLog -Level Error -Message "Failed to create remote directory: $_"
            throw
        }
    }

    $barePath = Join-Path $RemotePath "$RepoName.git"
    if (-not (Test-Path (Join-Path $barePath 'HEAD'))) {
        try {
            $null = New-Item -ItemType Directory -Path $barePath -Force
            
            # Safe location shift using try/finally block to prevent user state leakage
            try {
                Push-Location $barePath
                $init = Invoke-GitMeNative @('init', '--bare')
                if ($init.ExitCode -ne 0) { throw 'git init --bare failed' }
                Write-GitMeLog -Level Success -Message "Initialised bare repository: $barePath"
            }
            finally {
                Pop-Location
            }
        }
        catch {
            Write-GitMeLog -Level Error -Message "Failed to initialise bare repository: $_"
            throw
        }
    }
    else {
        Write-GitMeLog -Level Info -Message "Bare repository already exists at $barePath"
    }

    $uri = if ($barePath -match '^\\') {
        $barePath
    }
    else {
        $full = (Resolve-Path $barePath).Path
        if ($full -match '^[A-Za-z]:') {
            'file:///' + ($full -replace '\\', '/')
        }
        else {
            'file://' + ($full -replace '\\', '/')
        }
    }
    return [pscustomobject]@{ CloneUrl = $uri; HtmlUrl = $barePath; Provider = 'Local' }
}