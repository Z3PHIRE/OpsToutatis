function Test-ADDS-ForestApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters,

        [Parameter()]
        [AllowNull()]
        [object]$CurrentState,

        [Parameter()]
        [AllowNull()]
        [object]$ApplyResult
    )

    $stateAfterApply = Test-ADDS-ForestRole -Target $Target -DesiredParameters $DesiredParameters
    $stateTable = ConvertTo-OpsPropertyTable -InputObject $stateAfterApply

    $isCompliant = $false
    if ($null -ne $stateTable -and $stateTable.ContainsKey('IsCompliant')) {
        $isCompliant = [bool]$stateTable['IsCompliant']
    }

    $message = 'ADDS-Forest conforme : contrôleur de domaine opérationnel et DNS résolu.'
    if (-not $isCompliant) {
        $message = 'ADDS-Forest non conforme après Apply. Vérifiez AD DS, DNS et redémarrage. Rollback forêt : manuel uniquement.'
    }

    return [pscustomobject]@{
        IsCompliant = $isCompliant
        Message     = $message
        DomainName  = [string]$stateTable['ExpectedDomainName']
    }
}
