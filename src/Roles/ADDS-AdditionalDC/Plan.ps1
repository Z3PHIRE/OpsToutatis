function Get-ADDS-AdditionalDCPlan {
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

    $effectiveParameters = Get-ADDS-AdditionalDCEffectiveParameters -DesiredParameters $DesiredParameters

    $domainName = [string]$effectiveParameters['DomainName']
    if (-not (Test-ADDSAdditionalDCDomainName -DomainName $domainName)) {
        throw "Le paramètre DomainName est invalide ('${domainName}'). Un FQDN est obligatoire."
    }

    $siteName = [string]$effectiveParameters['SiteName']
    if ([string]::IsNullOrWhiteSpace($siteName)) {
        throw 'Le paramètre SiteName est obligatoire.'
    }

    $dsrmValidation = Test-ADDSAdditionalDCDsrmPasswordComplexity -Password $effectiveParameters['DSRMPassword']
    if (-not $dsrmValidation.IsValid) {
        throw $dsrmValidation.Message
    }

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $CurrentState
    if ($null -eq $stateTable) {
        throw 'État courant ADDS-AdditionalDC invalide. Relancez Test-ADDS-AdditionalDCRole avant Plan.'
    }

    if (-not [bool]$stateTable['IsWindows']) {
        throw 'Le rôle ADDS-AdditionalDC requiert Windows Server. Le système détecté n''est pas Windows.'
    }

    if (-not [bool]$stateTable['IsServerOS']) {
        throw 'Le rôle ADDS-AdditionalDC refuse les systèmes Windows non serveur (Windows 10/11).'
    }

    if ([bool]$stateTable['IsDomainController'] -and -not [bool]$stateTable['DomainMatches']) {
        throw "Cette machine est déjà contrôleur de domaine pour '$([string]$stateTable['CurrentDomainName'])'. Promotion additionnelle refusée."
    }

    $actions = @()

    if (-not [bool]$stateTable['FeatureInstalled']) {
        $actions += [pscustomobject]@{
            Type  = 'InstallWindowsFeature'
            Label = 'Installer le rôle Windows AD-Domain-Services.'
            Data  = @{ FeatureName = 'AD-Domain-Services' }
        }
    }

    if (-not [bool]$stateTable['IsDomainController']) {
        $actions += [pscustomobject]@{
            Type  = 'PromoteAdditionalDomainController'
            Label = "Promouvoir ce serveur en contrôleur de domaine additionnel pour '$domainName'."
            Data  = @{
                DomainName          = $domainName
                SiteName            = $siteName
                DSRMPassword        = $effectiveParameters['DSRMPassword']
                InstallDNS          = [bool]$effectiveParameters['InstallDNS']
                ReplicationSourceDC = [string]$effectiveParameters['ReplicationSourceDC']
            }
        }

        $actions += [pscustomobject]@{
            Type  = 'ManualRebootRequired'
            Label = 'Redémarrage requis après promotion AD DS (confirmation explicite obligatoire).'
            Data  = @{ Reason = 'ADDSAdditionalDCPromotion' }
        }
    }

    $summary = 'État déjà conforme.'
    if (@($actions).Count -gt 0) {
        $summary = ('{0} action(s) planifiée(s).' -f @($actions).Count)
    }

    return [pscustomobject]@{
        Summary = $summary
        Actions = @($actions)
    }
}

