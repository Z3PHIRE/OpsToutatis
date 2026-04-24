function Invoke-DHCP-ScopeApply {
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
            throw 'Action DHCP-Scope invalide. Type/Label requis.'
        }

        $actionType = [string]$actionTable['Type']
        $actionLabel = [string]$actionTable['Label']
        $actionData = ConvertTo-OpsPropertyTable -InputObject $actionTable['Data']
        if ($null -eq $actionData) {
            $actionData = @{}
        }

        Write-OpsTransportLog -Level Action -Message ("DHCP-Scope action: type={0}; label={1}" -f $actionType, $actionLabel)

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
            'EnsureDhcpScope' {
                $scopeName = [string]$actionData['ScopeName']
                $startRange = [string]$actionData['StartRange']
                $endRange = [string]$actionData['EndRange']
                $subnetMask = [string]$actionData['SubnetMask']
                $leaseDurationHours = [int]$actionData['LeaseDurationHours']

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$ScopeName,
                        [string]$StartRange,
                        [string]$EndRange,
                        [string]$SubnetMask,
                        [int]$LeaseDurationHours
                    )

                    $leaseDuration = [TimeSpan]::FromHours($LeaseDurationHours)
                    $existingScope = $null
                    try {
                        $allScopes = @(Get-DhcpServerv4Scope -ErrorAction Stop)
                        foreach ($candidateScope in $allScopes) {
                            if ([string]$candidateScope.Name -eq $ScopeName) {
                                $existingScope = $candidateScope
                                break
                            }
                        }
                    }
                    catch {
                        $existingScope = $null
                    }

                    if ($null -eq $existingScope) {
                        Add-DhcpServerv4Scope -Name $ScopeName -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask -LeaseDuration $leaseDuration -ErrorAction Stop | Out-Null
                    }
                    else {
                        Set-DhcpServerv4Scope -ScopeId $existingScope.ScopeId -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask -LeaseDuration $leaseDuration -State Active -ErrorAction Stop | Out-Null
                    }
                } -ArgumentList @($scopeName, $startRange, $endRange, $subnetMask, $leaseDurationHours) | Out-Null
            }
            'ConfigureDhcpOptions' {
                $scopeName = [string]$actionData['ScopeName']
                $router = [string]$actionData['Router']
                $dnsServers = @($actionData['DnsServers'])

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$ScopeName,
                        [string]$Router,
                        [string[]]$DnsServers
                    )

                    $scope = $null
                    $allScopes = @(Get-DhcpServerv4Scope -ErrorAction Stop)
                    foreach ($candidateScope in $allScopes) {
                        if ([string]$candidateScope.Name -eq $ScopeName) {
                            $scope = $candidateScope
                            break
                        }
                    }

                    if ($null -eq $scope) {
                        throw "Scope DHCP '$ScopeName' introuvable pendant la configuration des options."
                    }

                    Set-DhcpServerv4OptionValue -ScopeId $scope.ScopeId -Router $Router -DnsServer @($DnsServers) -ErrorAction Stop | Out-Null
                } -ArgumentList @($scopeName, $router, @($dnsServers)) | Out-Null
            }
            default {
                throw "Action DHCP-Scope non supportée : '$actionType'."
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
