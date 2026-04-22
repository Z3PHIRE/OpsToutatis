function Test-OpsFormFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Field,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    $validationMessage = ''
    if ($Field.ContainsKey('ValidationDescription')) {
        $validationMessage = [string]$Field['ValidationDescription']
    }

    if (-not $Field.ContainsKey('Validation') -or $null -eq $Field['Validation']) {
        return [pscustomobject]@{
            IsValid  = $true
            Message  = ''
            Guidance = $validationMessage
        }
    }

    $validation = $Field['Validation']
    try {
        if ($validation -is [scriptblock]) {
            $validationResult = & $validation $Value
            if (-not [bool]$validationResult) {
                if ([string]::IsNullOrWhiteSpace($validationMessage)) {
                    $validationMessage = "La valeur saisie ne respecte pas la règle attendue pour '$($Field['Label'])'."
                }

                return [pscustomobject]@{
                    IsValid  = $false
                    Message  = $validationMessage
                    Guidance = $validationMessage
                }
            }
        }
        else {
            $pattern = [string]$validation
            $textToValidate = ''
            if ($Value -is [SecureString]) {
                $textToValidate = Get-OpsPlainTextFromSecureString -SecureValue $Value
            }
            elseif ($null -eq $Value) {
                $textToValidate = ''
            }
            else {
                $textToValidate = [string]$Value
            }

            if (-not [regex]::IsMatch($textToValidate, $pattern)) {
                if ([string]::IsNullOrWhiteSpace($validationMessage)) {
                    $validationMessage = "La valeur saisie pour '$($Field['Label'])' doit respecter le motif : $pattern"
                }

                return [pscustomobject]@{
                    IsValid  = $false
                    Message  = $validationMessage
                    Guidance = $validationMessage
                }
            }
        }
    }
    catch {
        $errorMessage = "Validation impossible pour '$($Field['Label'])'. Détail : $($_.Exception.Message)"
        return [pscustomobject]@{
            IsValid  = $false
            Message  = $errorMessage
            Guidance = $validationMessage
        }
    }

    return [pscustomobject]@{
        IsValid  = $true
        Message  = ''
        Guidance = $validationMessage
    }
}

function ConvertTo-OpsFormChoiceList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$ChoiceInput
    )

    $choices = @()
    if ($null -eq $ChoiceInput) {
        return @($choices)
    }

    foreach ($choice in @($ChoiceInput)) {
        if ($choice -is [string]) {
            $choices += [pscustomobject]@{
                Value = $choice
                Label = $choice
            }
            continue
        }

        $choiceTable = ConvertTo-OpsUIHashtable -InputObject $choice
        if ($null -eq $choiceTable) {
            continue
        }

        $choiceValue = ''
        if ($choiceTable.ContainsKey('Value')) {
            $choiceValue = [string]$choiceTable['Value']
        }
        elseif ($choiceTable.ContainsKey('Id')) {
            $choiceValue = [string]$choiceTable['Id']
        }

        $choiceLabel = $choiceValue
        if ($choiceTable.ContainsKey('Label')) {
            $choiceLabel = [string]$choiceTable['Label']
        }

        if (-not [string]::IsNullOrWhiteSpace($choiceValue)) {
            $choices += [pscustomobject]@{
                Value = $choiceValue
                Label = $choiceLabel
            }
        }
    }

    return @($choices)
}

