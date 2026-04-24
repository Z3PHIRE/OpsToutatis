function Test-DNS-PrimaryApplied {
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

    $stateAfterApply = Test-DNS-PrimaryRole -Target $Target -DesiredParameters $DesiredParameters
    $stateTable = ConvertTo-OpsPropertyTable -InputObject $stateAfterApply

    $isCompliant = $false
    if ($null -ne $stateTable -and $stateTable.ContainsKey('IsCompliant')) {
        $isCompliant = [bool]$stateTable['IsCompliant']
    }

    $message = 'DNS-Primary conforme : zone primaire autonome opérationnelle.'
    if (-not $isCompliant) {
        $message = 'DNS-Primary non conforme après Apply. Vérifiez le rôle DNS et la zone non AD-integrated.'
    }

    return [pscustomobject]@{
        IsCompliant = $isCompliant
        Message     = $message
        ZoneName    = [string]$stateTable['ExpectedZoneName']
    }
}
