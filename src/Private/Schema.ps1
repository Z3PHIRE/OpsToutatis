function Resolve-OpsDataFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DocumentKind = 'fichier de données'
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "Le $DocumentKind est introuvable : '$resolvedPath'. Correction attendue : fournissez un chemin vers un fichier .psd1 existant."
    }

    if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.psd1') {
        throw "Le $DocumentKind '$resolvedPath' doit être un fichier .psd1. Correction attendue : renommez le fichier avec l'extension .psd1."
    }

    return $resolvedPath
}

function Import-OpsDataFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DocumentKind = 'fichier de données'
    )

    $resolvedPath = Resolve-OpsDataFilePath -Path $Path -DocumentKind $DocumentKind

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $resolvedPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if (@($parseErrors).Count -gt 0) {
        $firstError = @($parseErrors)[0]
        $lineNumber = $firstError.Extent.StartLineNumber
        $columnNumber = $firstError.Extent.StartColumnNumber
        throw "Erreur de syntaxe dans '$resolvedPath' à la ligne $lineNumber, colonne $columnNumber. Détail : $($firstError.Message). Correction attendue : corrigez la clé ou la ponctuation PSD1 à cet emplacement."
    }

    try {
        $data = Import-PowerShellDataFile -Path $resolvedPath -ErrorAction Stop
    }
    catch {
        throw "Impossible de charger le $DocumentKind '$resolvedPath'. Détail : $($_.Exception.Message). Correction attendue : vérifiez que le fichier retourne une hashtable PSD1 valide."
    }

    if (-not ($data -is [hashtable])) {
        throw "Le $DocumentKind '$resolvedPath' n'est pas une hashtable PSD1 valide. Correction attendue : utilisez le format '@{ ... }'."
    }

    return [pscustomobject]@{
        Path = $resolvedPath
        Data = $data
    }
}

function ConvertTo-OpsPropertyTable {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [hashtable]) {
        return $InputObject
    }

    if ($InputObject -is [pscustomobject] -or $InputObject -is [System.Management.Automation.PSObject]) {
        $table = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $table[$property.Name] = $property.Value
        }

        return $table
    }

    return $null
}

function Test-OpsSchemaType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    $normalizedType = $TypeName.ToLowerInvariant()
    switch ($normalizedType) {
        'string' {
            return ($Value -is [string])
        }
        'int32' {
            return ($Value -is [int])
        }
        'boolean' {
            return ($Value -is [bool])
        }
        'array' {
            if ($Value -is [string]) {
                return $false
            }

            return ($Value -is [System.Collections.IEnumerable])
        }
        'hashtable' {
            return ($null -ne (ConvertTo-OpsPropertyTable -InputObject $Value))
        }
        default {
            throw "Type de schéma interne non supporté : '$TypeName'."
        }
    }
}

function Find-OpsForbiddenKeys {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ForbiddenKeys
    )

    $errors = @()
    if ($null -eq $InputObject) {
        return @($errors)
    }

    $forbiddenSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($forbiddenKey in $ForbiddenKeys) {
        [void]$forbiddenSet.Add($forbiddenKey)
    }

    $propertyTable = ConvertTo-OpsPropertyTable -InputObject $InputObject
    if ($null -ne $propertyTable) {
        foreach ($propertyName in @($propertyTable.Keys)) {
            $propertyPath = "$ObjectPath.$propertyName"
            if ($forbiddenSet.Contains([string]$propertyName)) {
                $errors += "Clé interdite détectée '$propertyPath'. Correction attendue : supprimez les secrets des fichiers et utilisez CredentialRef + Set-OpsCredential."
            }

            $nestedErrors = Find-OpsForbiddenKeys -InputObject $propertyTable[$propertyName] -ObjectPath $propertyPath -ForbiddenKeys $ForbiddenKeys
            if (@($nestedErrors).Count -gt 0) {
                $errors += @($nestedErrors)
            }
        }

        return @($errors)
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $itemIndex = 0
        foreach ($item in $InputObject) {
            $itemPath = '{0}[{1}]' -f $ObjectPath, $itemIndex
            $nestedErrors = Find-OpsForbiddenKeys -InputObject $item -ObjectPath $itemPath -ForbiddenKeys $ForbiddenKeys
            if (@($nestedErrors).Count -gt 0) {
                $errors += @($nestedErrors)
            }

            $itemIndex += 1
        }
    }

    return @($errors)
}