function Show-OpsForm {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Fields,

        [Parameter()]
        [string]$Title = 'Formulaire OpsToutatis',

        [Parameter()]
        [AllowNull()]
        [hashtable]$InitialValues,

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii
    )

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Afficher le formulaire OpsToutatis')) {
        return @{}
    }

    $capabilities = Get-OpsUICapabilities -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii
    Write-OpsBanner -Title $Title -Subtitle 'Saisissez les valeurs requises. Les validations sont appliquées champ par champ.' -Plain:$capabilities.IsPlainMode -NonInteractive:$NonInteractive -Ascii:$Ascii | Out-Null

    $results = @{}
    foreach ($fieldObject in @($Fields)) {
        $field = ConvertTo-OpsUIHashtable -InputObject $fieldObject
        if ($null -eq $field) {
            throw "Champ de formulaire invalide. Correction attendue : utilisez une hashtable avec Name, Label, HelpText et Type."
        }

        if (-not $field.ContainsKey('Name') -or -not $field.ContainsKey('Label') -or -not $field.ContainsKey('Type')) {
            throw "Champ de formulaire invalide. Correction attendue : renseignez Name, Label et Type."
        }

        $name = [string]$field['Name']
        $label = [string]$field['Label']
        $type = [string]$field['Type']
        $helpText = ''
        if ($field.ContainsKey('HelpText')) {
            $helpText = [string]$field['HelpText']
        }

        $defaultValue = $null
        if ($field.ContainsKey('DefaultValue')) {
            $defaultValue = $field['DefaultValue']
        }

        if ($null -ne $InitialValues -and $InitialValues.ContainsKey($name)) {
            $defaultValue = $InitialValues[$name]
        }

        while ($true) {
            Write-OpsUI -Text ('Champ : {0}' -f $label) -Color Accent -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
            if (-not [string]::IsNullOrWhiteSpace($helpText)) {
                Write-OpsUI -Text ('Aide : {0}' -f $helpText) -Color Subtle -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
            }

            if ($field.ContainsKey('ValidationDescription')) {
                Write-OpsUI -Text ('Validation : {0}' -f [string]$field['ValidationDescription']) -Color Subtle -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
            }
            elseif ($field.ContainsKey('Validation')) {
                Write-OpsUI -Text 'Validation : la valeur doit respecter la règle configurée.' -Color Subtle -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
            }

            $capturedValue = $null
            $nonInteractiveMode = (-not $capabilities.IsInteractive)
            if ($nonInteractiveMode) {
                $capturedValue = $defaultValue
                Write-OpsUI -Text "Mode non interactif détecté. Valeur par défaut utilisée pour '$label'." -Color Warning -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
            }
            else {
                switch ($type.ToLowerInvariant()) {
                    'securestring' {
                        $capturedValue = Read-Host -Prompt $label -AsSecureString
                        $isEmptySecure = ($null -eq $capturedValue)
                        if (-not $isEmptySecure) {
                            $secureLength = (Get-OpsPlainTextFromSecureString -SecureValue $capturedValue).Length
                            $isEmptySecure = ($secureLength -eq 0)
                        }

                        if ($isEmptySecure -and $null -ne $defaultValue) {
                            if ($defaultValue -is [SecureString]) {
                                $capturedValue = $defaultValue
                            }
                            else {
                                $capturedValue = ConvertTo-SecureString -String ([string]$defaultValue) -AsPlainText -Force
                            }
                        }
                    }
                    'int' {
                        $rawValue = Read-Host -Prompt $label
                        if ([string]::IsNullOrWhiteSpace($rawValue) -and $null -ne $defaultValue) {
                            $capturedValue = [int]$defaultValue
                        }
                        else {
                            $parsedInt = 0
                            if (-not [int]::TryParse($rawValue, [ref]$parsedInt)) {
                                Write-OpsUI -Text "Valeur invalide pour '$label'. Correction attendue : saisissez un entier." -Color Error -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
                                continue
                            }

                            $capturedValue = $parsedInt
                        }
                    }
                    'choice' {
                        $choiceValues = @()
                        if ($field.ContainsKey('Choices')) {
                            $choiceValues = ConvertTo-OpsFormChoiceList -ChoiceInput $field['Choices']
                        }
                        elseif ($field.ContainsKey('Options')) {
                            $choiceValues = ConvertTo-OpsFormChoiceList -ChoiceInput $field['Options']
                        }

                        if (@($choiceValues).Count -eq 0) {
                            throw "Le champ '$label' de type Choice ne contient aucune option. Correction attendue : renseignez Choices."
                        }

                        for ($choiceIndex = 0; $choiceIndex -lt @($choiceValues).Count; $choiceIndex++) {
                            $choiceLine = '{0}. {1}' -f ($choiceIndex + 1), $choiceValues[$choiceIndex].Label
                            Write-OpsUI -Text $choiceLine -Color Text -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
                        }

                        $choiceInput = Read-Host -Prompt "$label (numéro)"
                        if ([string]::IsNullOrWhiteSpace($choiceInput) -and $null -ne $defaultValue) {
                            $capturedValue = [string]$defaultValue
                        }
                        else {
                            $parsedChoiceIndex = 0
                            if (-not [int]::TryParse($choiceInput, [ref]$parsedChoiceIndex)) {
                                Write-OpsUI -Text "Saisie invalide pour '$label'. Correction attendue : saisissez le numéro d'une option." -Color Error -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
                                continue
                            }

                            $candidateChoiceIndex = $parsedChoiceIndex - 1
                            if ($candidateChoiceIndex -lt 0 -or $candidateChoiceIndex -ge @($choiceValues).Count) {
                                Write-OpsUI -Text "Choix invalide pour '$label'. Correction attendue : utilisez un numéro de la liste." -Color Error -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
                                continue
                            }

                            $capturedValue = $choiceValues[$candidateChoiceIndex].Value
                        }
                    }
                    default {
                        $rawText = Read-Host -Prompt $label
                        if ([string]::IsNullOrWhiteSpace($rawText) -and $null -ne $defaultValue) {
                            $capturedValue = [string]$defaultValue
                        }
                        else {
                            $capturedValue = [string]$rawText
                        }
                    }
                }
            }

            if ($type.ToLowerInvariant() -eq 'securestring' -and $null -ne $capturedValue -and -not ($capturedValue -is [SecureString])) {
                $capturedValue = ConvertTo-SecureString -String ([string]$capturedValue) -AsPlainText -Force
            }

            if ($type.ToLowerInvariant() -eq 'int' -and $null -ne $capturedValue -and -not ($capturedValue -is [int])) {
                try {
                    $capturedValue = [int]$capturedValue
                }
                catch {
                    Write-OpsUI -Text "Valeur invalide pour '$label'. Correction attendue : saisissez un entier." -Color Error -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
                    if ($nonInteractiveMode) {
                        $capturedValue = $null
                        break
                    }

                    continue
                }
            }

            $validationResult = Test-OpsFormFieldValue -Field $field -Value $capturedValue
            if (-not $validationResult.IsValid) {
                Write-OpsUI -Text ("Validation échouée pour '{0}' : {1}" -f $label, $validationResult.Message) -Color Error -Plain:$capabilities.IsPlainMode -Ascii:$Ascii | Out-Null
                if ($nonInteractiveMode) {
                    $capturedValue = $null
                    break
                }

                continue
            }

            $results[$name] = $capturedValue
            if (Get-Command -Name Write-OpsLog -ErrorAction SilentlyContinue) {
                try {
                    Write-OpsLog -Level Decision -Message ("Form field '{0}' captured." -f $name) | Out-Null
                }
                catch {
                }
            }

            break
        }
    }

    return $results
}
