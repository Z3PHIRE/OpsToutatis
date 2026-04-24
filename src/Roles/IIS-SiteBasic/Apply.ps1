function Invoke-IIS-SiteBasicApply {
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
            throw 'Action IIS-SiteBasic invalide. Type/Label requis.'
        }

        $actionType = [string]$actionTable['Type']
        $actionLabel = [string]$actionTable['Label']
        $actionData = ConvertTo-OpsPropertyTable -InputObject $actionTable['Data']
        if ($null -eq $actionData) {
            $actionData = @{}
        }

        Write-OpsTransportLog -Level Action -Message ("IIS-SiteBasic action: type={0}; label={1}" -f $actionType, $actionLabel)

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
            'EnsureDirectory' {
                $physicalPath = [string]$actionData['PhysicalPath']
                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$PhysicalPath
                    )

                    if (-not (Test-Path -LiteralPath $PhysicalPath -PathType Container)) {
                        New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null
                    }
                } -ArgumentList @($physicalPath) | Out-Null
            }
            'EnsureAppPool' {
                $appPoolName = [string]$actionData['AppPoolName']
                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$AppPoolName
                    )

                    Import-Module WebAdministration -ErrorAction Stop | Out-Null
                    $appPoolPath = ('IIS:\AppPools\{0}' -f $AppPoolName)
                    if (-not (Test-Path -LiteralPath $appPoolPath)) {
                        New-WebAppPool -Name $AppPoolName -ErrorAction Stop | Out-Null
                    }
                } -ArgumentList @($appPoolName) | Out-Null
            }
            'EnsureWebsite' {
                $siteName = [string]$actionData['SiteName']
                $bindingPort = [int]$actionData['BindingPort']
                $physicalPath = [string]$actionData['PhysicalPath']
                $appPoolName = [string]$actionData['AppPoolName']

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$SiteName,
                        [int]$BindingPort,
                        [string]$PhysicalPath,
                        [string]$AppPoolName
                    )

                    Import-Module WebAdministration -ErrorAction Stop | Out-Null

                    if (-not (Test-Path -LiteralPath $PhysicalPath -PathType Container)) {
                        New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null
                    }

                    $appPoolPath = ('IIS:\AppPools\{0}' -f $AppPoolName)
                    if (-not (Test-Path -LiteralPath $appPoolPath)) {
                        New-WebAppPool -Name $AppPoolName -ErrorAction Stop | Out-Null
                    }

                    $site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
                    if ($null -eq $site) {
                        New-Website -Name $SiteName -Port $BindingPort -PhysicalPath $PhysicalPath -ApplicationPool $AppPoolName -ErrorAction Stop | Out-Null
                    }
                    else {
                        Set-ItemProperty -Path ('IIS:\Sites\{0}' -f $SiteName) -Name physicalPath -Value $PhysicalPath -ErrorAction Stop | Out-Null
                        Set-ItemProperty -Path ('IIS:\Sites\{0}' -f $SiteName) -Name applicationPool -Value $AppPoolName -ErrorAction Stop | Out-Null

                        foreach ($binding in @($site.Bindings.Collection)) {
                            if ([string]$binding.protocol -eq 'http') {
                                Remove-WebBinding -Name $SiteName -Protocol http -Port ($binding.bindingInformation.Split(':')[1]) -ErrorAction SilentlyContinue | Out-Null
                            }
                        }

                        New-WebBinding -Name $SiteName -Protocol http -Port $BindingPort -ErrorAction Stop | Out-Null
                    }
                } -ArgumentList @($siteName, $bindingPort, $physicalPath, $appPoolName) | Out-Null
            }
            default {
                throw "Action IIS-SiteBasic non supportée : '$actionType'."
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
