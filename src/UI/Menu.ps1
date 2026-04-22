function Read-OpsUIKey {
    [CmdletBinding()]
    param()

    try {
        $readOptions = [System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown
        $keyInfo = $Host.UI.RawUI.ReadKey($readOptions)
    }
    catch {
        return $null
    }

    return [pscustomobject]@{
        VirtualKeyCode = [int]$keyInfo.VirtualKeyCode
        Character      = [string]$keyInfo.Character
        ControlKeyState = $keyInfo.ControlKeyState
    }
}

function Show-OpsMenu {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Items,

        [Parameter()]
        [string]$Title = 'Sélectionnez une option',

        [Parameter()]
        [int]$DefaultIndex = 0,

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii
    )

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Afficher un menu OpsToutatis')) {
        return $null
    }

    $normalizedItems = @()
    $itemIndex = 0
    foreach ($item in @($Items)) {
        $itemTable = ConvertTo-OpsUIHashtable -InputObject $item
        if ($null -eq $itemTable) {
            throw "Entrée de menu invalide à l'index $itemIndex. Correction attendue : utilisez @{ Id='...'; Label='...'; Description='...' }."
        }

        $itemId = [string]$itemTable['Id']
        $itemLabel = [string]$itemTable['Label']
        $itemDescription = ''
        if ($itemTable.ContainsKey('Description')) {
            $itemDescription = [string]$itemTable['Description']
        }

        if ([string]::IsNullOrWhiteSpace($itemId) -or [string]::IsNullOrWhiteSpace($itemLabel)) {
            throw "Entrée de menu invalide à l'index $itemIndex. Correction attendue : renseignez Id et Label."
        }

        $normalizedItems += [pscustomobject]@{
            Id          = $itemId
            Label       = $itemLabel
            Description = $itemDescription
        }

        $itemIndex += 1
    }

    if (@($normalizedItems).Count -eq 0) {
        throw "Le menu '$Title' ne contient aucun élément."
    }

    $selectedIndex = $DefaultIndex
    if ($selectedIndex -lt 0) {
        $selectedIndex = 0
    }

    if ($selectedIndex -ge @($normalizedItems).Count) {
        $selectedIndex = @($normalizedItems).Count - 1
    }

    $capabilities = Get-OpsUICapabilities -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii
    if ($capabilities.IsPlainMode) {
        Write-OpsUI -Text $Title -Color Title -Plain -Ascii:$Ascii | Out-Null
        for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
            $menuItem = $normalizedItems[$index]
            $line = '{0}. {1}' -f ($index + 1), $menuItem.Label
            if (-not [string]::IsNullOrWhiteSpace($menuItem.Description)) {
                $line = $line + ' - ' + $menuItem.Description
            }

            Write-OpsUI -Text $line -Color Text -Plain -Ascii:$Ascii | Out-Null
        }

        if (-not $capabilities.IsInteractive) {
            $fallbackItem = $normalizedItems[$selectedIndex]
            Write-OpsUI -Text ("Mode non interactif détecté. Sélection par défaut : {0}" -f $fallbackItem.Label) -Color Warning -Plain -Ascii:$Ascii | Out-Null
            return $fallbackItem
        }

        while ($true) {
            $userInput = Read-Host "Entrez le numéro de l'option (Entrée pour défaut: $($selectedIndex + 1))"
            if ([string]::IsNullOrWhiteSpace($userInput)) {
                return $normalizedItems[$selectedIndex]
            }

            $parsedNumber = 0
            if ([int]::TryParse($userInput, [ref]$parsedNumber)) {
                $candidateIndex = $parsedNumber - 1
                if ($candidateIndex -ge 0 -and $candidateIndex -lt @($normalizedItems).Count) {
                    return $normalizedItems[$candidateIndex]
                }
            }

            Write-OpsUI -Text "Choix invalide. Correction attendue : saisissez un numéro valide de la liste." -Color Error -Plain -Ascii:$Ascii | Out-Null
        }
    }

    Write-OpsUI -Text $Title -Color Title -Ascii:$Ascii | Out-Null
    Write-OpsUI -Text 'Utilisez Haut/Bas, Home/End, Enter pour valider.' -Color Subtle -Ascii:$Ascii | Out-Null

    $itemsStartRow = 0
    try {
        $itemsStartRow = [Console]::CursorTop
    }
    catch {
        $itemsStartRow = 0
    }

    $consoleWidth = Get-OpsUIConsoleWidth
    for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
        $placeholder = ''.PadRight($consoleWidth - 1)
        Write-OpsUI -Text $placeholder -NoNewLine:$false -Ascii:$Ascii | Out-Null
    }

    $renderMenuLine = {
        param(
            [int]$LineIndex,
            [bool]$IsSelected
        )

        $menuItem = $normalizedItems[$LineIndex]
        $prefix = '  '
        $color = 'Text'
        if ($IsSelected) {
            $prefix = '> '
            $color = 'Selection'
        }

        $lineText = $prefix + $menuItem.Label
        if (-not [string]::IsNullOrWhiteSpace($menuItem.Description)) {
            $lineText = $lineText + ' - ' + $menuItem.Description
        }

        if ($lineText.Length -gt ($consoleWidth - 1)) {
            $lineText = $lineText.Substring(0, $consoleWidth - 1)
        }

        $lineText = $lineText.PadRight($consoleWidth - 1)
        $rowValue = $itemsStartRow + $LineIndex + 1
        Write-OpsUI -Text $lineText -Color $color -Row $rowValue -Column 1 -Ascii:$Ascii | Out-Null
    }

    for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
        & $renderMenuLine -LineIndex $index -IsSelected:($index -eq $selectedIndex)
    }

    while ($true) {
        $pressedKey = Read-OpsUIKey
        if ($null -eq $pressedKey) {
            return $normalizedItems[$selectedIndex]
        }

        $previousIndex = $selectedIndex
        switch ($pressedKey.VirtualKeyCode) {
            38 {
                if ($selectedIndex -gt 0) {
                    $selectedIndex -= 1
                }
            }
            40 {
                if ($selectedIndex -lt (@($normalizedItems).Count - 1)) {
                    $selectedIndex += 1
                }
            }
            36 {
                $selectedIndex = 0
            }
            35 {
                $selectedIndex = @($normalizedItems).Count - 1
            }
            13 {
                try {
                    [Console]::SetCursorPosition(0, $itemsStartRow + @($normalizedItems).Count)
                }
                catch {
                }

                return $normalizedItems[$selectedIndex]
            }
            default {
                # Ignore unsupported keys.
            }
        }

        if ($previousIndex -ne $selectedIndex) {
            & $renderMenuLine -LineIndex $previousIndex -IsSelected:$false
            & $renderMenuLine -LineIndex $selectedIndex -IsSelected:$true
        }
    }
}
