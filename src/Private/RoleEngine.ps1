if (-not (Get-Variable -Name OpsRoleCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:OpsRoleCache = @{}
}

if (-not (Get-Variable -Name OpsUiRuntimeLoaded -Scope Script -ErrorAction SilentlyContinue)) {
    $script:OpsUiRuntimeLoaded = $false
}

function Get-OpsRolesRootPath {
    [CmdletBinding()]
    param()

    $sourceRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleRoot = Split-Path -Path $sourceRoot -Parent
    $rolesRoot = Join-Path -Path $moduleRoot -ChildPath 'src'
    $rolesRoot = Join-Path -Path $rolesRoot -ChildPath 'Roles'
    return [System.IO.Path]::GetFullPath($rolesRoot)
}

function Get-OpsRoleFunctionMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleId
    )

    return @{
        Test       = ('Test-{0}Role' -f $RoleId)
        Plan       = ('Get-{0}Plan' -f $RoleId)
        Apply      = ('Invoke-{0}Apply' -f $RoleId)
        Verify     = ('Test-{0}Applied' -f $RoleId)
        Rollback   = ('Invoke-{0}Rollback' -f $RoleId)
        Parameters = ('Get-{0}ParameterSchema' -f $RoleId)
    }
}

function Get-OpsScriptDefinedFunctions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if (@($parseErrors).Count -gt 0) {
        $firstError = @($parseErrors)[0]
        $lineNumber = $firstError.Extent.StartLineNumber
        $columnNumber = $firstError.Extent.StartColumnNumber
        throw "Impossible d'analyser le script de rôle '$Path' (ligne $lineNumber, colonne $columnNumber). Détail : $($firstError.Message)"
    }

    $functionNames = @()
    $functionDefinitions = @(
        $scriptAst.FindAll(
            {
                param($astNode)
                $astNode -is [System.Management.Automation.Language.FunctionDefinitionAst]
            },
            $false
        )
    )

    foreach ($functionDefinition in $functionDefinitions) {
        if (-not [string]::IsNullOrWhiteSpace($functionDefinition.Name)) {
            $functionNames += [string]$functionDefinition.Name
        }
    }

    return @($functionNames | Sort-Object -Unique)
}

function Publish-OpsRoleFunctionsToScriptScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$FunctionNames
    )

    foreach ($functionName in @($FunctionNames | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($functionName)) {
            continue
        }

        $functionCommand = Get-Command -Name $functionName -ErrorAction SilentlyContinue
        if ($null -eq $functionCommand -or $functionCommand.CommandType -ne 'Function') {
            continue
        }

        Set-Item -Path ("Function:script:{0}" -f $functionName) -Value $functionCommand.ScriptBlock -Force
    }
}

function Initialize-OpsUiRuntime {
    [CmdletBinding()]
    param()

    if ($script:OpsUiRuntimeLoaded) {
        return
    }

    $sourceRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleRoot = Split-Path -Path $sourceRoot -Parent
    $uiRootPath = Join-Path -Path $moduleRoot -ChildPath 'src'
    $uiRootPath = Join-Path -Path $uiRootPath -ChildPath 'UI'

    $requiredUiFiles = @(
        'Theme.ps1',
        'Render.ps1',
        'Menu.ps1',
        'Checklist.ps1',
        'Form.ps1',
        'Progress.ps1',
        'Schema.ps1'
    )

    foreach ($requiredUiFile in $requiredUiFiles) {
        $uiFilePath = Join-Path -Path $uiRootPath -ChildPath $requiredUiFile
        if (-not (Test-Path -LiteralPath $uiFilePath)) {
            continue
        }

        try {
            . $uiFilePath
        }
        catch {
            return
        }
    }

    $script:OpsUiRuntimeLoaded = $true
}

