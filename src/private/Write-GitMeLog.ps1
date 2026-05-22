function Write-GitMeLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Info', 'Warn', 'Success', 'Error')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $ESC = [char]27
    $Cyan = "${ESC}[36m"
    $Yellow = "${ESC}[33m"
    $Green = "${ESC}[32m"
    $Red = "${ESC}[31m"
    $Reset = "${ESC}[0m"
    switch ($Level) {
        'Info' { if ($script:GitMeLogLevel -ne 'Quiet') { [Console]::Out.WriteLine("${Cyan}[INFO]${Reset} $Message") } }
        'Warn' { [Console]::Out.WriteLine("${Yellow}[WARN]${Reset} $Message") }
        'Success' { if ($script:GitMeLogLevel -ne 'Quiet') { [Console]::Out.WriteLine("${Green}[SUCCESS]${Reset} $Message") } }
        'Error' { [Console]::Error.WriteLine("${Red}[ERROR]${Reset} $Message") }
    }
}