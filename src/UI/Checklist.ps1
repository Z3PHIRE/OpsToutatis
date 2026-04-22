function Show-OpsChecklist {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Items,

        [Parameter()]
        [string]$Title = 'Sélectionnez les éléments',

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii
    )

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Afficher une checklist OpsToutatis')) {
        return @()
    }

    $normalizedItems = @()
    $defaultChecks = @()
    $itemIndex = 0
    foreach ($item in @($Items)) {
        $itemTable = ConvertTo-OpsUIHashtable -InputObject $item
        if ($null -eq $itemTable) {
            throw "Entrée de checklist invalide à l'index $itemIndex. Correction attendue : utilisez @{ Id='...'; Label='...'; Description='...'; DefaultChecked=$false }."
        }

        $itemId = [string]$itemTable['Id']
        $itemLabel = [string]$itemTable['Label']
        $itemDescription = ''
        if ($itemTable.ContainsKey('Description')) {
            $itemDescription = [string]$itemTable['Description']
        }

        if ([string]::IsNullOrWhiteSpace($itemId) -or [string]::IsNullOrWhiteSpace($itemLabel)) {
            throw "Entrée de checklist invalide à l'index $itemIndex. Correction attendue : renseignez Id et Label."
        }

        $defaultChecked = $false
        if ($itemTable.ContainsKey('DefaultChecked')) {
            $defaultChecked = [bool]$itemTable['DefaultChecked']
        }

        $normalizedItems += [pscustomobject]@{
            Id          = $itemId
            Label       = $itemLabel
            Description = $itemDescription
        }
        $defaultChecks += $defaultChecked
        $itemIndex += 1
    }

    if (@($normalizedItems).Count -eq 0) {
        throw "La checklist '$Title' ne contient aucun élément."
    }

    $capabilities = Get-OpsUICapabilities -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii
    $symbols = Get-OpsUISymbolSet -Ascii:($Ascii -or $capabilities.UseAscii)

    if ($capabilities.IsPlainMode) {
        Write-OpsUI -Text $Title -Color Title -Plain -Ascii:$Ascii | Out-Null
        for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
            $mark = $symbols.Unchecked
            if ($defaultChecks[$index]) {
                $mark = $symbols.Checked
            }

            $line = '{0}. {1} {2}' -f ($index + 1), $mark, $normalizedItems[$index].Label
            if (-not [string]::IsNullOrWhiteSpace($normalizedItems[$index].Description)) {
                $line = $line + ' - ' + $normalizedItems[$index].Description
            }

            Write-OpsUI -Text $line -Color Text -Plain -Ascii:$Ascii | Out-Null
        }

        if (-not $capabilities.IsInteractive) {
            $selectedIds = @()
            for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
                if ($defaultChecks[$index]) {
                    $selectedIds += $normalizedItems[$index].Id
                }
            }

            Write-OpsUI -Text "Mode non interactif détecté. Les sélections par défaut sont appliquées." -Color Warning -Plain -Ascii:$Ascii | Out-Null
            return @($selectedIds)
        }

        while ($true) {
            $userInput = Read-Host "Entrez les numéros séparés par des virgules (ex: 1,3,5). Entrée vide = valeurs par défaut"
            if ([string]::IsNullOrWhiteSpace($userInput)) {
                $selectedIds = @()
                for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
                    if ($defaultChecks[$index]) {
                        $selectedIds += $normalizedItems[$index].Id
                    }
                }

                return @($selectedIds)
            }

            $tokens = @($userInput -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $seenIndices = [System.Collections.Generic.HashSet[int]]::new()
            $isValid = $true

            foreach ($token in @($tokens)) {
                $parsedNumber = 0
                if (-not [int]::TryParse($token, [ref]$parsedNumber)) {
                    $isValid = $false
                    break
                }

                $candidateIndex = $parsedNumber - 1
                if ($candidateIndex -lt 0 -or $candidateIndex -ge @($normalizedItems).Count) {
                    $isValid = $false
                    break
                }

                [void]$seenIndices.Add($candidateIndex)
            }

            if (-not $isValid) {
                Write-OpsUI -Text "Saisie invalide. Correction attendue : utilisez uniquement des numéros présents dans la liste." -Color Error -Plain -Ascii:$Ascii | Out-Null
                continue
            }

            $selectedIds = @()
            foreach ($selectedIndex in @($seenIndices)) {
                $selectedIds += $normalizedItems[$selectedIndex].Id
            }

            return @($selectedIds)
        }
    }

    $checks = @($defaultChecks)
    $cursorIndex = 0
    Write-OpsUI -Text $Title -Color Title -Ascii:$Ascii | Out-Null
    Write-OpsUI -Text 'Touches: Espace=cocher, Entree=valider, Haut/Bas, Home/End, PageUp/PageDown.' -Color Subtle -Ascii:$Ascii | Out-Null

    $startRow = 0
    try {
        $startRow = [Console]::CursorTop
    }
    catch {
        $startRow = 0
    }

    $consoleWidth = Get-OpsUIConsoleWidth
    for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
        Write-OpsUI -Text ''.PadRight($consoleWidth - 1) -Ascii:$Ascii | Out-Null
    }

    $renderChecklistLine = {
        param(
            [int]$LineIndex,
            [bool]$IsFocused
        )

        $marker = $symbols.Unchecked
        if ($checks[$LineIndex]) {
            $marker = $symbols.Checked
        }

        $focusPrefix = '  '
        $color = 'Text'
        if ($IsFocused) {
            $focusPrefix = '> '
            $color = 'Selection'
        }

        $lineText = '{0}{1} {2}' -f $focusPrefix, $marker, $normalizedItems[$LineIndex].Label
        if (-not [string]::IsNullOrWhiteSpace($normalizedItems[$LineIndex].Description)) {
            $lineText = $lineText + ' - ' + $normalizedItems[$LineIndex].Description
        }

        if ($lineText.Length -gt ($consoleWidth - 1)) {
            $lineText = $lineText.Substring(0, $consoleWidth - 1)
        }

        $lineText = $lineText.PadRight($consoleWidth - 1)
        $rowValue = $startRow + $LineIndex + 1
        Write-OpsUI -Text $lineText -Color $color -Row $rowValue -Column 1 -Ascii:$Ascii | Out-Null
    }

    for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
        & $renderChecklistLine -LineIndex $index -IsFocused:($index -eq $cursorIndex)
    }

    while ($true) {
        $pressedKey = Read-OpsUIKey
        if ($null -eq $pressedKey) {
            break
        }

        $previousIndex = $cursorIndex
        switch ($pressedKey.VirtualKeyCode) {
            38 {
                if ($cursorIndex -gt 0) {
                    $cursorIndex -= 1
                }
            }
            40 {
                if ($cursorIndex -lt (@($normalizedItems).Count - 1)) {
                    $cursorIndex += 1
                }
            }
            36 {
                $cursorIndex = 0
            }
            35 {
                $cursorIndex = @($normalizedItems).Count - 1
            }
            33 {
                $cursorIndex = [Math]::Max(0, $cursorIndex - 10)
            }
            34 {
                $cursorIndex = [Math]::Min(@($normalizedItems).Count - 1, $cursorIndex + 10)
            }
            32 {
                $checks[$cursorIndex] = -not $checks[$cursorIndex]
                & $renderChecklistLine -LineIndex $cursorIndex -IsFocused:$true
            }
            13 {
                break
            }
            default {
            }
        }

        if ($pressedKey.VirtualKeyCode -eq 13) {
            break
        }

        if ($previousIndex -ne $cursorIndex) {
            & $renderChecklistLine -LineIndex $previousIndex -IsFocused:$false
            & $renderChecklistLine -LineIndex $cursorIndex -IsFocused:$true
        }
    }

    try {
        [Console]::SetCursorPosition(0, $startRow + @($normalizedItems).Count)
    }
    catch {
    }

    $selectedIds = @()
    for ($index = 0; $index -lt @($normalizedItems).Count; $index++) {
        if ($checks[$index]) {
            $selectedIds += $normalizedItems[$index].Id
        }
    }

    return @($selectedIds)
}
