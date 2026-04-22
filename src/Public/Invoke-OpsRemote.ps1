function Invoke-OpsRemote {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object[]]$ArgumentList = @(),

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSec = 120
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $transportName = Get-OpsTransportName -TargetTable $targetTable
    Test-OpsTransportContract -TransportName $transportName | Out-Null

    $targetLabel = Get-OpsTransportAddress -TargetTable $targetTable
    if ($targetTable.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$targetTable['Name'])) {
        $targetLabel = [string]$targetTable['Name']
    }

    if (-not $PSCmdlet.ShouldProcess($targetLabel, ("Exécuter une commande distante via {0}" -f $transportName))) {
        return $null
    }

    try {
        switch ($transportName) {
            'Local' {
                return Invoke-LocalCommand -Target $targetTable -ScriptBlock $ScriptBlock -ArgumentList @($ArgumentList) -TimeoutSec $TimeoutSec
            }
            'WinRM' {
                return Invoke-WinRMCommand -Target $targetTable -ScriptBlock $ScriptBlock -ArgumentList @($ArgumentList) -TimeoutSec $TimeoutSec
            }
            'SSH' {
                return Invoke-SSHCommand -Target $targetTable -ScriptBlock $ScriptBlock -ArgumentList @($ArgumentList) -TimeoutSec $TimeoutSec
            }
            default {
                throw "Transport non supporté '$transportName'."
            }
        }
    }
    catch {
        $errorMessage = "Échec d'exécution distante sur '$targetLabel' via $transportName. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
}
