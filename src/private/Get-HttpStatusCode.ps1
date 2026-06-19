function Get-HttpStatusCode {
    <#
    .SYNOPSIS
        Extracts the HTTP status code from a caught ErrorRecord.
        Compatible with both Windows PowerShell 5.1 and PowerShell 7+.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    if ($null -eq $exception) {
        return 0
    }

    # ── Strategy 1: read Response.StatusCode from the direct exception ────────
    # We use the PowerShell property accessor inside a try/catch so that both
    # real CLR properties (HttpWebResponse.StatusCode) and NoteProperties added
    # via Add-Member are handled without empty catch blocks.
    $response = $null
    try { $response = $exception.Response } catch { $response = $null }

    if ($null -ne $response) {
        $statusCode = $null
        try { $statusCode = $response.StatusCode } catch { $statusCode = $null }

        if ($null -ne $statusCode) {
            if ($statusCode -is [System.Net.HttpStatusCode]) {
                return [int]$statusCode
            }
            if ($statusCode -is [int]) {
                return $statusCode
            }
            $asInt = $statusCode -as [int]
            if ($null -ne $asInt) { return $asInt }
        }
    }

    # ── Strategy 2: inner exception (response may be wrapped one level deep) ──
    $inner = $null
    try { $inner = $exception.InnerException } catch { $inner = $null }

    if ($null -ne $inner) {
        $innerResponse = $null
        try { $innerResponse = $inner.Response } catch { $innerResponse = $null }

        if ($null -ne $innerResponse) {
            $statusCode = $null
            try { $statusCode = $innerResponse.StatusCode } catch { $statusCode = $null }

            if ($null -ne $statusCode) {
                if ($statusCode -is [System.Net.HttpStatusCode]) { return [int]$statusCode }
                if ($statusCode -is [int]) { return $statusCode }
                $asInt = $statusCode -as [int]
                if ($null -ne $asInt) { return $asInt }
            }
        }
    }

    return 0
}
