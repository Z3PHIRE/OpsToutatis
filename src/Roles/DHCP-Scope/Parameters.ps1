function Test-DHCPScopeIPv4Address {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Address
    )

    if ([string]::IsNullOrWhiteSpace($Address)) {
        return $false
    }

    try {
        $parsedAddress = [System.Net.IPAddress]::Parse($Address)
        if ($null -eq $parsedAddress) {
            return $false
        }

        return ($parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork)
    }
    catch {
        return $false
    }
}

function ConvertTo-DHCPScopeLeaseDurationHours {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [int]) {
        return [int]$Value
    }

    $parsedValue = 0
    if ([int]::TryParse([string]$Value, [ref]$parsedValue)) {
        return $parsedValue
    }

    throw "LeaseDurationHours invalide : '$Value'."
}

function Get-DHCP-ScopeEffectiveParameters {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = @{
        ScopeName          = 'Corp Clients'
        StartRange         = '10.0.10.100'
        EndRange           = '10.0.10.250'
        SubnetMask         = '255.255.255.0'
        Router             = '10.0.10.1'
        DnsServers         = @('10.0.10.10')
        LeaseDurationHours = 24
    }

    if ($null -ne $DesiredParameters) {
        foreach ($parameterKey in @($DesiredParameters.Keys)) {
            $effectiveParameters[$parameterKey] = $DesiredParameters[$parameterKey]
        }
    }

    $effectiveParameters['ScopeName'] = [string]$effectiveParameters['ScopeName']
    $effectiveParameters['StartRange'] = [string]$effectiveParameters['StartRange']
    $effectiveParameters['EndRange'] = [string]$effectiveParameters['EndRange']
    $effectiveParameters['SubnetMask'] = [string]$effectiveParameters['SubnetMask']
    $effectiveParameters['Router'] = [string]$effectiveParameters['Router']

    $dnsServerValues = @()
    foreach ($dnsServerValue in @($effectiveParameters['DnsServers'])) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dnsServerValue)) {
            $dnsServerValues += [string]$dnsServerValue
        }
    }

    $effectiveParameters['DnsServers'] = @($dnsServerValues)
    $effectiveParameters['LeaseDurationHours'] = ConvertTo-DHCPScopeLeaseDurationHours -Value $effectiveParameters['LeaseDurationHours']

    return $effectiveParameters
}

function Get-DHCP-ScopeParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    return @(
        @{
            Name                  = 'ScopeName'
            Label                 = 'Nom du scope DHCP'
            Type                  = 'String'
            DefaultValue          = 'Corp Clients'
            HelpText              = 'Nom lisible du scope DHCP IPv4 à créer ou mettre en conformité.'
            Validation            = '^.{1,128}$'
            ValidationDescription = 'Le nom du scope ne peut pas être vide.'
        }
        @{
            Name                  = 'StartRange'
            Label                 = 'Début de plage IPv4'
            Type                  = 'String'
            DefaultValue          = '10.0.10.100'
            HelpText              = 'Adresse IPv4 de début de bail DHCP.'
            Validation            = '^(?:\d{1,3}\.){3}\d{1,3}$'
            ValidationDescription = 'Format attendu : IPv4 (ex: 10.0.10.100).'
        }
        @{
            Name                  = 'EndRange'
            Label                 = 'Fin de plage IPv4'
            Type                  = 'String'
            DefaultValue          = '10.0.10.250'
            HelpText              = 'Adresse IPv4 de fin de bail DHCP.'
            Validation            = '^(?:\d{1,3}\.){3}\d{1,3}$'
            ValidationDescription = 'Format attendu : IPv4 (ex: 10.0.10.250).'
        }
        @{
            Name                  = 'SubnetMask'
            Label                 = 'Masque de sous-réseau'
            Type                  = 'String'
            DefaultValue          = '255.255.255.0'
            HelpText              = 'Masque IPv4 du scope DHCP.'
            Validation            = '^(?:\d{1,3}\.){3}\d{1,3}$'
            ValidationDescription = 'Format attendu : IPv4 (ex: 255.255.255.0).'
        }
        @{
            Name                  = 'Router'
            Label                 = 'Passerelle par défaut'
            Type                  = 'String'
            DefaultValue          = '10.0.10.1'
            HelpText              = 'Adresse IPv4 de la passerelle distribuée par DHCP.'
            Validation            = '^(?:\d{1,3}\.){3}\d{1,3}$'
            ValidationDescription = 'Format attendu : IPv4.'
        }
        @{
            Name                  = 'DnsServers'
            Label                 = 'Serveurs DNS (séparés par virgule)'
            Type                  = 'String'
            DefaultValue          = '10.0.10.10'
            HelpText              = 'Liste des DNS distribués aux clients. Exemple : 10.0.10.10,10.0.10.11'
            Validation            = '^(?:\s*(?:\d{1,3}\.){3}\d{1,3}\s*)(?:,\s*(?:\d{1,3}\.){3}\d{1,3}\s*)*$'
            ValidationDescription = 'Une ou plusieurs IPv4 séparées par des virgules.'
        }
        @{
            Name                  = 'LeaseDurationHours'
            Label                 = 'Durée de bail (heures)'
            Type                  = 'Int'
            DefaultValue          = 24
            HelpText              = 'Durée de validité d''un bail DHCP en heures.'
            Validation            = '^[0-9]{1,4}$'
            ValidationDescription = 'Entier positif entre 1 et 720.'
        }
    )
}

