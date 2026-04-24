function Test-ADDS-AdditionalDCApplied {
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

    $stateAfterApply = Test-ADDS-AdditionalDCRole -Target $Target -DesiredParameters $DesiredParameters
    $stateTable = ConvertTo-OpsPropertyTable -InputObject $stateAfterApply

    $isCompliant = $false
    if ($null -ne $stateTable -and $stateTable.ContainsKey('IsCompliant')) {
        $isCompliant = [bool]$stateTable['IsCompliant']
    }

    $message = 'ADDS-AdditionalDC conforme : contrôleur additionnel opérationnel.'
    if (-not $isCompliant) {
        $message = 'ADDS-AdditionalDC non conforme après Apply. Vérifiez la promotion AD DS et le redémarrage manuel.'
    }

    return [pscustomobject]@{
        IsCompliant = $isCompliant
        Message     = $message
        DomainName  = [string]$stateTable['ExpectedDomainName']
    }
}
