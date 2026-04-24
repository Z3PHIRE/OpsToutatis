function Test-IIS-SiteBasicApplied {
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

    $stateAfterApply = Test-IIS-SiteBasicRole -Target $Target -DesiredParameters $DesiredParameters
    $stateTable = ConvertTo-OpsPropertyTable -InputObject $stateAfterApply

    $isCompliant = $false
    if ($null -ne $stateTable -and $stateTable.ContainsKey('IsCompliant')) {
        $isCompliant = [bool]$stateTable['IsCompliant']
    }

    $message = 'IIS-SiteBasic conforme : site, app pool et binding opérationnels.'
    if (-not $isCompliant) {
        $message = 'IIS-SiteBasic non conforme après Apply. Vérifiez IIS, app pool, chemin et binding.'
    }

    return [pscustomobject]@{
        IsCompliant = $isCompliant
        Message     = $message
        SiteName    = [string]$stateTable['ExpectedSiteName']
    }
}
