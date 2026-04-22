function Invoke-OpsDeploy {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('RoleId')]
        [ValidateNotNullOrEmpty()]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSec = 120,

        [Parameter()]
        [AllowNull()]
        [string]$RiskConfirmation,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$PassThru
    )

    $roleDefinition = Import-OpsRoleDefinition -RoleId $Role
    $resolvedTarget = Resolve-OpsDeployTarget -Target $Target
    $targetDisplayName = Get-OpsTargetDisplayName -TargetTable $resolvedTarget

    Write-Information ("Pré-vérification de la cible '{0}' pour le rôle '{1}'..." -f $targetDisplayName, $roleDefinition.DisplayName) -InformationAction Continue
    $targetInfo = Get-OpsTargetInfo -Target $resolvedTarget -TimeoutSec $TimeoutSec
    if (-not (Test-OpsRoleSupportsTarget -RoleDefinition $roleDefinition -TargetInfo $targetInfo)) {
        $supportedList = @($roleDefinition.SupportedOS) -join ', '
        throw "Le rôle '$($roleDefinition.DisplayName)' ne supporte pas la cible '$targetDisplayName'. OS détecté : $($targetInfo.Distribution). OS attendus : $supportedList."
    }

    $effectiveParameters = Get-OpsRoleDesiredParameters -RoleDefinition $roleDefinition -TargetTable $resolvedTarget -DesiredParameters $DesiredParameters -NonInteractive:$NonInteractive

    Write-OpsTransportLog -Level Decision -Message ("Deployment requested: role={0}; target={1}" -f $roleDefinition.Id, $targetDisplayName)

    $testFunctionName = [string]$roleDefinition.FunctionMap.Test
    $planFunctionName = [string]$roleDefinition.FunctionMap.Plan
    $applyFunctionName = [string]$roleDefinition.FunctionMap.Apply
    $verifyFunctionName = [string]$roleDefinition.FunctionMap.Verify

    $currentState = & $testFunctionName -Target $resolvedTarget -DesiredParameters $effectiveParameters
    $rawPlanResult = & $planFunctionName -Target $resolvedTarget -CurrentState $currentState -DesiredParameters $effectiveParameters
    $planActions = ConvertTo-OpsPlanActionList -PlanResult $rawPlanResult

    $planLines = Show-OpsDeploymentPlanInternal -RoleDefinition $roleDefinition -TargetDisplayName $targetDisplayName -PlanActions @($planActions)
    $planWasPresented = ($null -ne $planLines)
    if (-not $planWasPresented) {
        throw "Plan non affiché pour le rôle '$($roleDefinition.Id)'. L'exécution Apply est bloquée."
    }

    $isWhatIfMode = $WhatIfPreference
    if ($isWhatIfMode) {
        Write-Information 'Mode WhatIf activé : plan affiché, aucune action appliquée.' -InformationAction Continue

        $whatIfResult = [pscustomobject]@{
            RoleId         = $roleDefinition.Id
            TargetName     = $targetDisplayName
            WasWhatIf      = $true
            ApplyPerformed = $false
            VerifyPassed   = $false
            CurrentState   = $currentState
            PlanActions    = @($planActions)
            Message        = 'WhatIf : plan affiché uniquement.'
        }

        return $whatIfResult
    }

    if ($roleDefinition.RiskLevel -eq 'High') {
        $confirmationKeyword = [string]$roleDefinition.DisplayName
        Write-Information ("Rôle à risque élevé détecté : {0}" -f $roleDefinition.DisplayName) -InformationAction Continue
        Write-Information ("Confirmation explicite requise : retapez exactement '{0}'." -f $confirmationKeyword) -InformationAction Continue

        $providedConfirmation = $RiskConfirmation
        if ([string]::IsNullOrWhiteSpace($providedConfirmation)) {
            if ($NonInteractive.IsPresent) {
                throw "Confirmation explicite absente pour le rôle à risque élevé '$($roleDefinition.DisplayName)'. Exécution annulée."
            }

            $providedConfirmation = Read-Host ("Confirmez l'exécution du rôle '{0}'" -f $roleDefinition.DisplayName)
        }

        if ($providedConfirmation -ne $confirmationKeyword) {
            throw "Confirmation invalide. Exécution refusée pour le rôle à risque élevé '$($roleDefinition.DisplayName)'."
        }
    }

    $applyPerformed = $false
    $applyResult = $null
    $applyErrorMessage = $null

    if (@($planActions).Count -eq 0) {
        Write-Information 'État déjà conforme. Aucune action Apply nécessaire.' -InformationAction Continue
    }
    else {
        if (-not $PSCmdlet.ShouldProcess($targetDisplayName, ("Appliquer le rôle {0}" -f $roleDefinition.DisplayName))) {
            $skippedResult = [pscustomobject]@{
                RoleId         = $roleDefinition.Id
                TargetName     = $targetDisplayName
                WasWhatIf      = $false
                ApplyPerformed = $false
                VerifyPassed   = $false
                CurrentState   = $currentState
                PlanActions    = @($planActions)
                Message        = 'Apply annulé par confirmation ShouldProcess.'
            }

            if ($PassThru.IsPresent) {
                return $skippedResult
            }

            return $skippedResult
        }

        try {
            $applyResult = & $applyFunctionName -Target $resolvedTarget -PlanActions @($planActions) -DesiredParameters $effectiveParameters -CurrentState $currentState
            $applyPerformed = $true
        }
        catch {
            $applyErrorMessage = $_.Exception.Message
        }
    }

    # Verify must always run after plan phase, even when Apply failed or was skipped.
    $verifyResult = $null
    $verifyErrorMessage = $null
    $verifyPassed = $false
    try {
        $verifyResult = & $verifyFunctionName -Target $resolvedTarget -DesiredParameters $effectiveParameters -CurrentState $currentState -ApplyResult $applyResult

        if ($verifyResult -is [bool]) {
            $verifyPassed = [bool]$verifyResult
        }
        else {
            $verifyTable = ConvertTo-OpsPropertyTable -InputObject $verifyResult
            if ($null -ne $verifyTable -and $verifyTable.ContainsKey('IsCompliant')) {
                $verifyPassed = [bool]$verifyTable['IsCompliant']
            }
            else {
                $verifyPassed = $false
            }
        }
    }
    catch {
        $verifyErrorMessage = $_.Exception.Message
        $verifyPassed = $false
    }

    $rollbackResult = $null
    $rollbackErrorMessage = $null
    if (-not $verifyPassed -and $roleDefinition.HasRollback) {
        $rollbackFunctionName = [string]$roleDefinition.FunctionMap.Rollback
        try {
            $rollbackResult = & $rollbackFunctionName -Target $resolvedTarget -PlanActions @($planActions) -DesiredParameters $effectiveParameters -CurrentState $currentState -ApplyResult $applyResult -VerifyResult $verifyResult
        }
        catch {
            $rollbackErrorMessage = $_.Exception.Message
        }
    }

    $result = [pscustomobject]@{
        RoleId           = $roleDefinition.Id
        RoleDisplayName  = $roleDefinition.DisplayName
        TargetName       = $targetDisplayName
        WasWhatIf        = $false
        ApplyPerformed   = $applyPerformed
        VerifyPassed     = $verifyPassed
        CurrentState     = $currentState
        PlanActions      = @($planActions)
        ApplyResult      = $applyResult
        VerifyResult     = $verifyResult
        RollbackResult   = $rollbackResult
        Message          = ''
    }

    if (-not [string]::IsNullOrWhiteSpace($applyErrorMessage)) {
        $result.Message = "Apply en échec : $applyErrorMessage"
        throw "Échec du déploiement du rôle '$($roleDefinition.DisplayName)' sur '$targetDisplayName'. Détail : $applyErrorMessage"
    }

    if (-not [string]::IsNullOrWhiteSpace($verifyErrorMessage)) {
        $result.Message = "Verify en échec : $verifyErrorMessage"
        throw "Vérification finale impossible pour le rôle '$($roleDefinition.DisplayName)' sur '$targetDisplayName'. Détail : $verifyErrorMessage"
    }

    if (-not $verifyPassed) {
        $result.Message = 'Verify non conforme.'
        if (-not [string]::IsNullOrWhiteSpace($rollbackErrorMessage)) {
            throw "État non conforme après déploiement du rôle '$($roleDefinition.DisplayName)'. Rollback tenté mais en échec : $rollbackErrorMessage"
        }

        throw "État non conforme après déploiement du rôle '$($roleDefinition.DisplayName)'. Vérifiez les logs de session pour le détail."
    }

    if (@($planActions).Count -eq 0) {
        $result.Message = 'État déjà conforme.'
        Write-Information ("Déploiement terminé : état déjà conforme pour le rôle '{0}'." -f $roleDefinition.DisplayName) -InformationAction Continue
    }
    else {
        $result.Message = 'Déploiement appliqué et vérifié.'
        Write-Information ("Déploiement terminé : rôle '{0}' appliqué et vérifié sur '{1}'." -f $roleDefinition.DisplayName, $targetDisplayName) -InformationAction Continue
    }

    if ($PassThru.IsPresent) {
        return $result
    }

    return $result
}
