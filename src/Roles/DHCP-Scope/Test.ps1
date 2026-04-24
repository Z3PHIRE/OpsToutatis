function Test-DHCP-ScopeRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-DHCP-ScopeEffectiveParameters -DesiredParameters $DesiredParameters
    $scopeName = [string]$effectiveParameters['ScopeName']
    $startRange = [string]$effectiveParameters['StartRange']
    $endRange = [string]$effectiveParameters['EndRange']
    $subnetMask = [string]$effectiveParameters['SubnetMask']
    $router = [string]$effectiveParameters['Router']
    $dnsServers = @($effectiveParameters['DnsServers'])
    $leaseDurationHours = [int]$effectiveParameters['LeaseDurationHours']

    $remoteState = Invoke-OpsRemote -Target $Target -ScriptBlock {
        param(
            [string]$ScopeName,
            [string]$StartRange,
            [string]$EndRange,
            [string]$SubnetMask,
            [string]$Router,
            [string[]]$DnsServers,
            [int]$LeaseDurationHours
        )

        $isWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
        $productType = 0
        $dhcpFeatureInstalled = $false
        $scopeExists = $false
        $scopeId = ''
        $scopeMatchesRange = $false
        $scopeMatchesMask = $false
        $scopeMatchesLease = $false
        $routerMatches = $false
        $dnsMatches = $false
        $isAuthorizedInAD = $false
        $authorizationReason = ''
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
                    $featureState = Get-WindowsFeature -Name 'DHCP' -ErrorAction Stop
                    $dhcpFeatureInstalled = [bool]$featureState.Installed
                }
                catch {
                    $errors += ('Feature probe failed: {0}' -f $_.Exception.Message)
                }
            }

            $scope = $null
            try {
                $allScopes = @(Get-DhcpServerv4Scope -ErrorAction Stop)
                foreach ($candidateScope in $allScopes) {
                    if ([string]$candidateScope.Name -eq $ScopeName) {
                        $scope = $candidateScope
                        break
                    }
                }
            }
            catch {
                $scope = $null
            }

            if ($null -ne $scope) {
                $scopeExists = $true
                $scopeId = [string]$scope.ScopeId
                $scopeMatchesRange = (
                    [string]$scope.StartRange -eq $StartRange -and
                    [string]$scope.EndRange -eq $EndRange
                )
                $scopeMatchesMask = ([string]$scope.SubnetMask -eq $SubnetMask)

                if ($scope.PSObject.Properties['LeaseDuration']) {
                    $leaseDuration = $scope.LeaseDuration
                    if ($null -ne $leaseDuration) {
                        $scopeMatchesLease = ([int]$leaseDuration.TotalHours -eq $LeaseDurationHours)
                    }
                }

                try {
                    $optionValue = Get-DhcpServerv4OptionValue -ScopeId $scope.ScopeId -ErrorAction Stop

                    if ($optionValue.PSObject.Properties['Router']) {
                        $routerValues = @($optionValue.Router | ForEach-Object { [string]$_ })
                        $routerMatches = ($routerValues -contains $Router)
                    }

                    if ($optionValue.PSObject.Properties['DnsServer']) {
                        $configuredDns = @($optionValue.DnsServer | ForEach-Object { [string]$_ })
                        $configuredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($configuredDnsValue in $configuredDns) {
                            [void]$configuredSet.Add($configuredDnsValue)
                        }

                        $dnsMatches = $true
                        foreach ($expectedDns in @($DnsServers)) {
                            if (-not $configuredSet.Contains([string]$expectedDns)) {
                                $dnsMatches = $false
                                break
                            }
                        }
                    }
                }
                catch {
                    $errors += ('DHCP option probe failed: {0}' -f $_.Exception.Message)
                }
            }

            $authorizationCommand = Get-Command -Name Get-DhcpServerInDC -ErrorAction SilentlyContinue
            if ($null -eq $authorizationCommand) {
                $isAuthorizedInAD = $false
                $authorizationReason = 'Get-DhcpServerInDC indisponible sur la cible.'
            }
            else {
                try {
                    $localHostName = [System.Net.Dns]::GetHostName()
                    $localFqdn = ''
                    try {
                        $localFqdn = [string]([System.Net.Dns]::GetHostEntry($localHostName).HostName)
                    }
                    catch {
                        $localFqdn = $localHostName
                    }

                    $localIpSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    try {
                        $addresses = [System.Net.Dns]::GetHostAddresses($localHostName)
                        foreach ($address in @($addresses)) {
                            if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                                [void]$localIpSet.Add([string]$address.IPAddressToString)
                            }
                        }
                    }
                    catch {
                    }

                    $authorizedServers = @(Get-DhcpServerInDC -ErrorAction Stop)
                    foreach ($authorizedServer in $authorizedServers) {
                        $authorizedDnsName = ''
                        $authorizedIpAddress = ''

                        if ($authorizedServer.PSObject.Properties['DnsName']) {
                            $authorizedDnsName = [string]$authorizedServer.DnsName
                        }

                        if ($authorizedServer.PSObject.Properties['IPAddress']) {
                            $authorizedIpAddress = [string]$authorizedServer.IPAddress
                        }

                        $dnsMatch = $false
                        if (-not [string]::IsNullOrWhiteSpace($authorizedDnsName)) {
                            $dnsMatch = (
                                $authorizedDnsName.Equals($localHostName, [System.StringComparison]::OrdinalIgnoreCase) -or
                                $authorizedDnsName.Equals($localFqdn, [System.StringComparison]::OrdinalIgnoreCase)
                            )
                        }

                        $ipMatch = $false
                        if (-not [string]::IsNullOrWhiteSpace($authorizedIpAddress)) {
                            $ipMatch = $localIpSet.Contains($authorizedIpAddress)
                        }

                        if ($dnsMatch -or $ipMatch) {
                            $isAuthorizedInAD = $true
                            break
                        }
                    }

                    if (-not $isAuthorizedInAD) {
                        $authorizationReason = 'Le serveur DHCP n''est pas autorisé dans Active Directory (Get-DhcpServerInDC).'
                    }
                }
                catch {
                    $isAuthorizedInAD = $false
                    $authorizationReason = ('Échec de vérification d''autorisation AD: {0}' -f $_.Exception.Message)
                }
            }
        }

        return [pscustomobject]@{
            IsWindows            = [bool]$isWindows
            ProductType          = [int]$productType
            IsServerOS           = ([bool]$isWindows -and [int]$productType -ne 1)
            DhcpFeatureInstalled = [bool]$dhcpFeatureInstalled
            ScopeExists          = [bool]$scopeExists
            ScopeId              = $scopeId
            ScopeMatchesRange    = [bool]$scopeMatchesRange
            ScopeMatchesMask     = [bool]$scopeMatchesMask
            ScopeMatchesLease    = [bool]$scopeMatchesLease
            RouterMatches        = [bool]$routerMatches
            DnsMatches           = [bool]$dnsMatches
            IsAuthorizedInAD     = [bool]$isAuthorizedInAD
            AuthorizationReason  = $authorizationReason
            Errors               = @($errors)
        }
    } -ArgumentList @($scopeName, $startRange, $endRange, $subnetMask, $router, @($dnsServers), $leaseDurationHours)

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $remoteState

    $isCompliant = (
        [bool]$stateTable['DhcpFeatureInstalled'] -and
        [bool]$stateTable['ScopeExists'] -and
        [bool]$stateTable['ScopeMatchesRange'] -and
        [bool]$stateTable['ScopeMatchesMask'] -and
        [bool]$stateTable['ScopeMatchesLease'] -and
        [bool]$stateTable['RouterMatches'] -and
        [bool]$stateTable['DnsMatches'] -and
        [bool]$stateTable['IsAuthorizedInAD']
    )

    return [pscustomobject]@{
        IsCompliant           = $isCompliant
        IsWindows             = [bool]$stateTable['IsWindows']
        IsServerOS            = [bool]$stateTable['IsServerOS']
        DhcpFeatureInstalled  = [bool]$stateTable['DhcpFeatureInstalled']
        ScopeExists           = [bool]$stateTable['ScopeExists']
        ScopeId               = [string]$stateTable['ScopeId']
        ScopeMatchesRange     = [bool]$stateTable['ScopeMatchesRange']
        ScopeMatchesMask      = [bool]$stateTable['ScopeMatchesMask']
        ScopeMatchesLease     = [bool]$stateTable['ScopeMatchesLease']
        RouterMatches         = [bool]$stateTable['RouterMatches']
        DnsMatches            = [bool]$stateTable['DnsMatches']
        IsAuthorizedInAD      = [bool]$stateTable['IsAuthorizedInAD']
        AuthorizationReason   = [string]$stateTable['AuthorizationReason']
        ExpectedScopeName     = $scopeName
        ExpectedStartRange    = $startRange
        ExpectedEndRange      = $endRange
        ExpectedSubnetMask    = $subnetMask
        ExpectedRouter        = $router
        ExpectedDnsServers    = @($dnsServers)
        ExpectedLeaseHours    = $leaseDurationHours
        Errors                = @($stateTable['Errors'])
    }
}

