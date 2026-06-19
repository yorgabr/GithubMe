function New-RemoteRepository {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GitHub', 'GitLab')]
        [string]$Provider,
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Token,
        [bool]$IsPrivate = $false,
        [string]$ApiBaseUrl
    )

    if (-not $PSCmdlet.ShouldProcess("$Provider/$Owner/$Name", 'Create remote repository')) { return }

    if ($Provider -eq 'GitHub') {
        $apiUrl = if ($ApiBaseUrl) { $ApiBaseUrl.TrimEnd('/') } else { 'https://api.github.com' }
        $visibility = if ($IsPrivate) { 'private' } else { 'public' }
        Write-GitMeLog -Level Info -Message "Creating $visibility GitHub repository '$Name'..."

        $uri = "$apiUrl/user/repos"
        try {
            $me = Invoke-RestMethod -Uri "$apiUrl/user" -Headers @{Authorization = "Bearer $Token" } -ErrorAction Stop
            if ($Owner -ne $me.login) { $uri = "$apiUrl/orgs/$Owner/repos" }
        }
        catch { Write-GitMeLog -Level Warn -Message 'Could not verify GitHub identity; assuming personal account.' }

        $headers = @{
            Authorization  = "Bearer $Token"
            Accept         = 'application/vnd.github.v3+json'
            'Content-Type' = 'application/json'
        }
        $body = @{
            name        = $Name
            private     = [bool]$IsPrivate
            auto_init   = $false
            description = "Repository created by GitMe"
        } | ConvertTo-Json

        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
            Write-GitMeLog -Level Success -Message "Repository created at $($response.html_url)"
            return [pscustomobject]@{
                CloneUrl = $response.clone_url
                HtmlUrl  = $response.html_url
                Provider = 'GitHub'
            }
        }
        catch {
            # Hybrid status code parsing for cross-compatibility between PS 5.1 and PS 7+.
            # PS 5.1 places the response on $_.Exception.Response while PS 7+ uses $_.Response.
            # We also guard against the property not existing at all (e.g., connection refused).
            $code = 0
            try {
                if ($null -ne $_.Exception -and $null -ne $_.Exception.Response) {
                    $code = [int]$_.Exception.Response.StatusCode
                }
            }
            catch {
                # Property does not exist; leave $code as 0
            }

            $detail = switch ($code) {
                422 { "Repository '$Name' already exists or name is invalid." }
                401 { "Authentication failed — verify the token has 'repo' scope." }
                403 { "Permission denied — token lacks repository creation rights." }
                default { "GitHub API error (${code}): $($_.Exception.Message)" }
            }
            Write-GitMeLog -Level Error -Message $detail
            throw
        }
    }
    elseif ($Provider -eq 'GitLab') {
        $apiUrl = if ($ApiBaseUrl) { $ApiBaseUrl.TrimEnd('/') } else { 'https://gitlab.com/api/v4' }
        $visibilityLevel = if ($IsPrivate) { 'private' } else { 'public' }
        Write-GitMeLog -Level Info -Message "Creating $visibilityLevel GitLab project '$Name'..."

        $headers = @{
            'PRIVATE-TOKEN' = $Token
            'Content-Type'  = 'application/json'
        }
        $body = @{
            name                   = $Name
            visibility             = $visibilityLevel
            initialize_with_readme = $false
        } | ConvertTo-Json

        $uri = "$apiUrl/projects"
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
            Write-GitMeLog -Level Success -Message "Project created at $($response.web_url)"
            return [pscustomobject]@{
                CloneUrl = $response.http_url_to_repo
                HtmlUrl  = $response.web_url
                Provider = 'GitLab'
            }
        }
        catch {
            # Hybrid status code parsing — same defensive approach as GitHub block above
            $code = 0
            try {
                if ($null -ne $_.Exception -and $null -ne $_.Exception.Response) {
                    $code = [int]$_.Exception.Response.StatusCode
                }
            }
            catch {
                # Property does not exist; leave $code as 0
            }

            $detail = switch ($code) {
                400 { "Project '$Name' already exists or path is invalid." }
                401 { "Authentication failed — verify your GitLab personal access token." }
                403 { "Permission denied — token lacks project creation rights." }
                default { "GitLab API error (${code}): $($_.Exception.Message)" }
            }
            Write-GitMeLog -Level Error -Message $detail
            throw
        }
    }
}
