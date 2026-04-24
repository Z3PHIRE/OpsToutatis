function Get-DNS-PrimaryPlan {
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

    $effectiveParameters = Get-DNS-PrimaryEffectiveParameters -DesiredParameters $DesiredParameters
    $zoneName = [string]$effectiveParameters['ZoneName']
    $zoneFile = [string]$effectiveParameters['ZoneFile']

    if (-not (Test-DNSPrimaryZoneName -ZoneName $zoneName)) {
        throw "Le paramètre ZoneName est invalide ('${zoneName}')."
    }

    if (-not [regex]::IsMatch($zoneFile, '^[A-Za-z0-9._-]{3,255}$')) {
        throw "Le paramètre ZoneFile est invalide ('${zoneFile}')."
    }

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $CurrentState
    if ($null -eq $stateTable) {
        throw 'État courant DNS-Primary invalide. Relancez Test-DNS-PrimaryRole avant Plan.'
    }

    if (-not [bool]$stateTable['IsWindows']) {
        throw 'Le rôle DNS-Primary requiert Windows Server. Le système détecté n''est pas Windows.'
    }

    if (-not [bool]$stateTable['IsServerOS']) {
        throw 'Le rôle DNS-Primary refuse les systèmes Windows non serveur (Windows 10/11).'
    }

    $actions = @()

    if (-not [bool]$stateTable['DnsFeatureInstalled']) {
        $actions += [pscustomobject]@{
            Type  = 'InstallWindowsFeature'
            Label = 'Installer le rôle Windows DNS.'
            Data  = @{ FeatureName = 'DNS' }
        }
    }

    if (-not [bool]$stateTable['ZoneExists']) {
        $actions += [pscustomobject]@{
            Type  = 'CreatePrimaryZone'
            Label = "Créer la zone DNS primaire autonome '$zoneName'."
            Data  = @{
                ZoneName = $zoneName
                ZoneFile = $zoneFile
            }
        }
    }
    elseif ([bool]$stateTable['ZoneIsDsIntegrated']) {
        $actions += [pscustomobject]@{
            Type  = 'ReplaceAdIntegratedZone'
            Label = "Remplacer la zone AD-integrated '$zoneName' par une zone primaire autonome." 
            Data  = @{
                ZoneName = $zoneName
                ZoneFile = $zoneFile
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

