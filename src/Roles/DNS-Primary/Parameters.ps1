function Test-DNSPrimaryZoneName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$ZoneName
    )

    if ([string]::IsNullOrWhiteSpace($ZoneName)) {
        return $false
    }

    return ([regex]::IsMatch(
            $ZoneName,
            '^(?=.{3,255}$)(?!-)(?:[A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$'
        ))
}

function Get-DNSPrimaryDefaultZoneFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZoneName
    )

    return ('{0}.dns' -f $ZoneName.ToLowerInvariant())
}

function Get-DNS-PrimaryEffectiveParameters {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = @{
        ZoneName  = 'corp.local'
        ZoneFile  = 'corp.local.dns'
    }

    if ($null -ne $DesiredParameters) {
        foreach ($parameterKey in @($DesiredParameters.Keys)) {
            $effectiveParameters[$parameterKey] = $DesiredParameters[$parameterKey]
        }
    }

    $effectiveParameters['ZoneName'] = [string]$effectiveParameters['ZoneName']

    if ([string]::IsNullOrWhiteSpace([string]$effectiveParameters['ZoneFile'])) {
        $effectiveParameters['ZoneFile'] = Get-DNSPrimaryDefaultZoneFileName -ZoneName $effectiveParameters['ZoneName']
    }
    else {
        $effectiveParameters['ZoneFile'] = [string]$effectiveParameters['ZoneFile']
    }

    return $effectiveParameters
}

function Get-DNS-PrimaryParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    return @(
        @{
            Name                  = 'ZoneName'
            Label                 = 'Nom de la zone DNS primaire (FQDN)'
            Type                  = 'String'
            DefaultValue          = 'corp.local'
            HelpText              = 'Zone DNS primaire autonome (fichier local), non intégrée AD.'
            Validation            = '^(?=.{3,255}$)(?!-)(?:[A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$'
            ValidationDescription = 'Exemple valide : corp.example.'
        }
        @{
            Name                  = 'ZoneFile'
            Label                 = 'Nom du fichier de zone'
            Type                  = 'String'
            DefaultValue          = 'corp.local.dns'
            HelpText              = 'Nom du fichier stockant la zone primaire (ex: corp.local.dns).'
            Validation            = '^[A-Za-z0-9._-]{3,255}$'
            ValidationDescription = 'Utilisez un nom de fichier DNS valide sans chemin absolu.'
        }
    )
}