function Get-OpsRoleManifestValidationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ManifestData,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestPath
    )

    $manifestSchema = @{
        Id                   = @{
            Required = $true
            Type     = 'String'
            Expected = "renseignez Id avec l'identifiant du rôle."
        }
        DisplayName          = @{
            Required = $true
            Type     = 'String'
            Expected = "renseignez DisplayName (nom lisible pour l'utilisateur)."
        }
        Category             = @{
            Required = $true
            Type     = 'String'
            Expected = "renseignez Category (ex: Windows/Directory)."
        }
        SupportedOS          = @{
            Required = $true
            Type     = 'Array'
            Expected = "renseignez SupportedOS avec un tableau d'OS supportés."
        }
        Requires             = @{
            Required = $true
            Type     = 'Array'
            Expected = "renseignez Requires avec un tableau (vide possible)."
        }
        Conflicts            = @{
            Required = $true
            Type     = 'Array'
            Expected = "renseignez Conflicts avec un tableau (vide possible)."
        }
        RiskLevel            = @{
            Required      = $true
            Type          = 'String'
            AllowedValues = @('Low', 'Medium', 'High')
            Expected      = "renseignez RiskLevel avec Low, Medium ou High."
        }
        DestructivePotential = @{
            Required = $true
            Type     = 'Boolean'
            Expected = "renseignez DestructivePotential avec $true ou $false."
        }
        EstimatedDurationMin = @{
            Required = $true
            Type     = 'Int32'
            Expected = "renseignez EstimatedDurationMin avec un entier >= 1."
        }
    }

    $validation = Test-OpsSchema -InputObject $ManifestData -ObjectPath ("RoleManifest[{0}]" -f $RoleId) -Schema $manifestSchema
    if (-not $validation.IsValid) {
        return [pscustomobject]@{
            IsValid = $false
            Message = "Manifest de rôle invalide '$ManifestPath' :`n- $(@($validation.Errors) -join "`n- ")"
        }
    }

    if ([string]$ManifestData['Id'] -ne $RoleId) {
        return [pscustomobject]@{
            IsValid = $false
            Message = "Le manifest '$ManifestPath' déclare Id='$([string]$ManifestData['Id'])' mais le dossier est '$RoleId'. Correction attendue : alignez l'Id et le nom du dossier."
        }
    }

    $duration = [int]$ManifestData['EstimatedDurationMin']
    if ($duration -lt 1) {
        return [pscustomobject]@{
            IsValid = $false
            Message = "EstimatedDurationMin invalide dans '$ManifestPath' : '$duration'. Correction attendue : utilisez un entier >= 1."
        }
    }

    foreach ($osName in @($ManifestData['SupportedOS'])) {
        if (-not ($osName -is [string])) {
            return [pscustomobject]@{
                IsValid = $false
                Message = "SupportedOS contient une valeur non-string dans '$ManifestPath'. Correction attendue : utilisez uniquement des chaînes."
            }
        }
    }

    foreach ($requiredRole in @($ManifestData['Requires'])) {
        if (-not ($requiredRole -is [string])) {
            return [pscustomobject]@{
                IsValid = $false
                Message = "Requires contient une valeur non-string dans '$ManifestPath'. Correction attendue : utilisez uniquement des identifiants de rôle string."
            }
        }
    }

    foreach ($conflictingRole in @($ManifestData['Conflicts'])) {
        if (-not ($conflictingRole -is [string])) {
            return [pscustomobject]@{
                IsValid = $false
                Message = "Conflicts contient une valeur non-string dans '$ManifestPath'. Correction attendue : utilisez uniquement des identifiants de rôle string."
            }
        }
    }

    return [pscustomobject]@{
        IsValid = $true
        Message = 'OK'
    }
}

function Import-OpsRoleDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleId,

        [Parameter()]
        [switch]$Force
    )

    $normalizedRoleKey = $RoleId.ToLowerInvariant()
    if (-not $Force.IsPresent -and $script:OpsRoleCache.ContainsKey($normalizedRoleKey)) {
        return $script:OpsRoleCache[$normalizedRoleKey]
    }

    $rolesRootPath = Get-OpsRolesRootPath
    if (-not (Test-Path -LiteralPath $rolesRootPath)) {
        throw "Dossier des rôles introuvable : '$rolesRootPath'."
    }

    $roleDirectoryPath = Join-Path -Path $rolesRootPath -ChildPath $RoleId
    $roleDirectoryPath = [System.IO.Path]::GetFullPath($roleDirectoryPath)
    if (-not (Test-Path -LiteralPath $roleDirectoryPath -PathType Container)) {
        throw "Rôle introuvable : '$RoleId'. Correction attendue : créez le dossier '$roleDirectoryPath'."
    }

    $requiredFiles = @('role.psd1', 'Test.ps1', 'Plan.ps1', 'Apply.ps1', 'Verify.ps1')

    foreach ($requiredFile in $requiredFiles) {
        $requiredFilePath = Join-Path -Path $roleDirectoryPath -ChildPath $requiredFile
        if (-not (Test-Path -LiteralPath $requiredFilePath -PathType Leaf)) {
            throw "Rôle '$RoleId' invalide : fichier requis manquant '$requiredFile'. Correction attendue : ajoutez ce fichier dans '$roleDirectoryPath'."
        }
    }

    $manifestPath = Join-Path -Path $roleDirectoryPath -ChildPath 'role.psd1'
    $loadedManifest = Import-OpsDataFile -Path $manifestPath -DocumentKind ("manifest du rôle '{0}'" -f $RoleId)
    $manifestTable = ConvertTo-OpsPropertyTable -InputObject $loadedManifest.Data

    $manifestValidation = Get-OpsRoleManifestValidationResult -ManifestData $manifestTable -RoleId $RoleId -ManifestPath $manifestPath
    if (-not $manifestValidation.IsValid) {
        throw $manifestValidation.Message
    }

    $loadOrder = @('Parameters.ps1', 'Test.ps1', 'Plan.ps1', 'Apply.ps1', 'Verify.ps1', 'Rollback.ps1')
    $roleFunctionNames = @()
    foreach ($scriptFileName in $loadOrder) {
        $scriptFilePath = Join-Path -Path $roleDirectoryPath -ChildPath $scriptFileName
        if (-not (Test-Path -LiteralPath $scriptFilePath -PathType Leaf)) {
            continue
        }

        $scriptDefinedFunctions = Get-OpsScriptDefinedFunctions -Path $scriptFilePath
        if (@($scriptDefinedFunctions).Count -gt 0) {
            $roleFunctionNames += @($scriptDefinedFunctions)
        }

        try {
            . $scriptFilePath
        }
        catch {
            throw "Impossible de charger '$scriptFilePath'. Détail : $($_.Exception.Message)"
        }
    }

    Publish-OpsRoleFunctionsToScriptScope -FunctionNames @($roleFunctionNames)

    $functionMap = Get-OpsRoleFunctionMap -RoleId $RoleId
    $missingFunctions = @()
    foreach ($requiredFunction in @($functionMap.Test, $functionMap.Plan, $functionMap.Apply, $functionMap.Verify)) {
        if ($null -eq (Get-Command -Name $requiredFunction -ErrorAction SilentlyContinue)) {
            $missingFunctions += $requiredFunction
        }
    }

    if (@($missingFunctions).Count -gt 0) {
        throw "Rôle '$RoleId' invalide : fonction(s) manquante(s) $($missingFunctions -join ', '). Correction attendue : implémentez les fonctions requises dans les scripts du rôle."
    }

    $hasRollback = $false
    $rollbackFilePath = Join-Path -Path $roleDirectoryPath -ChildPath 'Rollback.ps1'
    if (Test-Path -LiteralPath $rollbackFilePath -PathType Leaf) {
        if ($null -eq (Get-Command -Name $functionMap.Rollback -ErrorAction SilentlyContinue)) {
            throw "Rôle '$RoleId' invalide : Rollback.ps1 présent mais fonction '$($functionMap.Rollback)' introuvable."
        }

        $hasRollback = $true
    }

    $hasParameterSchema = $false
    $parametersFilePath = Join-Path -Path $roleDirectoryPath -ChildPath 'Parameters.ps1'
    if (Test-Path -LiteralPath $parametersFilePath -PathType Leaf) {
        if ($null -eq (Get-Command -Name $functionMap.Parameters -ErrorAction SilentlyContinue)) {
            throw "Rôle '$RoleId' invalide : Parameters.ps1 présent mais fonction '$($functionMap.Parameters)' introuvable."
        }

        $hasParameterSchema = $true
    }

    $roleDefinition = [pscustomobject]@{
        Id                   = [string]$manifestTable['Id']
        DisplayName          = [string]$manifestTable['DisplayName']
        Category             = [string]$manifestTable['Category']
        SupportedOS          = @($manifestTable['SupportedOS'])
        Requires             = @($manifestTable['Requires'])
        Conflicts            = @($manifestTable['Conflicts'])
        RiskLevel            = [string]$manifestTable['RiskLevel']
        DestructivePotential = [bool]$manifestTable['DestructivePotential']
        EstimatedDurationMin = [int]$manifestTable['EstimatedDurationMin']
        RolePath             = $roleDirectoryPath
        ManifestPath         = $manifestPath
        FunctionMap          = $functionMap
        HasRollback          = $hasRollback
        HasParameterSchema   = $hasParameterSchema
    }

    $script:OpsRoleCache[$normalizedRoleKey] = $roleDefinition
    return $roleDefinition
}

function Get-OpsRoleDefinitionsInternal {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RoleId,

        [Parameter()]
        [switch]$Force
    )

    if (-not [string]::IsNullOrWhiteSpace($RoleId)) {
        return @(Import-OpsRoleDefinition -RoleId $RoleId -Force:$Force)
    }

    $rolesRootPath = Get-OpsRolesRootPath
    if (-not (Test-Path -LiteralPath $rolesRootPath -PathType Container)) {
        return @()
    }

    $roleDirectories = @(Get-ChildItem -LiteralPath $rolesRootPath -Directory | Sort-Object -Property Name)
    $roleDefinitions = @()
    foreach ($roleDirectory in $roleDirectories) {
        $manifestPath = Join-Path -Path $roleDirectory.FullName -ChildPath 'role.psd1'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Rôle invalide '$($roleDirectory.Name)' : manifest manquant 'role.psd1'."
        }

        $roleDefinitions += Import-OpsRoleDefinition -RoleId $roleDirectory.Name -Force:$Force
    }

    return @($roleDefinitions)
}

function Test-OpsTargetIsLocalAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetName
    )

    $normalizedTargetName = $TargetName.Trim().ToLowerInvariant()
    return ($normalizedTargetName -in @('local', 'localhost', '127.0.0.1', '::1'))
}

function Resolve-OpsDeployTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target
    )

    if ($Target -is [string]) {
        $targetName = [string]$Target
        if ([string]::IsNullOrWhiteSpace($targetName)) {
            throw 'Cible vide. Correction attendue : fournissez un nom de cible ou un objet Host.'
        }

        if (Test-OpsTargetIsLocalAlias -TargetName $targetName) {
            return @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
                OS        = 'Local'
            }
        }

        if ($null -ne $script:OpsCurrentInventory) {
            $inventoryData = $null
            if ($script:OpsCurrentInventory -is [hashtable]) {
                $inventoryData = $script:OpsCurrentInventory
            }
            elseif ($script:OpsCurrentInventory.PSObject.Properties['Data']) {
                $inventoryData = $script:OpsCurrentInventory.Data
            }

            $inventoryTable = ConvertTo-OpsPropertyTable -InputObject $inventoryData
            if ($null -ne $inventoryTable -and $inventoryTable.ContainsKey('Hosts')) {
                foreach ($hostEntry in @($inventoryTable['Hosts'])) {
                    $hostTable = ConvertTo-OpsPropertyTable -InputObject $hostEntry
                    if ($null -eq $hostTable -or -not $hostTable.ContainsKey('Name')) {
                        continue
                    }

                    $inventoryHostName = [string]$hostTable['Name']
                    if ($inventoryHostName.Equals($targetName, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return $hostTable
                    }
                }
            }
        }

        throw "Cible '$targetName' introuvable. Correction attendue : importez un inventaire contenant cet hôte ou fournissez un objet Target complet."
    }

    $targetTable = ConvertTo-OpsPropertyTable -InputObject $Target
    if ($null -eq $targetTable) {
        throw "Cible invalide. Correction attendue : fournissez un nom de cible ou une hashtable avec Name/Address/Transport."
    }

    if (-not $targetTable.ContainsKey('Transport') -or [string]::IsNullOrWhiteSpace([string]$targetTable['Transport'])) {
        $nameValue = ''
        if ($targetTable.ContainsKey('Name')) {
            $nameValue = [string]$targetTable['Name']
        }
        elseif ($targetTable.ContainsKey('Address')) {
            $nameValue = [string]$targetTable['Address']
        }

        if (Test-OpsTargetIsLocalAlias -TargetName $nameValue) {
            $targetTable['Transport'] = 'Local'
        }
        else {
            throw "Transport manquant pour la cible '$nameValue'. Correction attendue : ajoutez Transport='Local'|'WinRM'|'SSH'."
        }
    }

    if (-not $targetTable.ContainsKey('Address') -or [string]::IsNullOrWhiteSpace([string]$targetTable['Address'])) {
        if ($targetTable.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$targetTable['Name'])) {
            $targetTable['Address'] = [string]$targetTable['Name']
        }
        else {
            throw 'Adresse cible manquante. Correction attendue : renseignez Address ou Name.'
        }
    }

    if (-not $targetTable.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$targetTable['Name'])) {
        $targetTable['Name'] = [string]$targetTable['Address']
    }

    return $targetTable
}

function Get-OpsTargetDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable
    )

    if ($TargetTable.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$TargetTable['Name'])) {
        return [string]$TargetTable['Name']
    }

    return [string]$TargetTable['Address']
}

function ConvertTo-OpsPlanActionList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$PlanResult
    )

    if ($null -eq $PlanResult) {
        return @()
    }

    $actionsSource = $null
    $planTable = ConvertTo-OpsPropertyTable -InputObject $PlanResult
    if ($null -ne $planTable -and $planTable.ContainsKey('Actions')) {
        $actionsSource = $planTable['Actions']
    }
    elseif ($PlanResult -is [System.Collections.IEnumerable] -and -not ($PlanResult -is [string])) {
        $actionsSource = $PlanResult
    }
    else {
        throw "Plan invalide : aucune collection 'Actions' détectée. Correction attendue : retournez @{ Actions = @(...) }."
    }

    $normalizedActions = @()
    $actionIndex = 0
    foreach ($actionItem in @($actionsSource)) {
        $actionTable = ConvertTo-OpsPropertyTable -InputObject $actionItem
        if ($null -eq $actionTable) {
            throw "Action de plan invalide à l'index $actionIndex. Correction attendue : utilisez une hashtable avec Type et Label."
        }

        if (-not $actionTable.ContainsKey('Type') -or [string]::IsNullOrWhiteSpace([string]$actionTable['Type'])) {
            throw "Action de plan invalide à l'index $actionIndex : clé Type manquante."
        }

        if (-not $actionTable.ContainsKey('Label') -or [string]::IsNullOrWhiteSpace([string]$actionTable['Label'])) {
            throw "Action de plan invalide à l'index $actionIndex : clé Label manquante."
        }

        $actionData = $null
        if ($actionTable.ContainsKey('Data')) {
            $actionData = $actionTable['Data']
        }

        $normalizedActions += [pscustomobject]@{
            Type  = [string]$actionTable['Type']
            Label = [string]$actionTable['Label']
            Data  = $actionData
        }

        $actionIndex += 1
    }

    return @($normalizedActions)
}

function Get-OpsDefaultParametersFromSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]]$Schema
    )

    $defaults = @{}
    foreach ($field in @($Schema)) {
        $fieldTable = ConvertTo-OpsPropertyTable -InputObject $field
        if ($null -eq $fieldTable -or -not $fieldTable.ContainsKey('Name')) {
            continue
        }

        $parameterName = [string]$fieldTable['Name']
        if ([string]::IsNullOrWhiteSpace($parameterName)) {
            continue
        }

        $parameterValue = $null
        if ($fieldTable.ContainsKey('DefaultValue')) {
            $parameterValue = $fieldTable['DefaultValue']
        }

        $parameterType = 'String'
        if ($fieldTable.ContainsKey('Type')) {
            $parameterType = [string]$fieldTable['Type']
        }

        if ($parameterType.Equals('SecureString', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($parameterValue -is [SecureString]) {
                $defaults[$parameterName] = $parameterValue
            }
            elseif ($null -ne $parameterValue) {
                $defaults[$parameterName] = ConvertTo-SecureString -String ([string]$parameterValue) -AsPlainText -Force
            }
            else {
                $defaults[$parameterName] = ConvertTo-SecureString -String '' -AsPlainText -Force
            }
        }
        else {
            $defaults[$parameterName] = $parameterValue
        }
    }

    return $defaults
}

function Get-OpsRoleDesiredParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RoleDefinition,

        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters,

        [Parameter()]
        [switch]$NonInteractive
    )

    if ($null -ne $DesiredParameters) {
        return $DesiredParameters
    }

    if (-not $RoleDefinition.HasParameterSchema) {
        return @{}
    }

    $schemaFunctionName = [string]$RoleDefinition.FunctionMap.Parameters
    $parameterSchema = & $schemaFunctionName -Target $TargetTable
    $defaultParameters = Get-OpsDefaultParametersFromSchema -Schema @($parameterSchema)

    Initialize-OpsUiRuntime
    $showOpsFormCommand = Get-Command -Name Show-OpsForm -ErrorAction SilentlyContinue
    if ($NonInteractive.IsPresent -or $null -eq $showOpsFormCommand) {
        return $defaultParameters
    }

    try {
        $formTitle = "Paramètres du rôle $($RoleDefinition.DisplayName)"
        $capturedParameters = Show-OpsForm -Title $formTitle -Fields @($parameterSchema) -InitialValues $defaultParameters
        if ($null -eq $capturedParameters) {
            return $defaultParameters
        }

        return $capturedParameters
    }
    catch {
        return $defaultParameters
    }
}

function Show-OpsDeploymentPlanInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RoleDefinition,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetDisplayName,

        [Parameter()]
        [object[]]$PlanActions = @()
    )

    $planLines = @()
    $planLines += ("Rôle : {0}" -f $RoleDefinition.DisplayName)
    $planLines += ("Cible : {0}" -f $TargetDisplayName)
    $planLines += ("Niveau de risque : {0}" -f $RoleDefinition.RiskLevel)
    $planLines += ("Durée estimée : {0} min" -f $RoleDefinition.EstimatedDurationMin)
    $planLines += ''

    if (@($PlanActions).Count -eq 0) {
        $planLines += 'Aucune action requise. État déjà conforme.'
    }
    else {
        $planLines += 'Actions planifiées :'
        $actionIndex = 1
        foreach ($planAction in @($PlanActions)) {
            $planLines += ("{0}. [{1}] {2}" -f $actionIndex, [string]$planAction.Type, [string]$planAction.Label)
            $actionIndex += 1
        }
    }

    Initialize-OpsUiRuntime
    $writeOpsBoxCommand = Get-Command -Name Write-OpsBox -ErrorAction SilentlyContinue
    if ($null -ne $writeOpsBoxCommand) {
        Write-OpsBox -Title ("Plan de deploiement - {0}" -f $RoleDefinition.Id) -ContentLines $planLines -Ascii | Out-Null
    }
    else {
        foreach ($planLine in $planLines) {
            Write-Output $planLine
        }
    }

    return $planLines
}

function Test-OpsRoleSupportsTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RoleDefinition,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$TargetInfo
    )

    $supportedOperatingSystems = @($RoleDefinition.SupportedOS)
    if (@($supportedOperatingSystems).Count -eq 0) {
        return $true
    }

    $normalizedSupportedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($supportedOperatingSystem in $supportedOperatingSystems) {
        [void]$normalizedSupportedSet.Add([string]$supportedOperatingSystem)
    }

    if ($normalizedSupportedSet.Contains('Any') -or $normalizedSupportedSet.Contains('*')) {
        return $true
    }

    $targetTable = ConvertTo-OpsPropertyTable -InputObject $TargetInfo
    if ($null -eq $targetTable) {
        return $false
    }

    $candidateValues = @()
    foreach ($candidateKey in @('Distribution', 'Family', 'RawDistribution')) {
        if ($targetTable.ContainsKey($candidateKey)) {
            $candidateValue = [string]$targetTable[$candidateKey]
            if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                $candidateValues += $candidateValue
            }
        }
    }

    foreach ($candidateValue in $candidateValues) {
        if ($normalizedSupportedSet.Contains($candidateValue)) {
            return $true
        }
    }

    return $false
}
