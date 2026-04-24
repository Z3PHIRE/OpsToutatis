function Test-IIS-SiteBasicRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-IIS-SiteBasicEffectiveParameters -DesiredParameters $DesiredParameters
    $siteName = [string]$effectiveParameters['SiteName']
    $bindingPort = [int]$effectiveParameters['BindingPort']
    $physicalPath = [string]$effectiveParameters['PhysicalPath']
    $appPoolName = [string]$effectiveParameters['AppPoolName']

    $remoteState = Invoke-OpsRemote -Target $Target -ScriptBlock {
        param(
            [string]$SiteName,
            [int]$BindingPort,
            [string]$PhysicalPath,
            [string]$AppPoolName
        )

        $isWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
        $productType = 0
        $iisFeatureInstalled = $false
        $directoryExists = $false
        $appPoolExists = $false
        $siteExists = $false
        $sitePathMatches = $false
        $siteAppPoolMatches = $false
        $bindingPortMatches = $false
        $errors = @()

        if ($isWindows) {
            try {
                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $productType = [int]$osInfo.ProductType
            }
            catch {
                $errors += ('OS probe failed: {0}' -f $_.Exception.Message)
            }

            $featureCommand = Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue
            if ($null -ne $featureCommand) {
                try {
                    $featureState = Get-WindowsFeature -Name 'Web-Server' -ErrorAction Stop
                    $iisFeatureInstalled = [bool]$featureState.Installed
                }
                catch {
                    $errors += ('Feature probe failed: {0}' -f $_.Exception.Message)
                }
            }

            $directoryExists = Test-Path -LiteralPath $PhysicalPath -PathType Container

            try {
                Import-Module WebAdministration -ErrorAction Stop | Out-Null

                $appPoolPath = ('IIS:\AppPools\{0}' -f $AppPoolName)
                $appPoolExists = Test-Path -LiteralPath $appPoolPath

                $site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
                if ($null -ne $site) {
                    $siteExists = $true

                    if ($site.PSObject.Properties['PhysicalPath']) {
                        $sitePathMatches = ([string]$site.PhysicalPath).Equals($PhysicalPath, [System.StringComparison]::OrdinalIgnoreCase)
                    }

                    if ($site.PSObject.Properties['ApplicationPool']) {
                        $siteAppPoolMatches = ([string]$site.ApplicationPool).Equals($AppPoolName, [System.StringComparison]::OrdinalIgnoreCase)
                    }

                    foreach ($binding in @($site.Bindings.Collection)) {
                        $bindingInformation = [string]$binding.BindingInformation
                        if ($bindingInformation -match (':{0}:' -f $BindingPort)) {
                            $bindingPortMatches = $true
                            break
                        }
                    }
                }
            }
            catch {
                $errors += ('IIS probe failed: {0}' -f $_.Exception.Message)
            }
        }

        return [pscustomobject]@{
            IsWindows           = [bool]$isWindows
            ProductType         = [int]$productType
            IsServerOS          = ([bool]$isWindows -and [int]$productType -ne 1)
            IisFeatureInstalled = [bool]$iisFeatureInstalled
            DirectoryExists     = [bool]$directoryExists
            AppPoolExists       = [bool]$appPoolExists
            SiteExists          = [bool]$siteExists
            SitePathMatches     = [bool]$sitePathMatches
            SiteAppPoolMatches  = [bool]$siteAppPoolMatches
            BindingPortMatches  = [bool]$bindingPortMatches
            Errors              = @($errors)
        }
    } -ArgumentList @($siteName, $bindingPort, $physicalPath, $appPoolName)

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $remoteState

    $isCompliant = (
        [bool]$stateTable['IisFeatureInstalled'] -and
        [bool]$stateTable['DirectoryExists'] -and
        [bool]$stateTable['AppPoolExists'] -and
        [bool]$stateTable['SiteExists'] -and
        [bool]$stateTable['SitePathMatches'] -and
        [bool]$stateTable['SiteAppPoolMatches'] -and
        [bool]$stateTable['BindingPortMatches']
    )

    return [pscustomobject]@{
        IsCompliant          = $isCompliant
        IsWindows            = [bool]$stateTable['IsWindows']
        IsServerOS           = [bool]$stateTable['IsServerOS']
        IisFeatureInstalled  = [bool]$stateTable['IisFeatureInstalled']
        DirectoryExists      = [bool]$stateTable['DirectoryExists']
        AppPoolExists        = [bool]$stateTable['AppPoolExists']
        SiteExists           = [bool]$stateTable['SiteExists']
        SitePathMatches      = [bool]$stateTable['SitePathMatches']
        SiteAppPoolMatches   = [bool]$stateTable['SiteAppPoolMatches']
        BindingPortMatches   = [bool]$stateTable['BindingPortMatches']
        ExpectedSiteName     = $siteName
        ExpectedBindingPort  = $bindingPort
        ExpectedPhysicalPath = $physicalPath
        ExpectedAppPoolName  = $appPoolName
        Errors               = @($stateTable['Errors'])
    }
}
