function Get-ADDS-ForestPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$CurrentState,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-ADDS-ForestEffectiveParameters -DesiredParameters $DesiredParameters

    $domainName = [string]$effectiveParameters['DomainName']
    if (-not (Test-ADDSForestDomainName -DomainName $domainName)) {
        throw "Le paramètre DomainName est invalide ('${domainName}'). Un FQDN est obligatoire (exemple : corp.example)."
    }

    $netBiosName = [string]$effectiveParameters['NetBIOSName']
    if (-not [regex]::IsMatch($netBiosName, '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$')) {
        throw "Le paramètre NetBIOSName est invalide ('${netBiosName}'). Utilisez 1 à 15 caractères alphanumériques (tiret autorisé)."
    }

    $dsrmValidation = Test-ADDSForestDsrmPasswordComplexity -Password $effectiveParameters['DSRMPassword']
    if (-not $dsrmValidation.IsValid) {
        throw $dsrmValidation.Message
    }

    $forestFunctionalLevel = [string]$effectiveParameters['ForestFunctionalLevel']
    if ($forestFunctionalLevel -notin @('Win2012R2', 'WinThreshold')) {
        throw "Le paramètre ForestFunctionalLevel est invalide ('$forestFunctionalLevel'). Valeurs supportées : Win2012R2, WinThreshold."
    }

    $siteName = [string]$effectiveParameters['SiteName']
    if ([string]::IsNullOrWhiteSpace($siteName)) {
        throw 'Le paramètre SiteName est obligatoire.'
    }

    $installDns = [bool]$effectiveParameters['InstallDNS']

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $CurrentState
    if ($null -eq $stateTable) {
        throw 'État courant ADDS-Forest invalide. Relancez Test-ADDS-ForestRole avant Plan.'
    }

    if (-not [bool]$stateTable['IsWindows']) {
        throw 'Le rôle ADDS-Forest requiert Windows Server. Le système détecté n''est pas Windows.'
    }

    if (-not [bool]$stateTable['IsServerOS']) {
        throw 'Le rôle ADDS-Forest refuse les systèmes Windows non serveur (Windows 10/11). Utilisez Windows Server 2016+.'
    }

    if ([bool]$stateTable['IsDomainController'] -and -not [bool]$stateTable['DomainMatches']) {
        throw "Cette machine est déjà contrôleur de domaine pour '$([string]$stateTable['CurrentDomainName'])'. Création d'une nouvelle forêt refusée."
    }

    $actions = @()

    if (-not [bool]$stateTable['FeatureInstalled']) {
        $actions += [pscustomobject]@{
            Type  = 'InstallWindowsFeature'
            Label = 'Installer le rôle Windows AD-Domain-Services.'
            Data  = @{
                FeatureName = 'AD-Domain-Services'
            }
        }
    }

    if (-not [bool]$stateTable['IsDomainController']) {
        $actions += [pscustomobject]@{
            Type  = 'InstallADDSForest'
            Label = "Créer la forêt Active Directory '$domainName'."
            Data  = @{
                DomainName            = $domainName
                NetBIOSName           = $netBiosName
                DSRMPassword          = $effectiveParameters['DSRMPassword']
                ForestFunctionalLevel = $forestFunctionalLevel
                SiteName              = $siteName
                InstallDNS            = $installDns
            }
        }

        $actions += [pscustomobject]@{
            Type  = 'ManualRebootRequired'
            Label = 'Redémarrage requis après promotion AD DS (confirmation explicite obligatoire).'
            Data  = @{
                Reason = 'ADDSForestPromotion'
            }
        }
    }

    $summary = 'État déjà conforme.'
    if (@($actions).Count -gt 0) {
        $summary = ('{0} action(s) planifiée(s).' -f @($actions).Count)
    }

    return [pscustomobject]@{
        Summary       = $summary
        Actions       = @($actions)
        RollbackNotes = @(
            'Rollback forêt AD : opération manuelle uniquement.',
            'Procédure recommandée : restauration depuis sauvegarde système ou reconstruction contrôlée du domaine.'
        )
    }
}

