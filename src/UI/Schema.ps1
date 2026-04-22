function Show-OpsTopology {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InventoryData,

        [Parameter()]
        [string]$Title = 'Topologie OpsToutatis',

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii,

        [Parameter()]
        [switch]$PassThru
    )

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Afficher la topologie OpsToutatis')) {
        return $null
    }

    $capabilities = Get-OpsUICapabilities -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii
    $symbols = Get-OpsUISymbolSet -Ascii:($Ascii -or $capabilities.UseAscii)

    $inventoryTable = ConvertTo-OpsUIHashtable -InputObject $InventoryData
    if ($null -eq $inventoryTable) {
        throw "Topologie invalide. Correction attendue : fournissez une hashtable d'inventaire contenant Hosts et Groups."
    }

    $hostsByName = @{}
    if ($inventoryTable.ContainsKey('Hosts')) {
        foreach ($hostEntry in @($inventoryTable['Hosts'])) {
            $hostTable = ConvertTo-OpsUIHashtable -InputObject $hostEntry
            if ($null -eq $hostTable -or -not $hostTable.ContainsKey('Name')) {
                continue
            }

            $hostName = [string]$hostTable['Name']
            $hostsByName[$hostName] = $hostTable
        }
    }

    $renderLines = @($Title)

    $groupsTable = @{}
    if ($inventoryTable.ContainsKey('Groups')) {
        $groupsCandidate = ConvertTo-OpsUIHashtable -InputObject $inventoryTable['Groups']
        if ($null -ne $groupsCandidate) {
            $groupsTable = $groupsCandidate
        }
    }

    if (@($groupsTable.Keys).Count -eq 0) {
        $renderLines += 'Aucun groupe détecté dans l''inventaire.'
    }
    else {
        $groupNames = @($groupsTable.Keys | Sort-Object)
        foreach ($groupName in $groupNames) {
            $renderLines += ('{0} Groupe {1}' -f $symbols.Branch, $groupName)
            $members = @($groupsTable[$groupName])
            if (@($members).Count -eq 0) {
                $renderLines += ('{0}{1}(vide)' -f $symbols.Stem, $symbols.LastBranch)
                continue
            }

            for ($memberIndex = 0; $memberIndex -lt @($members).Count; $memberIndex++) {
                $memberName = [string]$members[$memberIndex]
                $isLast = ($memberIndex -eq (@($members).Count - 1))
                $prefix = $symbols.Stem
                $branch = $symbols.Branch
                if ($isLast) {
                    $branch = $symbols.LastBranch
                }

                $hostDetails = $memberName
                if ($hostsByName.ContainsKey($memberName)) {
                    $hostTable = $hostsByName[$memberName]
                    $hostOS = ''
                    $hostTransport = ''
                    $hostAddress = ''

                    if ($hostTable.ContainsKey('OS')) {
                        $hostOS = [string]$hostTable['OS']
                    }

                    if ($hostTable.ContainsKey('Transport')) {
                        $hostTransport = [string]$hostTable['Transport']
                    }

                    if ($hostTable.ContainsKey('Address')) {
                        $hostAddress = [string]$hostTable['Address']
                    }

                    $hostDetails = '{0} ({1}, {2}, {3})' -f $memberName, $hostOS, $hostTransport, $hostAddress
                }
                else {
                    $hostDetails = $memberName + ' (hôte non trouvé dans Hosts)'
                }

                $renderLines += ('{0}{1}{2}' -f $prefix, $branch, $hostDetails)
            }
        }
    }

    $renderedText = [string]::Join([Environment]::NewLine, $renderLines)
    if ($PassThru.IsPresent) {
        return $renderedText
    }

    for ($lineIndex = 0; $lineIndex -lt @($renderLines).Count; $lineIndex++) {
        $color = 'Text'
        if ($lineIndex -eq 0) {
            $color = 'Title'
        }
        elseif ($renderLines[$lineIndex] -like '*Groupe*') {
            $color = 'Accent'
        }

        Write-OpsUI -Text $renderLines[$lineIndex] -Color $color -Plain:$capabilities.IsPlainMode -NonInteractive:$NonInteractive -Ascii:$Ascii | Out-Null
    }

    return $null
}
