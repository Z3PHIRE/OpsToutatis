function Invoke-ADDS-AdditionalDCApply {
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
    $pendingRestart = $false

    foreach ($planAction in @($PlanActions)) {
        $actionTable = ConvertTo-OpsPropertyTable -InputObject $planAction
        if ($null -eq $actionTable) {
            throw 'Action ADDS-AdditionalDC invalide. Type/Label requis.'
        }

        $actionType = [string]$actionTable['Type']
        $actionLabel = [string]$actionTable['Label']
        $actionData = ConvertTo-OpsPropertyTable -InputObject $actionTable['Data']
        if ($null -eq $actionData) {
            $actionData = @{}
        }

        Write-OpsTransportLog -Level Action -Message ("ADDS-AdditionalDC action: type={0}; label={1}" -f $actionType, $actionLabel)

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
            'PromoteAdditionalDomainController' {
                $domainName = [string]$actionData['DomainName']
                $siteName = [string]$actionData['SiteName']
                $dsrmPassword = $actionData['DSRMPassword']
                $installDns = [bool]$actionData['InstallDNS']
                $replicationSourceDc = [string]$actionData['ReplicationSourceDC']

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$DomainName,
                        [string]$SiteName,
                        [SecureString]$DSRMPassword,
                        [bool]$InstallDns,
                        [string]$ReplicationSourceDc
                    )

                    Import-Module ADDSDeployment -ErrorAction Stop | Out-Null

                    $installParameters = @{
                        DomainName                    = $DomainName
                        SiteName                      = $SiteName
                        SafeModeAdministratorPassword = $DSRMPassword
                        InstallDns                    = $InstallDns
                        SkipPreChecks                 = $false
                        NoRebootOnCompletion          = $true
                        Force                         = $true
                        Confirm                       = $false
                    }

                    if (-not [string]::IsNullOrWhiteSpace($ReplicationSourceDc)) {
                        $installParameters['ReplicationSourceDC'] = $ReplicationSourceDc
                    }

                    Install-ADDSDomainController @installParameters -ErrorAction Stop | Out-Null
                } -ArgumentList @($domainName, $siteName, $dsrmPassword, $installDns, $replicationSourceDc) | Out-Null
            }
            'ManualRebootRequired' {
                $pendingRestart = $true
                Write-Information 'Redémarrage AD DS requis. Aucun redémarrage automatique ne sera lancé.' -InformationAction Continue
                Write-Information 'Planification recommandée : programmez un créneau, puis redémarrez manuellement la machine cible.' -InformationAction Continue
            }
            default {
                throw "Action ADDS-AdditionalDC non supportée : '$actionType'."
            }
        }

        $appliedActions += [pscustomobject]@{
            Type  = $actionType
            Label = $actionLabel
        }
    }

    $message = 'Apply ADDS-AdditionalDC terminé.'
    if ($pendingRestart) {
        $message = 'Apply ADDS-AdditionalDC terminé. Redémarrage manuel requis.'
    }

    return [pscustomobject]@{
        AppliedActionCount = @($appliedActions).Count
        AppliedActions     = @($appliedActions)
        PendingRestart     = $pendingRestart
        Message            = $message
    }
}
