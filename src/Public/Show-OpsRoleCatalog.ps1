function Show-OpsRoleCatalog {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [string]$Category,

        [Parameter()]
        [string]$SupportedOS
    )

    if (-not $PSCmdlet.ShouldProcess('catalogue des rôles', 'Afficher le catalogue OpsToutatis')) {
        return @()
    }

    $allRoles = @(Get-OpsRole)
    $filteredRoles = @($allRoles)

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $filteredRoles = @(
            $filteredRoles | Where-Object {
                ([string]$_.Category) -like ("*{0}*" -f $Category)
            }
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($SupportedOS)) {
        $filteredRoles = @(
            $filteredRoles | Where-Object {
                @($_.SupportedOS) -contains $SupportedOS
            }
        )
    }

    if (@($filteredRoles).Count -eq 0) {
        Write-Output 'Aucun rôle ne correspond aux filtres demandés.'
        return @()
    }

    $catalogLines = @()
    foreach ($roleDefinition in $filteredRoles) {
        $catalogLines += ("- {0} ({1})" -f $roleDefinition.DisplayName, $roleDefinition.Id)
        $catalogLines += ("  Catégorie : {0}" -f $roleDefinition.Category)
        $catalogLines += ("  Risque : {0} | Durée estimée : {1} min" -f $roleDefinition.RiskLevel, $roleDefinition.EstimatedDurationMin)
        $catalogLines += ("  OS supportés : {0}" -f (@($roleDefinition.SupportedOS) -join ', '))
        $catalogLines += ''
    }

    Initialize-OpsUiRuntime
    $writeOpsBoxCommand = Get-Command -Name Write-OpsBox -ErrorAction SilentlyContinue
    if ($null -ne $writeOpsBoxCommand) {
        Write-OpsBox -Title 'Catalogue des rôles OpsToutatis' -ContentLines $catalogLines -Ascii | Out-Null
    }
    else {
        foreach ($catalogLine in $catalogLines) {
            Write-Output $catalogLine
        }
    }

    return @($filteredRoles)
}
