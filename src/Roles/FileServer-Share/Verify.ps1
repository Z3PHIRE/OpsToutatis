function Test-FileServer-ShareApplied {
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

    $stateAfterApply = Test-FileServer-ShareRole -Target $Target -DesiredParameters $DesiredParameters
    $stateTable = ConvertTo-OpsPropertyTable -InputObject $stateAfterApply

    $isCompliant = $false
    if ($null -ne $stateTable -and $stateTable.ContainsKey('IsCompliant')) {
        $isCompliant = [bool]$stateTable['IsCompliant']
    }

    $message = 'FileServer-Share conforme : dossier, ACL NTFS et permissions SMB alignés.'
    if (-not $isCompliant) {
        $message = 'FileServer-Share non conforme après Apply. Vérifiez ACL NTFS et droits SMB.'
    }

    return [pscustomobject]@{
        IsCompliant = $isCompliant
        Message     = $message
        ShareName   = [string]$stateTable['ExpectedShareName']
    }
}
