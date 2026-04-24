function Test-DHCP-ScopeApplied {
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

    $stateAfterApply = Test-DHCP-ScopeRole -Target $Target -DesiredParameters $DesiredParameters
    $stateTable = ConvertTo-OpsPropertyTable -InputObject $stateAfterApply

    $isCompliant = $false
    if ($null -ne $stateTable -and $stateTable.ContainsKey('IsCompliant')) {
        $isCompliant = [bool]$stateTable['IsCompliant']
    }

    $message = 'DHCP-Scope conforme : scope et options DHCP alignés.'
    if (-not $isCompliant) {
        $message = 'DHCP-Scope non conforme après Apply. Vérifiez l''autorisation AD DHCP et les options de scope.'
    }

    return [pscustomobject]@{
        IsCompliant = $isCompliant
        Message     = $message
        ScopeName   = [string]$stateTable['ExpectedScopeName']
    }
}

