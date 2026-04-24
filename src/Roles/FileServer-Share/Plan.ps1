function Get-FileServer-SharePlan {
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

    $effectiveParameters = Get-FileServer-ShareEffectiveParameters -DesiredParameters $DesiredParameters

    $shareName = [string]$effectiveParameters['ShareName']
    $sharePath = [string]$effectiveParameters['Path']
    $fullAccessPrincipals = @($effectiveParameters['FullAccessPrincipals'])
    $readAccessPrincipals = @($effectiveParameters['ReadAccessPrincipals'])

    if (-not [regex]::IsMatch($shareName, '^[A-Za-z0-9._$ -]{1,80}$')) {
        throw "Le paramètre ShareName est invalide ('${shareName}')."
    }

    if ([string]::IsNullOrWhiteSpace($sharePath)) {
        throw 'Le paramètre Path est obligatoire.'
    }

    if (Test-FileServerShareProtectedPath -Path $sharePath) {
        throw "Chemin refusé pour sécurité : '$sharePath'. Les chemins sous C:\\Windows et C:\\Program Files sont interdits."
    }

    if (@($fullAccessPrincipals).Count -eq 0) {
        throw 'FullAccessPrincipals doit contenir au moins un principal.'
    }

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $CurrentState
    if ($null -eq $stateTable) {
        throw 'État courant FileServer-Share invalide. Relancez Test-FileServer-ShareRole avant Plan.'
    }

    if (-not [bool]$stateTable['IsWindows']) {
        throw 'Le rôle FileServer-Share requiert Windows Server. Le système détecté n''est pas Windows.'
    }

    if (-not [bool]$stateTable['IsServerOS']) {
        throw 'Le rôle FileServer-Share refuse les systèmes Windows non serveur (Windows 10/11).'
    }

    $actions = @()

    if (-not [bool]$stateTable['DirectoryExists']) {
        $actions += [pscustomobject]@{
            Type  = 'EnsureDirectory'
            Label = "Créer le dossier '$sharePath'."
            Data  = @{ Path = $sharePath }
        }
    }

    if (-not [bool]$stateTable['NtfsFullMatches'] -or -not [bool]$stateTable['NtfsReadMatches']) {
        $actions += [pscustomobject]@{
            Type  = 'SetNtfsAcl'
            Label = "Configurer les ACL NTFS sur '$sharePath'."
            Data  = @{
                Path                 = $sharePath
                FullAccessPrincipals = @($fullAccessPrincipals)
                ReadAccessPrincipals = @($readAccessPrincipals)
            }
        }
    }

    if (-not [bool]$stateTable['ShareExists'] -or -not [bool]$stateTable['SharePathMatches']) {
        $actions += [pscustomobject]@{
            Type  = 'EnsureSmbShare'
            Label = "Créer ou corriger le partage SMB '$shareName'."
            Data  = @{
                ShareName            = $shareName
                Path                 = $sharePath
                FullAccessPrincipals = @($fullAccessPrincipals)
                ReadAccessPrincipals = @($readAccessPrincipals)
            }
        }
    }

    if (-not [bool]$stateTable['ShareFullMatches'] -or -not [bool]$stateTable['ShareReadMatches']) {
        $actions += [pscustomobject]@{
            Type  = 'SetSmbSharePermissions'
            Label = "Mettre à jour les permissions SMB de '$shareName'."
            Data  = @{
                ShareName            = $shareName
                FullAccessPrincipals = @($fullAccessPrincipals)
                ReadAccessPrincipals = @($readAccessPrincipals)
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

