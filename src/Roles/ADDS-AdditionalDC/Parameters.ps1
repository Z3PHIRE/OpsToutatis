function Convert-ADDSAdditionalDCSecureStringToPlainText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureValue
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function ConvertTo-ADDSAdditionalDCBoolean {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ParameterName
    )

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    if ($Value -is [int] -or $Value -is [long]) {
        return ([int64]$Value -ne 0)
    }

    $textValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($textValue)) {
        throw "Le paramètre '$ParameterName' doit être booléen (true/false)."
    }

    switch -Regex ($textValue.Trim().ToLowerInvariant()) {
        '^(1|true|yes|y|on)$' {
            return $true
        }
        '^(0|false|no|n|off)$' {
            return $false
        }
        default {
            throw "Le paramètre '$ParameterName' doit être booléen (true/false)."
        }
    }
}

function Test-ADDSAdditionalDCDomainName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$DomainName
    )

    if ([string]::IsNullOrWhiteSpace($DomainName)) {
        return $false
    }

    return ([regex]::IsMatch(
            $DomainName,
            '^(?=.{3,255}$)(?!-)(?:[A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$'
        ))
}

function Test-ADDSAdditionalDCDsrmPasswordComplexity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$Password
    )

    $plainPassword = Convert-ADDSAdditionalDCSecureStringToPlainText -SecureValue $Password
    $isLongEnough = ($plainPassword.Length -ge 14)
    $hasUpper = [regex]::IsMatch($plainPassword, '[A-Z]')
    $hasLower = [regex]::IsMatch($plainPassword, '[a-z]')
    $hasDigit = [regex]::IsMatch($plainPassword, '[0-9]')
    $hasSpecial = [regex]::IsMatch($plainPassword, '[^A-Za-z0-9]')

    $isValid = ($isLongEnough -and $hasUpper -and $hasLower -and $hasDigit -and $hasSpecial)
    $message = 'OK'
    if (-not $isValid) {
        $message = 'Le mot de passe DSRM doit contenir au moins 14 caractères avec majuscule, minuscule, chiffre et caractère spécial.'
    }

    return [pscustomobject]@{
        IsValid = $isValid
        Message = $message
    }
}

function Get-ADDS-AdditionalDCEffectiveParameters {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = @{
        DomainName          = 'corp.local'
        SiteName            = 'Default-First-Site-Name'
        DSRMPassword        = (New-Object System.Security.SecureString)
        InstallDNS          = $true
        ReplicationSourceDC = ''
    }

    if ($null -ne $DesiredParameters) {
        foreach ($parameterKey in @($DesiredParameters.Keys)) {
            $effectiveParameters[$parameterKey] = $DesiredParameters[$parameterKey]
        }
    }

    $effectiveParameters['DomainName'] = [string]$effectiveParameters['DomainName']
    $effectiveParameters['SiteName'] = [string]$effectiveParameters['SiteName']
    $effectiveParameters['ReplicationSourceDC'] = [string]$effectiveParameters['ReplicationSourceDC']

    $dsrmPasswordValue = $effectiveParameters['DSRMPassword']
    if ($dsrmPasswordValue -is [SecureString]) {
        $effectiveParameters['DSRMPassword'] = $dsrmPasswordValue
    }
    elseif ($null -eq $dsrmPasswordValue) {
        $effectiveParameters['DSRMPassword'] = New-Object System.Security.SecureString
    }
    else {
        $effectiveParameters['DSRMPassword'] = ConvertTo-SecureString -String ([string]$dsrmPasswordValue) -AsPlainText -Force
    }

    $effectiveParameters['InstallDNS'] = ConvertTo-ADDSAdditionalDCBoolean -Value $effectiveParameters['InstallDNS'] -ParameterName 'InstallDNS'
    return $effectiveParameters
}

function Get-ADDS-AdditionalDCParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    return @(
        @{
            Name                  = 'DomainName'
            Label                 = 'Nom du domaine existant (FQDN)'
            Type                  = 'String'
            DefaultValue          = 'corp.local'
            HelpText              = 'Domaine Active Directory existant à rejoindre comme contrôleur additionnel.'
            Validation            = '^(?=.{3,255}$)(?!-)(?:[A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$'
            ValidationDescription = 'Exemple valide : corp.example.'
        }
        @{
            Name                  = 'SiteName'
            Label                 = 'Nom du site AD'
            Type                  = 'String'
            DefaultValue          = 'Default-First-Site-Name'
            HelpText              = 'Site Active Directory cible pour ce contrôleur de domaine.'
            Validation            = '^.{1,128}$'
            ValidationDescription = 'Le nom de site ne peut pas être vide.'
        }
        @{
            Name                  = 'DSRMPassword'
            Label                 = 'Mot de passe DSRM'
            Type                  = 'SecureString'
            DefaultValue          = ''
            HelpText              = 'Mot de passe DSRM (14 caractères minimum). Sert à la restauration AD en mode sans échec.'
            Validation            = '^.{14,}$'
            ValidationDescription = 'Au moins 14 caractères. Complexité vérifiée en Plan.'
        }
        @{
            Name                  = 'InstallDNS'
            Label                 = 'Installer DNS sur ce DC'
            Type                  = 'Choice'
            DefaultValue          = 'True'
            Choices               = @(
                @{ Value = 'True'; Label = 'Oui (recommandé)' }
                @{ Value = 'False'; Label = 'Non' }
            )
            HelpText              = 'Installe le service DNS pendant la promotion du contrôleur additionnel.'
            Validation            = '^(?i:true|false)$'
            ValidationDescription = 'Choisissez Oui ou Non.'
        }
        @{
            Name                  = 'ReplicationSourceDC'
            Label                 = 'Contrôleur source de réplication (optionnel)'
            Type                  = 'String'
            DefaultValue          = ''
            HelpText              = 'Nom DNS du DC source prioritaire. Laissez vide pour sélection automatique.'
            Validation            = '^$|^[A-Za-z0-9.-]+$'
            ValidationDescription = 'Valeur vide ou nom d''hôte DNS valide.'
        }
    )
}