function Test-OpsSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Schema,

        [Parameter()]
        [switch]$AllowUnknownKeys
    )

    $errors = @()
    $propertyTable = ConvertTo-OpsPropertyTable -InputObject $InputObject
    if ($null -eq $propertyTable) {
        $errors += "Type invalide pour '$ObjectPath'. Correction attendue : utilisez une hashtable '@{ ... }'."
        return [pscustomobject]@{
            IsValid = $false
            Errors  = @($errors)
        }
    }

    $schemaKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($schemaKey in @($Schema.Keys)) {
        [void]$schemaKeySet.Add([string]$schemaKey)
        $definition = $Schema[$schemaKey]
        if (-not ($definition -is [hashtable])) {
            throw "Schéma interne invalide pour la clé '$schemaKey'. Chaque définition doit être une hashtable."
        }

        $isRequired = $false
        if ($definition.ContainsKey('Required')) {
            $isRequired = [bool]$definition.Required
        }

        $hasKey = $propertyTable.ContainsKey($schemaKey)
        if (-not $hasKey) {
            if ($isRequired) {
                $expected = "ajoutez la clé '$schemaKey'"
                if ($definition.ContainsKey('Expected')) {
                    $expected = [string]$definition.Expected
                }

                $errors += "Clé manquante '$ObjectPath.$schemaKey'. Correction attendue : $expected."
            }

            continue
        }

        $value = $propertyTable[$schemaKey]
        if ($null -eq $value) {
            $allowNull = $false
            if ($definition.ContainsKey('AllowNull')) {
                $allowNull = [bool]$definition.AllowNull
            }

            if (-not $allowNull) {
                $errors += "Valeur nulle interdite pour '$ObjectPath.$schemaKey'. Correction attendue : renseignez une valeur non nulle."
            }

            continue
        }

        if ($definition.ContainsKey('Type')) {
            $expectedType = [string]$definition.Type
            $isTypeValid = Test-OpsSchemaType -TypeName $expectedType -Value $value
            if (-not $isTypeValid) {
                $actualType = $value.GetType().FullName
                $errors += "Type invalide pour '$ObjectPath.$schemaKey'. Type attendu : $expectedType. Type reçu : $actualType."
                continue
            }
        }

        if ($definition.ContainsKey('AllowedValues')) {
            $allowedValues = @($definition.AllowedValues)
            $allowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($allowedValue in $allowedValues) {
                [void]$allowedSet.Add([string]$allowedValue)
            }

            if (-not $allowedSet.Contains([string]$value)) {
                $errors += "Valeur invalide pour '$ObjectPath.$schemaKey' : '$value'. Valeurs supportées : $($allowedValues -join ', ')."
            }
        }
    }

    if (-not $AllowUnknownKeys.IsPresent) {
        foreach ($propertyName in @($propertyTable.Keys)) {
            if (-not $schemaKeySet.Contains([string]$propertyName)) {
                $errors += "Clé non supportée '$ObjectPath.$propertyName'. Correction attendue : retirez cette clé ou utilisez une clé prévue par le schéma."
            }
        }
    }

    return [pscustomobject]@{
        IsValid = (@($errors).Count -eq 0)
        Errors  = @($errors)
    }
}

function Get-OpsSupportedOperatingSystems {
    [CmdletBinding()]
    param()

    return @(
        'WindowsServer2016',
        'WindowsServer2019',
        'WindowsServer2022',
        'WindowsServer2025',
        'Ubuntu2204',
        'Ubuntu2404',
        'Debian12',
        'RHEL9'
    )
}

function Get-OpsBuiltInRoles {
    [CmdletBinding()]
    param()

    return @(
        'ADDS-Forest',
        'DNS-Primary',
        'Linux-Nginx'
    )
}

