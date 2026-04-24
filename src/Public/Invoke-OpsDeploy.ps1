function Invoke-OpsDeploy {
    [CmdletBinding(DefaultParameterSetName = 'RoleTarget', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'RoleTarget')]
        [Alias('RoleId')]
        [ValidateNotNullOrEmpty()]
        [string]$Role,

        [Parameter(Mandatory = $true, ParameterSetName = 'RoleTarget')]
        [AllowNull()]
        [object]$Target,

        [Parameter(ParameterSetName = 'RoleTarget')]
        [AllowNull()]
        [hashtable]$DesiredParameters,

        [Parameter(Mandatory = $true, ParameterSetName = 'Playbook')]
        [ValidateNotNullOrEmpty()]
        [string]$Playbook,

        [Parameter(ParameterSetName = 'Playbook')]
        [string]$InventoryPath,

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

    if ($PSCmdlet.ParameterSetName -eq 'Playbook') {
        $loadedPlaybook = $null
        if ([string]::IsNullOrWhiteSpace($InventoryPath)) {
            $loadedPlaybook = Import-OpsPlaybook -Path $Playbook -WhatIf:$false
        }
        else {
            Import-OpsInventory -Path $InventoryPath -WhatIf:$false | Out-Null
            $loadedPlaybook = Import-OpsPlaybook -Path $Playbook -InventoryPath $InventoryPath -WhatIf:$false
        }

        $playbookTable = ConvertTo-OpsPropertyTable -InputObject $loadedPlaybook.Data
        if ($null -eq $playbookTable -or -not $playbookTable.ContainsKey('Targets')) {
            throw "Playbook invalide '$Playbook' : clé Targets manquante."
        }

        $deploymentResults = @()
        $targetEntries = @($playbookTable['Targets'])
        $targetCount = @($targetEntries).Count
        $targetIndex = 0

        foreach ($targetEntry in $targetEntries) {
            $targetIndex += 1
            $targetEntryTable = ConvertTo-OpsPropertyTable -InputObject $targetEntry
            if ($null -eq $targetEntryTable) {
                throw "Entrée de playbook invalide à l'index $targetIndex."
            }

            if (-not $targetEntryTable.ContainsKey('Host')) {
                throw "Entrée de playbook invalide à l'index $targetIndex : clé Host manquante."
            }

            if (-not $targetEntryTable.ContainsKey('Roles')) {
                throw "Entrée de playbook invalide à l'index $targetIndex : clé Roles manquante."
            }

            $hostName = [string]$targetEntryTable['Host']
            $roleList = @($targetEntryTable['Roles'])
            if (@($roleList).Count -eq 0) {
                throw "Entrée de playbook invalide pour l'hôte '$hostName' : au moins un rôle est requis."
            }

            Write-Information ("Cible {0}/{1}: {2}" -f $targetIndex, $targetCount, $hostName) -InformationAction Continue
            $resolvedTarget = Resolve-OpsDeployTarget -Target $hostName

            $roleParametersByName = $null
            if ($targetEntryTable.ContainsKey('Parameters')) {
                $roleParametersByName = ConvertTo-OpsPropertyTable -InputObject $targetEntryTable['Parameters']
            }

            foreach ($roleName in $roleList) {
                $roleNameText = [string]$roleName
                if ([string]::IsNullOrWhiteSpace($roleNameText)) {
                    throw "Nom de rôle vide détecté pour l'hôte '$hostName'."
                }

                Write-Information ("Exécution du rôle '{0}' sur '{1}'..." -f $roleNameText, $hostName) -InformationAction Continue

                $invokeArguments = @{
                    Role           = $roleNameText
                    Target         = $resolvedTarget
                    TimeoutSec     = $TimeoutSec
                    NonInteractive = $NonInteractive.IsPresent
                    PassThru       = $true
                    Confirm        = $false
                }

                if (-not [string]::IsNullOrWhiteSpace($RiskConfirmation)) {
                    $invokeArguments['RiskConfirmation'] = $RiskConfirmation
                }

                if ($null -ne $roleParametersByName -and $roleParametersByName.ContainsKey($roleNameText)) {
                    $roleSpecificParameters = ConvertTo-OpsPropertyTable -InputObject $roleParametersByName[$roleNameText]
                    if ($null -ne $roleSpecificParameters) {
                        $invokeArguments['DesiredParameters'] = $roleSpecificParameters
                    }
                }

                $deploymentResults += Invoke-OpsDeploy @invokeArguments
            }
        }

        $playbookResult = [pscustomobject]@{
            PlaybookPath        = [string]$loadedPlaybook.Path
            TargetCount         = $targetCount
            RoleInvocationCount = @($deploymentResults).Count
            WasWhatIf           = [bool]$WhatIfPreference
            Results             = @($deploymentResults)
        }

        if ($PassThru.IsPresent) {
            return $playbookResult
        }

        return $playbookResult
    }

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
