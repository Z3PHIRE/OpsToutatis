function Invoke-ADDS-ForestApply {
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
            throw 'Action ADDS-Forest invalide. Type/Label requis.'
        }

        $actionType = [string]$actionTable['Type']
        $actionLabel = [string]$actionTable['Label']

        Write-OpsTransportLog -Level Action -Message ("ADDS-Forest action: type={0}; label={1}" -f $actionType, $actionLabel)

        $actionData = ConvertTo-OpsPropertyTable -InputObject $actionTable['Data']
        if ($null -eq $actionData) {
            $actionData = @{}
        }

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
            'InstallADDSForest' {
                $domainName = [string]$actionData['DomainName']
                $netBiosName = [string]$actionData['NetBIOSName']
                $dsrmPassword = $actionData['DSRMPassword']
                $forestFunctionalLevel = [string]$actionData['ForestFunctionalLevel']
                $siteName = [string]$actionData['SiteName']
                $installDns = [bool]$actionData['InstallDNS']

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$DomainName,
                        [string]$NetBIOSName,
                        [SecureString]$DSRMPassword,
                        [string]$ForestFunctionalLevel,
                        [string]$SiteName,
                        [bool]$InstallDns
                    )

                    Import-Module ADDSDeployment -ErrorAction Stop | Out-Null

                    $installParameters = @{
                        DomainName                    = $DomainName
                        DomainNetbiosName             = $NetBIOSName
                        SafeModeAdministratorPassword = $DSRMPassword
                        ForestMode                    = $ForestFunctionalLevel
                        SiteName                      = $SiteName
                        InstallDns                    = $InstallDns
                        SkipPreChecks                 = $false
                        NoRebootOnCompletion          = $true
                        Force                         = $true
                        Confirm                       = $false
                    }

                    Install-ADDSForest @installParameters -ErrorAction Stop | Out-Null
                } -ArgumentList @($domainName, $netBiosName, $dsrmPassword, $forestFunctionalLevel, $siteName, $installDns) | Out-Null
            }
            'ManualRebootRequired' {
                $pendingRestart = $true
                Write-Information 'Redémarrage AD DS requis. Aucun redémarrage automatique ne sera lancé.' -InformationAction Continue
                Write-Information 'Planification recommandée : programmez un créneau, puis redémarrez manuellement la machine cible.' -InformationAction Continue
            }
            default {
                throw "Action ADDS-Forest non supportée : '$actionType'."
            }
        }

        $appliedActions += [pscustomobject]@{
            Type  = $actionType
            Label = $actionLabel
        }
    }

    $message = 'Apply ADDS-Forest terminé.'
    if ($pendingRestart) {
        $message = 'Apply ADDS-Forest terminé. Redémarrage manuel requis.'
    }

    return [pscustomobject]@{
        AppliedActionCount = @($appliedActions).Count
        AppliedActions     = @($appliedActions)
        PendingRestart     = $pendingRestart
        Message            = $message
    }
}
