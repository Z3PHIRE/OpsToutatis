function Write-OpsLog {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Info', 'Warn', 'Error', 'Action', 'Decision')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Message,

        [Parameter()]
        [switch]$PassThru
    )

    $session = Get-OpsSession
    if ($null -eq $session) {
        throw "Aucune session active. Exécutez New-OpsSession avant d'écrire des logs."
    }

    $safeMessage = Format-OpsRedactedString -InputText $Message
    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffK')
    $logLine = ('[{0}] [{1}] {2}' -f $timestamp, $Level.ToUpperInvariant(), $safeMessage)

    if (-not $PSCmdlet.ShouldProcess($session.SessionPath, "Write $Level log entry")) {
        return
    }

    Add-Content -LiteralPath $session.SessionLogPath -Value $logLine -Encoding UTF8

    switch ($Level) {
        'Action' {
            Add-Content -LiteralPath $session.ActionsLogPath -Value $logLine -Encoding UTF8
            $session.ActionCount = [int]$session.ActionCount + 1
        }
        'Decision' {
            Add-Content -LiteralPath $session.DecisionsLogPath -Value $logLine -Encoding UTF8
            $session.DecisionCount = [int]$session.DecisionCount + 1
        }
        'Error' {
            Add-Content -LiteralPath $session.ErrorsLogPath -Value $logLine -Encoding UTF8
            $session.ErrorCount = [int]$session.ErrorCount + 1
        }
        default {
        }
    }

    if ($PassThru.IsPresent) {
        Write-Output $logLine
    }
}
