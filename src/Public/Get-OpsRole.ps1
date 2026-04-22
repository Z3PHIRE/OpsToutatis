function Get-OpsRole {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [Alias('RoleId')]
        [string]$Role,

        [Parameter()]
        [switch]$ForceReload
    )

    if (-not $PSCmdlet.ShouldProcess('catalogue des rôles', 'Lister les rôles OpsToutatis')) {
        return @()
    }

    $roleDefinitions = Get-OpsRoleDefinitionsInternal -RoleId $Role -Force:$ForceReload
    return @($roleDefinitions | Sort-Object -Property Id)
}
