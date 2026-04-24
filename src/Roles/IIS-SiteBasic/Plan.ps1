function Get-IIS-SiteBasicPlan {
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

    $effectiveParameters = Get-IIS-SiteBasicEffectiveParameters -DesiredParameters $DesiredParameters

    $siteName = [string]$effectiveParameters['SiteName']
    $bindingPort = [int]$effectiveParameters['BindingPort']
    $physicalPath = [string]$effectiveParameters['PhysicalPath']
    $appPoolName = [string]$effectiveParameters['AppPoolName']

    if (-not [regex]::IsMatch($siteName, '^[A-Za-z0-9._ -]{1,128}$')) {
        throw "Le paramètre SiteName est invalide ('${siteName}')."
    }

    if ($bindingPort -lt 1 -or $bindingPort -gt 65535) {
        throw "Le paramètre BindingPort est invalide ('$bindingPort'). Valeurs supportées : 1..65535."
    }

    if ([string]::IsNullOrWhiteSpace($physicalPath)) {
        throw 'Le paramètre PhysicalPath est obligatoire.'
    }

    if (-not [regex]::IsMatch($appPoolName, '^[A-Za-z0-9._ -]{1,128}$')) {
        throw "Le paramètre AppPoolName est invalide ('${appPoolName}')."
    }

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $CurrentState
    if ($null -eq $stateTable) {
        throw 'État courant IIS-SiteBasic invalide. Relancez Test-IIS-SiteBasicRole avant Plan.'
    }

    if (-not [bool]$stateTable['IsWindows']) {
        throw 'Le rôle IIS-SiteBasic requiert Windows Server. Le système détecté n''est pas Windows.'
    }

    if (-not [bool]$stateTable['IsServerOS']) {
        throw 'Le rôle IIS-SiteBasic refuse les systèmes Windows non serveur (Windows 10/11).'
    }

    $actions = @()

    if (-not [bool]$stateTable['IisFeatureInstalled']) {
        $actions += [pscustomobject]@{
            Type  = 'InstallWindowsFeature'
            Label = 'Installer le rôle Windows Web-Server (IIS).'
            Data  = @{ FeatureName = 'Web-Server' }
        }
    }

    if (-not [bool]$stateTable['DirectoryExists']) {
        $actions += [pscustomobject]@{
            Type  = 'EnsureDirectory'
            Label = "Créer le dossier du site '$physicalPath'."
            Data  = @{ PhysicalPath = $physicalPath }
        }
    }

    if (-not [bool]$stateTable['AppPoolExists']) {
        $actions += [pscustomobject]@{
            Type  = 'EnsureAppPool'
            Label = "Créer l'application pool '$appPoolName'."
            Data  = @{ AppPoolName = $appPoolName }
        }
    }

    if (-not [bool]$stateTable['SiteExists'] -or -not [bool]$stateTable['SitePathMatches'] -or -not [bool]$stateTable['SiteAppPoolMatches'] -or -not [bool]$stateTable['BindingPortMatches']) {
        $actions += [pscustomobject]@{
            Type  = 'EnsureWebsite'
            Label = "Créer ou corriger le site IIS '$siteName'."
            Data  = @{
                SiteName     = $siteName
                BindingPort  = $bindingPort
                PhysicalPath = $physicalPath
                AppPoolName  = $appPoolName
            }
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

