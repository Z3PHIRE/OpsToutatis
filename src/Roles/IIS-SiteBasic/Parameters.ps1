function ConvertTo-IISSiteBasicPort {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [int]) {
        return [int]$Value
    }

    $parsedPort = 0
    if ([int]::TryParse([string]$Value, [ref]$parsedPort)) {
        return $parsedPort
    }

    throw "BindingPort invalide : '$Value'."
}

function Get-IIS-SiteBasicEffectiveParameters {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = @{
        SiteName     = 'OpsSite'
        BindingPort  = 80
        PhysicalPath = 'C:\inetpub\OpsSite'
        AppPoolName  = 'OpsSitePool'
    }

    if ($null -ne $DesiredParameters) {
        foreach ($parameterKey in @($DesiredParameters.Keys)) {
            $effectiveParameters[$parameterKey] = $DesiredParameters[$parameterKey]
        }
    }

    $effectiveParameters['SiteName'] = [string]$effectiveParameters['SiteName']
    $effectiveParameters['BindingPort'] = ConvertTo-IISSiteBasicPort -Value $effectiveParameters['BindingPort']
    $effectiveParameters['PhysicalPath'] = [System.IO.Path]::GetFullPath([string]$effectiveParameters['PhysicalPath'])
    $effectiveParameters['AppPoolName'] = [string]$effectiveParameters['AppPoolName']

    return $effectiveParameters
}

function Get-IIS-SiteBasicParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    return @(
        @{
            Name                  = 'SiteName'
            Label                 = 'Nom du site IIS'
            Type                  = 'String'
            DefaultValue          = 'OpsSite'
            HelpText              = 'Nom du site IIS à créer ou aligner.'
            Validation            = '^[A-Za-z0-9._ -]{1,128}$'
            ValidationDescription = '1 à 128 caractères alphanumériques/._- espace.'
        }
        @{
            Name                  = 'BindingPort'
            Label                 = 'Port HTTP de binding'
            Type                  = 'Int'
            DefaultValue          = 80
            HelpText              = 'Port TCP d''écoute HTTP du site IIS.'
            Validation            = '^[0-9]{1,5}$'
            ValidationDescription = 'Port entre 1 et 65535.'
        }
        @{
            Name                  = 'PhysicalPath'
            Label                 = 'Chemin physique du site'
            Type                  = 'String'
            DefaultValue          = 'C:\\inetpub\\OpsSite'
            HelpText              = 'Chemin local des fichiers du site web.'
            Validation            = '^[A-Za-z]:\\.+'
            ValidationDescription = 'Chemin absolu Windows requis.'
        }
        @{
            Name                  = 'AppPoolName'
            Label                 = 'Nom de l''Application Pool'
            Type                  = 'String'
            DefaultValue          = 'OpsSitePool'
            HelpText              = 'Application pool IIS associé au site.'
            Validation            = '^[A-Za-z0-9._ -]{1,128}$'
            ValidationDescription = '1 à 128 caractères alphanumériques/._- espace.'
        }
    )
}

