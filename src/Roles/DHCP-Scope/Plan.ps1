function ConvertTo-DHCPScopeIPv4Numeric {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Address
    )

    $parsedAddress = [System.Net.IPAddress]::Parse($Address)
    $addressBytes = $parsedAddress.GetAddressBytes()
    [array]::Reverse($addressBytes)
    return [BitConverter]::ToUInt32($addressBytes, 0)
}

function ConvertTo-DHCPScopeDnsServerArray {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$DnsServers
    )

    $result = @()
    if ($DnsServers -is [string]) {
        foreach ($dnsToken in @(([string]$DnsServers).Split(','))) {
            $trimmedToken = $dnsToken.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmedToken)) {
                $result += $trimmedToken
            }
        }

        return @($result)
    }

    foreach ($dnsServerValue in @($DnsServers)) {
        $candidateValue = [string]$dnsServerValue
        if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
            $result += $candidateValue
        }
    }

    return @($result)
}

function Get-DHCP-ScopePlan {
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

    $effectiveParameters = Get-DHCP-ScopeEffectiveParameters -DesiredParameters $DesiredParameters

    $scopeName = [string]$effectiveParameters['ScopeName']
    if ([string]::IsNullOrWhiteSpace($scopeName)) {
        throw 'Le paramètre ScopeName est obligatoire.'
    }

    $startRange = [string]$effectiveParameters['StartRange']
    $endRange = [string]$effectiveParameters['EndRange']
    $subnetMask = [string]$effectiveParameters['SubnetMask']
    $router = [string]$effectiveParameters['Router']
    $dnsServers = ConvertTo-DHCPScopeDnsServerArray -DnsServers $effectiveParameters['DnsServers']
    $leaseDurationHours = [int]$effectiveParameters['LeaseDurationHours']

    foreach ($ipv4Parameter in @(
            @{ Name = 'StartRange'; Value = $startRange },
            @{ Name = 'EndRange'; Value = $endRange },
            @{ Name = 'SubnetMask'; Value = $subnetMask },
            @{ Name = 'Router'; Value = $router }
        )) {
        $ipv4Value = [string]$ipv4Parameter['Value']
        $isValidIpv4 = $false
        try {
            $parsedAddress = [System.Net.IPAddress]::Parse($ipv4Value)
            if ($null -ne $parsedAddress -and $parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                $isValidIpv4 = $true
            }
        }
        catch {
            $isValidIpv4 = $false
        }

        if (-not $isValidIpv4) {
            throw "Le paramètre $([string]$ipv4Parameter['Name']) est invalide ('$ipv4Value'). Une IPv4 valide est obligatoire."
        }
    }

    if (@($dnsServers).Count -eq 0) {
        throw 'Le paramètre DnsServers est obligatoire (au moins une IPv4).'
    }

    foreach ($dnsServer in @($dnsServers)) {
        if (-not (Test-DHCPScopeIPv4Address -Address $dnsServer)) {
            throw "Le serveur DNS '$dnsServer' est invalide."
        }
    }

    $startNumeric = ConvertTo-DHCPScopeIPv4Numeric -Address $startRange
    $endNumeric = ConvertTo-DHCPScopeIPv4Numeric -Address $endRange
    if ($startNumeric -gt $endNumeric) {
        throw "Plage DHCP invalide : StartRange '$startRange' doit être <= EndRange '$endRange'."
    }

    if ($leaseDurationHours -lt 1 -or $leaseDurationHours -gt 720) {
        throw "LeaseDurationHours invalide ('$leaseDurationHours'). Valeurs supportées : 1 à 720."
    }

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $CurrentState
    if ($null -eq $stateTable) {
        throw 'État courant DHCP-Scope invalide. Relancez Test-DHCP-ScopeRole avant Plan.'
    }

    if (-not [bool]$stateTable['IsWindows']) {
        throw 'Le rôle DHCP-Scope requiert Windows Server. Le système détecté n''est pas Windows.'
    }

    if (-not [bool]$stateTable['IsServerOS']) {
        throw 'Le rôle DHCP-Scope refuse les systèmes Windows non serveur (Windows 10/11).'
    }

    if (-not [bool]$stateTable['IsAuthorizedInAD']) {
        $authorizationReason = [string]$stateTable['AuthorizationReason']
        if ([string]::IsNullOrWhiteSpace($authorizationReason)) {
            $authorizationReason = 'Le serveur DHCP cible n''est pas autorisé dans Active Directory.'
        }

        throw "Déploiement refusé : DHCP non autorisé dans AD pour éviter un scope rogue. Détail : $authorizationReason"
    }

    $actions = @()

    if (-not [bool]$stateTable['DhcpFeatureInstalled']) {
        $actions += [pscustomobject]@{
            Type  = 'InstallWindowsFeature'
            Label = 'Installer le rôle Windows DHCP.'
            Data  = @{ FeatureName = 'DHCP' }
        }
    }

    $needsScopeConfiguration = (
        -not [bool]$stateTable['ScopeExists'] -or
        -not [bool]$stateTable['ScopeMatchesRange'] -or
        -not [bool]$stateTable['ScopeMatchesMask'] -or
        -not [bool]$stateTable['ScopeMatchesLease']
    )

    if ($needsScopeConfiguration) {
        $actions += [pscustomobject]@{
            Type  = 'EnsureDhcpScope'
            Label = "Créer ou mettre à jour le scope DHCP '$scopeName'."
            Data  = @{
                ScopeName          = $scopeName
                StartRange         = $startRange
                EndRange           = $endRange
                SubnetMask         = $subnetMask
                LeaseDurationHours = $leaseDurationHours
            }
        }
    }

    if ($needsScopeConfiguration -or -not [bool]$stateTable['RouterMatches'] -or -not [bool]$stateTable['DnsMatches']) {
        $actions += [pscustomobject]@{
            Type  = 'ConfigureDhcpOptions'
            Label = "Configurer les options DHCP (routeur/DNS) pour '$scopeName'."
            Data  = @{
                ScopeName   = $scopeName
                Router      = $router
                DnsServers  = @($dnsServers)
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