function Get-OpsAvailableRoles {
    [CmdletBinding()]
    param()

    $roleSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($builtInRole in @(Get-OpsBuiltInRoles)) {
        [void]$roleSet.Add($builtInRole)
    }

    $sourceRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleRoot = Split-Path -Path $sourceRoot -Parent
    $rolesPath = Join-Path -Path $moduleRoot -ChildPath 'src'
    $rolesPath = Join-Path -Path $rolesPath -ChildPath 'Roles'

    if (Test-Path -LiteralPath $rolesPath) {
        $roleDirectories = @(Get-ChildItem -LiteralPath $rolesPath -Directory)
        foreach ($roleDirectory in $roleDirectories) {
            $manifestPath = Join-Path -Path $roleDirectory.FullName -ChildPath 'role.psd1'
            if (Test-Path -LiteralPath $manifestPath) {
                try {
                    $manifestData = Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop
                    if ($manifestData -is [hashtable] -and $manifestData.ContainsKey('Id')) {
                        $manifestRoleId = [string]$manifestData['Id']
                        if (-not [string]::IsNullOrWhiteSpace($manifestRoleId)) {
                            [void]$roleSet.Add($manifestRoleId)
                            continue
                        }
                    }
                }
                catch {
                }

                [void]$roleSet.Add($roleDirectory.Name)
            }
        }

        $roleFiles = @(Get-ChildItem -LiteralPath $rolesPath -File)
        foreach ($roleFile in $roleFiles) {
            if ($roleFile.Name -eq '.gitkeep') {
                continue
            }

            [void]$roleSet.Add($roleFile.BaseName)
        }
    }

    return @($roleSet | Sort-Object)
}

function Initialize-OpsSecretVault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName
    )

    $secretManagementModule = Get-Module -Name Microsoft.PowerShell.SecretManagement -ListAvailable | Select-Object -First 1
    $secretStoreModule = Get-Module -Name Microsoft.PowerShell.SecretStore -ListAvailable | Select-Object -First 1

    if ($null -eq $secretManagementModule -or $null -eq $secretStoreModule) {
        return [pscustomobject]@{
            Success = $false
            Message = "Le module SecretManagement n'est pas disponible. Installez-le avec : Install-Module Microsoft.PowerShell.SecretManagement,Microsoft.PowerShell.SecretStore -Scope CurrentUser."
        }
    }

    try {
        Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop | Out-Null
        Import-Module Microsoft.PowerShell.SecretStore -ErrorAction Stop | Out-Null
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Message = "Impossible de charger SecretManagement/SecretStore. Détail : $($_.Exception.Message)"
        }
    }

    $storeConfiguration = $null
    if (Get-Command -Name Get-SecretStoreConfiguration -ErrorAction SilentlyContinue) {
        try {
            $storeConfiguration = Get-SecretStoreConfiguration -ErrorAction Stop
        }
        catch {
            $storeConfiguration = $null
        }
    }

    if ($null -ne $storeConfiguration) {
        $authenticationMode = [string]$storeConfiguration.Authentication
        $interactionMode = [string]$storeConfiguration.Interaction
        if ($authenticationMode -ne 'None' -or $interactionMode -ne 'None') {
            return [pscustomobject]@{
                Success = $false
                Message = "Le coffre SecretStore est configuré en mode interactif (Authentication=$authenticationMode, Interaction=$interactionMode). Correction attendue : exécutez Set-SecretStoreConfiguration -Authentication None -Interaction None."
            }
        }
    }

    $vault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
    if ($null -eq $vault) {
        try {
            Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault -Description 'OpsToutatis default vault' -ErrorAction Stop | Out-Null
        }
        catch {
            return [pscustomobject]@{
                Success = $false
                Message = "Impossible de créer le coffre '$VaultName'. Détail : $($_.Exception.Message)."
            }
        }
    }

    return [pscustomobject]@{
        Success = $true
        Message = "Vault '$VaultName' ready."
    }
}
