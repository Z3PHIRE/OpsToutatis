function Test-DNS-PrimaryRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-DNS-PrimaryEffectiveParameters -DesiredParameters $DesiredParameters
    $zoneName = [string]$effectiveParameters['ZoneName']

    $remoteState = Invoke-OpsRemote -Target $Target -ScriptBlock {
        param(
            [string]$ZoneName
        )

        $isWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
        $productType = 0
        $dnsFeatureInstalled = $false
        $zoneExists = $false
        $zoneIsDsIntegrated = $false
        $zoneType = ''
        $zoneFile = ''
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
                    $featureState = Get-WindowsFeature -Name 'DNS' -ErrorAction Stop
                    $dnsFeatureInstalled = [bool]$featureState.Installed
                }
                catch {
                    $errors += ('Feature probe failed: {0}' -f $_.Exception.Message)
                }
            }

            $zoneCommand = Get-Command -Name Get-DnsServerZone -ErrorAction SilentlyContinue
            if ($null -ne $zoneCommand) {
                try {
                    $zone = Get-DnsServerZone -Name $ZoneName -ErrorAction Stop
                    if ($null -ne $zone) {
                        $zoneExists = $true
                        if ($zone.PSObject.Properties['IsDsIntegrated']) {
                            $zoneIsDsIntegrated = [bool]$zone.IsDsIntegrated
                        }

                        if ($zone.PSObject.Properties['ZoneType']) {
                            $zoneType = [string]$zone.ZoneType
                        }

                        if ($zone.PSObject.Properties['ZoneFile']) {
                            $zoneFile = [string]$zone.ZoneFile
                        }
                    }
                }
                catch {
                }
            }
        }

        return [pscustomobject]@{
            IsWindows           = [bool]$isWindows
            ProductType         = [int]$productType
            IsServerOS          = ([bool]$isWindows -and [int]$productType -ne 1)
            DnsFeatureInstalled = [bool]$dnsFeatureInstalled
            ZoneExists          = [bool]$zoneExists
            ZoneIsDsIntegrated  = [bool]$zoneIsDsIntegrated
            ZoneType            = $zoneType
            ZoneFile            = $zoneFile
            Errors              = @($errors)
        }
    } -ArgumentList @($zoneName)

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $remoteState
    $isCompliant = (
        [bool]$stateTable['DnsFeatureInstalled'] -and
        [bool]$stateTable['ZoneExists'] -and
        -not [bool]$stateTable['ZoneIsDsIntegrated'] -and
        ([string]$stateTable['ZoneType'] -match '^Primary$')
    )

    return [pscustomobject]@{
        IsCompliant           = $isCompliant
        IsWindows             = [bool]$stateTable['IsWindows']
        IsServerOS            = [bool]$stateTable['IsServerOS']
        DnsFeatureInstalled   = [bool]$stateTable['DnsFeatureInstalled']
        ZoneExists            = [bool]$stateTable['ZoneExists']
        ZoneIsDsIntegrated    = [bool]$stateTable['ZoneIsDsIntegrated']
        ZoneType              = [string]$stateTable['ZoneType']
        ZoneFile              = [string]$stateTable['ZoneFile']
        ExpectedZoneName      = $zoneName
        ExpectedZoneFile      = [string]$effectiveParameters['ZoneFile']
        Errors                = @($stateTable['Errors'])
    }
}
