function Invoke-DNS-PrimaryApply {
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

    $appliedActions = @()

    foreach ($planAction in @($PlanActions)) {
        $actionTable = ConvertTo-OpsPropertyTable -InputObject $planAction
        if ($null -eq $actionTable) {
            throw 'Action DNS-Primary invalide. Type/Label requis.'
        }

        $actionType = [string]$actionTable['Type']
        $actionLabel = [string]$actionTable['Label']
        $actionData = ConvertTo-OpsPropertyTable -InputObject $actionTable['Data']
        if ($null -eq $actionData) {
            $actionData = @{}
        }

        Write-OpsTransportLog -Level Action -Message ("DNS-Primary action: type={0}; label={1}" -f $actionType, $actionLabel)

        switch ($actionType) {
            'InstallWindowsFeature' {
                $featureName = [string]$actionData['FeatureName']
                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$FeatureName
                    )

                    $featureCommand = Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue
                    if ($null -eq $featureCommand) {
                        throw 'Get-WindowsFeature est indisponible. Utilisez Windows Server avec ServerManager.'
                    }

                    $featureState = Get-WindowsFeature -Name $FeatureName -ErrorAction Stop
                    if (-not [bool]$featureState.Installed) {
                        Install-WindowsFeature -Name $FeatureName -IncludeManagementTools -ErrorAction Stop | Out-Null
                    }
                } -ArgumentList @($featureName) | Out-Null
            }
            'CreatePrimaryZone' {
                $zoneName = [string]$actionData['ZoneName']
                $zoneFile = [string]$actionData['ZoneFile']

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$ZoneName,
                        [string]$ZoneFile
                    )

                    $zone = $null
                    try {
                        $zone = Get-DnsServerZone -Name $ZoneName -ErrorAction Stop
                    }
                    catch {
                        $zone = $null
                    }

                    if ($null -eq $zone) {
                        Add-DnsServerPrimaryZone -Name $ZoneName -ZoneFile $ZoneFile -DynamicUpdate None -ErrorAction Stop | Out-Null
                    }
                } -ArgumentList @($zoneName, $zoneFile) | Out-Null
            }
            'ReplaceAdIntegratedZone' {
                $zoneName = [string]$actionData['ZoneName']
                $zoneFile = [string]$actionData['ZoneFile']

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$ZoneName,
                        [string]$ZoneFile
                    )

                    $zone = Get-DnsServerZone -Name $ZoneName -ErrorAction Stop
                    if ($null -ne $zone -and [bool]$zone.IsDsIntegrated) {
                        Remove-DnsServerZone -Name $ZoneName -Force -ErrorAction Stop | Out-Null
                        Add-DnsServerPrimaryZone -Name $ZoneName -ZoneFile $ZoneFile -DynamicUpdate None -ErrorAction Stop | Out-Null
                    }
                } -ArgumentList @($zoneName, $zoneFile) | Out-Null
            }
            default {
                throw "Action DNS-Primary non supportée : '$actionType'."
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
