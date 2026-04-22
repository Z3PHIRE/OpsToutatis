function Test-OpsPlaybook {
    [CmdletBinding(DefaultParameterSetName = 'Path', SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Data')]
        [AllowNull()]
        [object]$PlaybookData,

        [Parameter(ParameterSetName = 'Data')]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath = '(mémoire)',

        [Parameter()]
        [string]$InventoryPath,

        [Parameter()]
        [AllowNull()]
        [object]$InventoryData,

        [Parameter()]
        [switch]$PassThru
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $loadedPlaybook = Import-OpsDataFile -Path $Path -DocumentKind 'playbook'
        $PlaybookData = $loadedPlaybook.Data
        $SourcePath = $loadedPlaybook.Path
    }

    if (-not $PSCmdlet.ShouldProcess($SourcePath, 'Valider le schéma du playbook OpsToutatis')) {
        return $null
    }

    $inventorySourcePath = '(inventaire courant)'
    if (-not [string]::IsNullOrWhiteSpace($InventoryPath)) {
        $loadedInventory = Import-OpsDataFile -Path $InventoryPath -DocumentKind 'inventaire'
        $InventoryData = $loadedInventory.Data
        $inventorySourcePath = $loadedInventory.Path
    }
    elseif ($null -ne $InventoryData) {
        $inventorySourcePath = '(inventaire fourni en mémoire)'
    }
    elseif ($null -ne $script:OpsCurrentInventory) {
        if ($script:OpsCurrentInventory -is [hashtable]) {
            $InventoryData = $script:OpsCurrentInventory
        }
        elseif ($script:OpsCurrentInventory.PSObject.Properties['Data']) {
            $InventoryData = $script:OpsCurrentInventory.Data
            if ($script:OpsCurrentInventory.PSObject.Properties['Path']) {
                $inventorySourcePath = [string]$script:OpsCurrentInventory.Path
            }
        }
        else {
            $InventoryData = $script:OpsCurrentInventory
        }
    }

    if ($null -eq $InventoryData) {
        $message = "Aucun inventaire disponible pour valider le playbook '$SourcePath'. Correction attendue : importez d'abord un inventaire via Import-OpsInventory."
        if ($PassThru.IsPresent) {
            return [pscustomobject]@{
                IsValid      = $false
                Errors       = @($message)
                SourcePath   = $SourcePath
                Playbook     = $null
                Inventory    = $null
                Message      = $message
                ErrorClasses = @('missing_inventory')
            }
        }

        throw $message
    }

    $errors = @()
    $errorClasses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $inventoryValidation = Test-OpsInventory -InventoryData $InventoryData -SourcePath $inventorySourcePath -PassThru
    if (-not $inventoryValidation.IsValid) {
        [void]$errorClasses.Add('unsupported_os')
        foreach ($inventoryError in @($inventoryValidation.Errors)) {
            $errors += "Inventaire invalide pour la validation du playbook : $inventoryError"
        }
    }

    $playbookTable = ConvertTo-OpsPropertyTable -InputObject $PlaybookData
    $topLevelSchema = @{
        Name        = @{
            Required = $true
            Type     = 'String'
            Expected = "ajoutez la clé 'Name' (nom du playbook)."
        }
        Description = @{
            Required = $true
            Type     = 'String'
            Expected = "ajoutez la clé 'Description'."
        }
        Targets     = @{
            Required = $true
            Type     = 'Array'
            Expected = "ajoutez la clé 'Targets' avec un tableau de cibles."
        }
        Options     = @{
            Required = $true
            Type     = 'Hashtable'
            Expected = "ajoutez la clé 'Options' avec ParallelHosts et StopOnFirstError."
        }
    }

    $topLevelResult = Test-OpsSchema -InputObject $playbookTable -ObjectPath 'Playbook' -Schema $topLevelSchema
    if (-not $topLevelResult.IsValid) {
        [void]$errorClasses.Add('missing_or_invalid_key')
        $errors += @($topLevelResult.Errors)
    }

    $forbiddenKeys = @(
        'Password',
        'Pwd',
        'Passphrase',
        'Secret',
        'SecretValue',
        'Token',
        'ApiKey',
        'PrivateKey'
    )
    $errors += @(Find-OpsForbiddenKeys -InputObject $PlaybookData -ObjectPath 'Playbook' -ForbiddenKeys $forbiddenKeys)
    if (@($errors | Where-Object { $_ -like '*Clé interdite*' }).Count -gt 0) {
        [void]$errorClasses.Add('forbidden_secret_field')
    }

    if ($null -ne $playbookTable -and $playbookTable.ContainsKey('Options')) {
        $optionsSchema = @{
            ParallelHosts   = @{
                Required = $true
                Type     = 'Int32'
                Expected = "renseignez 'Options.ParallelHosts' avec un entier >= 1."
            }
            StopOnFirstError = @{
                Required = $true
                Type     = 'Boolean'
                Expected = "renseignez 'Options.StopOnFirstError' avec $true ou $false."
            }
        }

        $optionsResult = Test-OpsSchema -InputObject $playbookTable['Options'] -ObjectPath 'Playbook.Options' -Schema $optionsSchema
        if (-not $optionsResult.IsValid) {
            [void]$errorClasses.Add('invalid_type')
            $errors += @($optionsResult.Errors)
        }
        else {
            $parallelHosts = [int](ConvertTo-OpsPropertyTable -InputObject $playbookTable['Options'])['ParallelHosts']
            if ($parallelHosts -lt 1) {
                [void]$errorClasses.Add('invalid_type')
                $errors += "Valeur invalide pour 'Playbook.Options.ParallelHosts' : '$parallelHosts'. Correction attendue : utilisez un entier supérieur ou égal à 1."
            }
        }
    }

    $inventoryHostNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $inventoryValidation.Inventory -and $inventoryValidation.Inventory.ContainsKey('Hosts')) {
        foreach ($inventoryHost in @($inventoryValidation.Inventory['Hosts'])) {
            $inventoryHostTable = ConvertTo-OpsPropertyTable -InputObject $inventoryHost
            if ($null -ne $inventoryHostTable -and $inventoryHostTable.ContainsKey('Name')) {
                [void]$inventoryHostNames.Add([string]$inventoryHostTable['Name'])
            }
        }
    }

    $availableRoles = @(Get-OpsAvailableRoles)
    $availableRoleSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($availableRole in $availableRoles) {
        [void]$availableRoleSet.Add($availableRole)
    }

    if ($null -ne $playbookTable -and $playbookTable.ContainsKey('Targets')) {
        if (Test-OpsSchemaType -TypeName 'Array' -Value $playbookTable['Targets']) {
            $targetSchema = @{
                Host  = @{
                    Required = $true
                    Type     = 'String'
                    Expected = "renseignez la clé 'Host' avec un nom d'hôte existant."
                }
                Roles = @{
                    Required = $true
                    Type     = 'Array'
                    Expected = "renseignez la clé 'Roles' avec un tableau de rôles."
                }
            }

            $targetIndex = 0
            foreach ($target in @($playbookTable['Targets'])) {
                $targetPath = 'Playbook.Targets[{0}]' -f $targetIndex
                $targetResult = Test-OpsSchema -InputObject $target -ObjectPath $targetPath -Schema $targetSchema
                if (-not $targetResult.IsValid) {
                    [void]$errorClasses.Add('missing_or_invalid_key')
                    $errors += @($targetResult.Errors)
                    $targetIndex += 1
                    continue
                }

                $targetTable = ConvertTo-OpsPropertyTable -InputObject $target
                $hostName = [string]$targetTable['Host']
                if (-not $inventoryHostNames.Contains($hostName)) {
                    [void]$errorClasses.Add('missing_reference')
                    $errors += "Référence d'hôte inexistante '$targetPath.Host' = '$hostName'. Correction attendue : utilisez un host présent dans l'inventaire."
                }

                $roleIndex = 0
                foreach ($roleName in @($targetTable['Roles'])) {
                    $rolePath = '{0}.Roles[{1}]' -f $targetPath, $roleIndex
                    if (-not ($roleName -is [string])) {
                        [void]$errorClasses.Add('invalid_type')
                        $errors += "Type invalide pour '$rolePath'. Correction attendue : utilisez un nom de rôle de type string."
                        $roleIndex += 1
                        continue
                    }

                    if (-not $availableRoleSet.Contains([string]$roleName)) {
                        [void]$errorClasses.Add('missing_reference')
                        $errors += "Rôle inexistant '$rolePath' = '$roleName'. Correction attendue : utilisez un rôle disponible dans src/Roles ou un rôle intégré."
                    }

                    $roleIndex += 1
                }

                $targetIndex += 1
            }
        }
    }

    $result = [pscustomobject]@{
        IsValid      = (@($errors).Count -eq 0)
        Errors       = @($errors)
        SourcePath   = $SourcePath
        Playbook     = $playbookTable
        Inventory    = $inventoryValidation.Inventory
        Message      = $null
        ErrorClasses = @($errorClasses)
    }

    if (-not $result.IsValid) {
        $result.Message = "Validation du playbook échouée pour '$SourcePath' :`n- $($result.Errors -join "`n- ")"
        if ($PassThru.IsPresent) {
            return $result
        }

        throw $result.Message
    }

    if ($PassThru.IsPresent) {
        return $result
    }

    return $true
}
