function Convert-ADDSForestSecureStringToPlainText {
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

function ConvertTo-ADDSForestBoolean {
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

function Get-ADDSForestDefaultNetBIOSName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$DomainName
    )

    if ([string]::IsNullOrWhiteSpace($DomainName)) {
        return 'CORP'
    }

    $firstLabel = [string]($DomainName.Split('.')[0])
    if ([string]::IsNullOrWhiteSpace($firstLabel)) {
        return 'CORP'
    }

    $cleaned = ($firstLabel -replace '[^A-Za-z0-9-]', '').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($cleaned)) {
        return 'CORP'
    }

    if ($cleaned.Length -gt 15) {
        $cleaned = $cleaned.Substring(0, 15)
    }

    return $cleaned
}

function Test-ADDSForestDomainName {
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

function Test-ADDSForestDsrmPasswordComplexity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$Password
    )

    $plainPassword = Convert-ADDSForestSecureStringToPlainText -SecureValue $Password
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

function Get-ADDS-ForestEffectiveParameters {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = @{
        DomainName            = 'corp.local'
        NetBIOSName           = 'CORP'
        DSRMPassword          = (New-Object System.Security.SecureString)
        ForestFunctionalLevel = 'WinThreshold'
        SiteName              = 'Default-First-Site-Name'
        InstallDNS            = $true
    }

    if ($null -ne $DesiredParameters) {
        foreach ($parameterKey in @($DesiredParameters.Keys)) {
            $effectiveParameters[$parameterKey] = $DesiredParameters[$parameterKey]
        }
    }

    $effectiveParameters['DomainName'] = [string]$effectiveParameters['DomainName']

    if ([string]::IsNullOrWhiteSpace([string]$effectiveParameters['NetBIOSName'])) {
        $effectiveParameters['NetBIOSName'] = Get-ADDSForestDefaultNetBIOSName -DomainName ([string]$effectiveParameters['DomainName'])
    }
    else {
        $effectiveParameters['NetBIOSName'] = [string]$effectiveParameters['NetBIOSName']
    }

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

    $effectiveParameters['ForestFunctionalLevel'] = [string]$effectiveParameters['ForestFunctionalLevel']
    $effectiveParameters['SiteName'] = [string]$effectiveParameters['SiteName']
    $effectiveParameters['InstallDNS'] = ConvertTo-ADDSForestBoolean -Value $effectiveParameters['InstallDNS'] -ParameterName 'InstallDNS'

    return $effectiveParameters
}

function Get-ADDS-ForestParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    return @(
        @{
            Name                  = 'DomainName'
            Label                 = 'Nom du domaine (FQDN)'
            Type                  = 'String'
            DefaultValue          = 'corp.local'
            HelpText              = 'Nom DNS complet de la nouvelle forêt Active Directory.'
            Validation            = '^(?=.{3,255}$)(?!-)(?:[A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$'
            ValidationDescription = 'Exemple valide : corp.example. Un FQDN est obligatoire.'
        }
        @{
            Name                  = 'NetBIOSName'
            Label                 = 'Nom NetBIOS du domaine'
            Type                  = 'String'
            DefaultValue          = 'CORP'
            HelpText              = 'Nom court AD (15 caractères max) utilisé pour la compatibilité héritée.'
            Validation            = '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$'
            ValidationDescription = '1 à 15 caractères alphanumériques (tiret autorisé).'
        }
        @{
            Name                  = 'DSRMPassword'
            Label                 = 'Mot de passe DSRM'
            Type                  = 'SecureString'
            DefaultValue          = ''
            HelpText              = 'Mot de passe DSRM (14 caractères minimum). Sert à restaurer AD en mode sans échec.'
            Validation            = '^.{14,}$'
            ValidationDescription = 'Au moins 14 caractères. Complexité vérifiée en phase Plan.'
        }
        @{
            Name                  = 'ForestFunctionalLevel'
            Label                 = 'Niveau fonctionnel forêt'
            Type                  = 'Choice'
            DefaultValue          = 'WinThreshold'
            Choices               = @(
                @{ Value = 'Win2012R2'; Label = 'Windows Server 2012 R2' }
                @{ Value = 'WinThreshold'; Label = 'Windows Server 2016+' }
            )
            HelpText              = 'Niveau fonctionnel de la forêt. WinThreshold correspond à Windows Server 2016+.'
            Validation            = '^(Win2012R2|WinThreshold)$'
            ValidationDescription = 'Valeurs autorisées : Win2012R2 ou WinThreshold.'
        }
        @{
            Name                  = 'SiteName'
            Label                 = 'Nom du site AD'
            Type                  = 'String'
            DefaultValue          = 'Default-First-Site-Name'
            HelpText              = 'Nom du site Active Directory où sera promu le contrôleur de domaine.'
            Validation            = '^.{1,128}$'
            ValidationDescription = 'Le nom de site ne peut pas être vide.'
        }
        @{
            Name                  = 'InstallDNS'
            Label                 = 'Installer DNS intégré'
            Type                  = 'Choice'
            DefaultValue          = 'True'
            Choices               = @(
                @{ Value = 'True'; Label = 'Oui (recommandé)' }
                @{ Value = 'False'; Label = 'Non' }
            )
            HelpText              = 'Active le rôle DNS pendant la promotion de la forêt.'
            Validation            = '^(?i:true|false)$'
            ValidationDescription = 'Choisissez Oui ou Non.'
        }
    )
}
