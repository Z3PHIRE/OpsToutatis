function Invoke-Demo-HelloApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object[]]$PlanActions,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters,

        [Parameter()]
        [AllowNull()]
        [object]$CurrentState
    )

    $normalizedActions = @($PlanActions)
    $appliedActions = @()
    foreach ($planAction in $normalizedActions) {
        $actionTable = ConvertTo-OpsPropertyTable -InputObject $planAction
        if ($null -eq $actionTable) {
            throw "Action de plan Demo-Hello invalide. Correction attendue : utilisez une hashtable d'action avec Type/Label."
        }

        $actionType = [string]$actionTable['Type']
        $actionLabel = [string]$actionTable['Label']

        try {
            Write-OpsLog -Level Action -Message ("Demo-Hello action: type={0}; label={1}" -f $actionType, $actionLabel) | Out-Null
        }
        catch {
            Write-OpsTransportLog -Level Action -Message ("Demo-Hello action: type={0}; label={1}" -f $actionType, $actionLabel)
        }

        $actionData = ConvertTo-OpsPropertyTable -InputObject $actionTable['Data']
        if ($null -eq $actionData) {
            $actionData = @{}
        }

        switch ($actionType) {
            'EnsureDirectory' {
                $outputPath = [string]$actionData['OutputPath']
                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$TargetOutputPath
                    )

                    $directoryPath = Split-Path -Path $TargetOutputPath -Parent
                    if (-not [string]::IsNullOrWhiteSpace($directoryPath) -and -not (Test-Path -LiteralPath $directoryPath)) {
                        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
                    }
                } -ArgumentList @($outputPath) | Out-Null
            }
            'WriteHelloFile' {
                $outputPath = [string]$actionData['OutputPath']
                $helloText = [string]$actionData['HelloText']
                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$TargetOutputPath,
                        [string]$TargetContent
                    )

                    $directoryPath = Split-Path -Path $TargetOutputPath -Parent
                    if (-not [string]::IsNullOrWhiteSpace($directoryPath) -and -not (Test-Path -LiteralPath $directoryPath)) {
                        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
                    }

                    Set-Content -LiteralPath $TargetOutputPath -Value $TargetContent -Encoding UTF8 -Force
                } -ArgumentList @($outputPath, $helloText) | Out-Null
            }
            default {
                throw "Action Demo-Hello non supportée : '$actionType'."
            }
        }

        $appliedActions += [pscustomobject]@{
            Type  = $actionType
            Label = $actionLabel
        }
    }

    return [pscustomobject]@{
        AppliedActionCount = @($appliedActions).Count
        AppliedActions     = @($appliedActions)
    }
}
