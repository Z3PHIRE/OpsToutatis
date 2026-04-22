function Test-Demo-HelloApplied {
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

    $stateAfterApply = Test-Demo-HelloRole -Target $Target -DesiredParameters $DesiredParameters
    $stateTable = ConvertTo-OpsPropertyTable -InputObject $stateAfterApply
    $isCompliant = $false
    if ($null -ne $stateTable -and $stateTable.ContainsKey('IsCompliant')) {
        $isCompliant = [bool]$stateTable['IsCompliant']
    }

    $message = 'Le rôle Demo-Hello est conforme.'
    if (-not $isCompliant) {
        $message = "Le rôle Demo-Hello n'est pas conforme après Apply."
    }

    return [pscustomobject]@{
        IsCompliant = $isCompliant
        Message     = $message
        OutputPath  = [string]$stateTable['OutputPath']
    }
}
