function Get-Demo-HelloPlan {
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

    $effectiveParameters = Get-Demo-HelloEffectiveParameters -Target $Target -DesiredParameters $DesiredParameters
    $outputPath = [string]$effectiveParameters['OutputPath']
    $expectedContent = [string]$effectiveParameters['HelloText']

    $currentStateTable = ConvertTo-OpsPropertyTable -InputObject $CurrentState
    $currentContent = ''
    $currentFileExists = $false
    $currentDirectoryExists = $false
    if ($null -ne $currentStateTable) {
        if ($currentStateTable.ContainsKey('CurrentContent')) {
            $currentContent = [string]$currentStateTable['CurrentContent']
        }

        if ($currentStateTable.ContainsKey('FileExists')) {
            $currentFileExists = [bool]$currentStateTable['FileExists']
        }

        if ($currentStateTable.ContainsKey('DirectoryExists')) {
            $currentDirectoryExists = [bool]$currentStateTable['DirectoryExists']
        }
    }

    $normalizedCurrentContent = $currentContent.TrimEnd("`r", "`n")
    $normalizedExpectedContent = $expectedContent.TrimEnd("`r", "`n")
    $actions = @()

    if (-not $currentDirectoryExists) {
        $actions += [pscustomobject]@{
            Type  = 'EnsureDirectory'
            Label = ("Créer le dossier parent de '{0}'." -f $outputPath)
            Data  = @{
                OutputPath = $outputPath
            }
        }
    }

    if (-not $currentFileExists) {
        $actions += [pscustomobject]@{
            Type  = 'WriteHelloFile'
            Label = ("Créer le fichier '{0}' avec le contenu attendu." -f $outputPath)
            Data  = @{
                OutputPath = $outputPath
                HelloText  = $expectedContent
            }
        }
    }
    elseif ($normalizedCurrentContent -ne $normalizedExpectedContent) {
        $actions += [pscustomobject]@{
            Type  = 'WriteHelloFile'
            Label = ("Mettre à jour le contenu de '{0}' pour l'état attendu." -f $outputPath)
            Data  = @{
                OutputPath = $outputPath
                HelloText  = $expectedContent
            }
        }
    }

    $summary = 'État déjà conforme.'
    if (@($actions).Count -gt 0) {
        $summary = ("{0} action(s) planifiée(s)." -f @($actions).Count)
    }

    return [pscustomobject]@{
        Summary = $summary
        Actions = @($actions)
    }
}
