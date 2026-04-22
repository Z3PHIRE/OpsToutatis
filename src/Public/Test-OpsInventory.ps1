function Test-OpsInventory {
    [CmdletBinding(DefaultParameterSetName = 'Path', SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Data')]
        [AllowNull()]
        [object]$InventoryData,

        [Parameter(ParameterSetName = 'Data')]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath = '(mémoire)',

        [Parameter()]
        [switch]$PassThru
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $loadedInventory = Import-OpsDataFile -Path $Path -DocumentKind 'inventaire'
        $InventoryData = $loadedInventory.Data
        $SourcePath = $loadedInventory.Path
    }

    if (-not $PSCmdlet.ShouldProcess($SourcePath, 'Valider le schéma de l''inventaire OpsToutatis')) {
        return $null
    }

    $errors = @()
    $inventoryTable = ConvertTo-OpsPropertyTable -InputObject $InventoryData

    $topLevelSchema = @{
        Hosts  = @{
            Required = $true
            Type     = 'Array'
            Expected = "ajoutez la clé 'Hosts' avec un tableau de machines."
        }
        Groups = @{
            Required = $true
            Type     = 'Hashtable'
            Expected = "ajoutez la clé 'Groups' avec une table de groupes."
        }
    }

    $topLevelResult = Test-OpsSchema -InputObject $inventoryTable -ObjectPath 'Inventory' -Schema $topLevelSchema
    if (-not $topLevelResult.IsValid) {
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
    $errors += @(Find-OpsForbiddenKeys -InputObject $InventoryData -ObjectPath 'Inventory' -ForbiddenKeys $forbiddenKeys)

    $hostNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $supportedOperatingSystems = @(Get-OpsSupportedOperatingSystems)
    $supportedTransports = @('WinRM', 'SSH', 'Local')

    if ($null -ne $inventoryTable -and $inventoryTable.ContainsKey('Hosts')) {
        $hostEntries = $inventoryTable['Hosts']
        if (Test-OpsSchemaType -TypeName 'Array' -Value $hostEntries) {
            $hostSchema = @{
                Name          = @{
                    Required = $true
                    Type     = 'String'
                    Expected = "renseignez le nom d'hôte, par exemple 'DC01'."
                }
                Address       = @{
                    Required = $true
                    Type     = 'String'
                    Expected = "renseignez une adresse IP valide, par exemple '192.168.1.10'."
                }
                Transport     = @{
                    Required      = $true
                    Type          = 'String'
                    AllowedValues = $supportedTransports
                    Expected      = "renseignez le transport parmi : $($supportedTransports -join ', ')."
                }
                OS            = @{
                    Required      = $true
                    Type          = 'String'
                    AllowedValues = $supportedOperatingSystems
                    Expected      = "renseignez un OS supporté, par exemple '$($supportedOperatingSystems[0])'."
                }
                CredentialRef = @{
                    Required = $true
                    Type     = 'String'
                    Expected = "renseignez une référence de credential (ex: 'corp-admin')."
                }
            }

            $hostIndex = 0
            foreach ($hostEntry in @($hostEntries)) {
                $hostPath = 'Inventory.Hosts[{0}]' -f $hostIndex
                $hostResult = Test-OpsSchema -InputObject $hostEntry -ObjectPath $hostPath -Schema $hostSchema
                if (-not $hostResult.IsValid) {
                    $errors += @($hostResult.Errors)
                    $hostIndex += 1
                    continue
                }

                $hostTable = ConvertTo-OpsPropertyTable -InputObject $hostEntry
                $hostName = [string]$hostTable['Name']
                if ($hostNameSet.Contains($hostName)) {
                    $errors += "Nom d'hôte dupliqué '$hostPath.Name' = '$hostName'. Correction attendue : utilisez un nom unique dans Inventory.Hosts."
                }
                else {
                    [void]$hostNameSet.Add($hostName)
                }

                $parsedIpAddress = $null
                $ipValue = [string]$hostTable['Address']
                if (-not [System.Net.IPAddress]::TryParse($ipValue, [ref]$parsedIpAddress)) {
                    $errors += "Adresse IP invalide pour '$hostPath.Address' : '$ipValue'. Correction attendue : utilisez une adresse IPv4/IPv6 valide."
                }

                $hostIndex += 1
            }
        }
    }

    if ($null -ne $inventoryTable -and $inventoryTable.ContainsKey('Groups')) {
        $groups = ConvertTo-OpsPropertyTable -InputObject $inventoryTable['Groups']
        if ($null -eq $groups) {
            $errors += "Type invalide pour 'Inventory.Groups'. Correction attendue : utilisez une hashtable de groupes."
        }
        else {
            foreach ($groupName in @($groups.Keys)) {
                $groupPath = 'Inventory.Groups.{0}' -f $groupName
                $groupMembers = $groups[$groupName]
                if (-not (Test-OpsSchemaType -TypeName 'Array' -Value $groupMembers)) {
                    $errors += "Type invalide pour '$groupPath'. Correction attendue : utilisez un tableau de noms d'hôtes."
                    continue
                }

                $memberIndex = 0
                foreach ($member in @($groupMembers)) {
                    $memberPath = '{0}[{1}]' -f $groupPath, $memberIndex
                    if (-not ($member -is [string])) {
                        $errors += "Type invalide pour '$memberPath'. Correction attendue : utilisez un nom d'hôte de type string."
                        $memberIndex += 1
                        continue
                    }

                    if (-not $hostNameSet.Contains($member)) {
                        $errors += "Référence d'hôte inexistante '$memberPath' = '$member'. Correction attendue : utilisez un hôte déclaré dans Inventory.Hosts."
                    }

                    $memberIndex += 1
                }
            }
        }
    }

    $result = [pscustomobject]@{
        IsValid    = (@($errors).Count -eq 0)
        Errors     = @($errors)
        SourcePath = $SourcePath
        Inventory  = $inventoryTable
        Message    = $null
    }

    if (-not $result.IsValid) {
        $result.Message = "Validation de l'inventaire échouée pour '$SourcePath' :`n- $($result.Errors -join "`n- ")"
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
