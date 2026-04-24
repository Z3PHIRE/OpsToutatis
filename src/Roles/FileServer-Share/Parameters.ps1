function ConvertTo-FileServerSharePrincipalArray {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    $principals = @()

    if ($Value -is [string]) {
        foreach ($token in @(([string]$Value).Split(','))) {
            $candidate = $token.Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $principals += $candidate
            }
        }

        return @($principals)
    }

    foreach ($item in @($Value)) {
        $candidate = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $principals += $candidate
        }
    }

    return @($principals)
}

function Test-FileServerShareProtectedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)

    $protectedRoots = @(
        [System.IO.Path]::GetFullPath('C:\Windows'),
        [System.IO.Path]::GetFullPath('C:\Program Files'),
        [System.IO.Path]::GetFullPath('C:\Program Files (x86)')
    )

    foreach ($protectedRoot in $protectedRoots) {
        if ($fullPath.StartsWith($protectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-FileServer-ShareEffectiveParameters {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = @{
        ShareName             = 'OpsData'
        Path                  = 'C:\Shares\OpsData'
        FullAccessPrincipals  = @('BUILTIN\Administrators')
        ReadAccessPrincipals  = @('BUILTIN\Users')
    }

    if ($null -ne $DesiredParameters) {
        foreach ($parameterKey in @($DesiredParameters.Keys)) {
            $effectiveParameters[$parameterKey] = $DesiredParameters[$parameterKey]
        }
    }

    $effectiveParameters['ShareName'] = [string]$effectiveParameters['ShareName']
    $effectiveParameters['Path'] = [System.IO.Path]::GetFullPath([string]$effectiveParameters['Path'])
    $effectiveParameters['FullAccessPrincipals'] = ConvertTo-FileServerSharePrincipalArray -Value $effectiveParameters['FullAccessPrincipals']
    $effectiveParameters['ReadAccessPrincipals'] = ConvertTo-FileServerSharePrincipalArray -Value $effectiveParameters['ReadAccessPrincipals']

    return $effectiveParameters
}

function Get-FileServer-ShareParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    return @(
        @{
            Name                  = 'ShareName'
            Label                 = 'Nom du partage SMB'
            Type                  = 'String'
            DefaultValue          = 'OpsData'
            HelpText              = 'Nom du partage réseau exposé aux clients (ex: OpsData).'
            Validation            = '^[A-Za-z0-9._$ -]{1,80}$'
            ValidationDescription = '1 à 80 caractères. Lettres/chiffres/espace/._-$ autorisés.'
        }
        @{
            Name                  = 'Path'
            Label                 = 'Chemin local du dossier partagé'
            Type                  = 'String'
            DefaultValue          = 'C:\\Shares\\OpsData'
            HelpText              = 'Chemin local du dossier à partager. Les chemins système sensibles sont interdits.'
            Validation            = '^[A-Za-z]:\\.+'
            ValidationDescription = 'Chemin absolu Windows requis (ex: C:\\Shares\\OpsData).'
        }
        @{
            Name                  = 'FullAccessPrincipals'
            Label                 = 'Principaux FullAccess (virgule)'
            Type                  = 'String'
            DefaultValue          = 'BUILTIN\\Administrators'
            HelpText              = 'Comptes/groupes avec contrôle total (séparés par virgule).'
            Validation            = '^.{1,1024}$'
            ValidationDescription = 'Au moins un principal requis.'
        }
        @{
            Name                  = 'ReadAccessPrincipals'
            Label                 = 'Principaux ReadAccess (virgule)'
            Type                  = 'String'
            DefaultValue          = 'BUILTIN\\Users'
            HelpText              = 'Comptes/groupes en lecture (séparés par virgule).'
            Validation            = '^.*$'
            ValidationDescription = 'Laissez vide si aucun accès lecture spécifique.'
        }
    )
}
