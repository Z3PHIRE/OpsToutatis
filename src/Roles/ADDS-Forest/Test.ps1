function Test-ADDS-ForestRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-ADDS-ForestEffectiveParameters -DesiredParameters $DesiredParameters
    $domainName = [string]$effectiveParameters['DomainName']

    $remoteState = Invoke-OpsRemote -Target $Target -ScriptBlock {
        param(
            [string]$ExpectedDomainName
        )

        $isWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
        $osCaption = ''
        $productType = 0
        $domainRole = 0
        $currentDomainName = ''
        $featureInstalled = $false
        $domainLookupSucceeded = $false
        $dnsLookupSucceeded = $false
        $dnsRecordValue = ''
        $errors = @()

        if ($isWindows) {
            try {
                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $osCaption = [string]$osInfo.Caption
                $productType = [int]$osInfo.ProductType
            }
            catch {
                $errors += ('OS probe failed: {0}' -f $_.Exception.Message)
            }

            try {
                $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                $domainRole = [int]$computerSystem.DomainRole
                $currentDomainName = [string]$computerSystem.Domain
            }
            catch {
                $errors += ('Domain role probe failed: {0}' -f $_.Exception.Message)
            }

            $featureCommand = Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue
            if ($null -ne $featureCommand) {
                try {
                    $featureState = Get-WindowsFeature -Name 'AD-Domain-Services' -ErrorAction Stop
                    $featureInstalled = [bool]$featureState.Installed
                }
                catch {
                    $errors += ('Feature probe failed: {0}' -f $_.Exception.Message)
                }
            }

            if ($domainRole -ge 4) {
                $adDomainCommand = Get-Command -Name Get-ADDomain -ErrorAction SilentlyContinue
                if ($null -ne $adDomainCommand) {
                    try {
                        Import-Module ActiveDirectory -ErrorAction Stop | Out-Null
                        $null = Get-ADDomain -Identity $ExpectedDomainName -ErrorAction Stop
                        $domainLookupSucceeded = $true
                    }
                    catch {
                        $errors += ('Get-ADDomain failed: {0}' -f $_.Exception.Message)
                    }
                }

                $resolveDnsCommand = Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue
                if ($null -ne $resolveDnsCommand) {
                    try {
                        $dnsResult = Resolve-DnsName -Name $ExpectedDomainName -ErrorAction Stop | Select-Object -First 1
                        if ($null -ne $dnsResult) {
                            $dnsLookupSucceeded = $true
                            if ($dnsResult.PSObject.Properties['NameHost']) {
                                $dnsRecordValue = [string]$dnsResult.NameHost
                            }
                            elseif ($dnsResult.PSObject.Properties['Name']) {
                                $dnsRecordValue = [string]$dnsResult.Name
                            }
                        }
                    }
                    catch {
                        $errors += ('DNS lookup failed: {0}' -f $_.Exception.Message)
                    }
                }
            }
        }

        return [pscustomobject]@{
            IsWindows            = [bool]$isWindows
            OsCaption            = $osCaption
            ProductType          = [int]$productType
            DomainRole           = [int]$domainRole
            CurrentDomainName    = $currentDomainName
            FeatureInstalled     = [bool]$featureInstalled
            DomainLookupSucceeded = [bool]$domainLookupSucceeded
            DnsLookupSucceeded   = [bool]$dnsLookupSucceeded
            DnsRecordValue       = $dnsRecordValue
            Errors               = @($errors)
        }
    } -ArgumentList @($domainName)

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $remoteState
    $domainRole = 0
    if ($null -ne $stateTable -and $stateTable.ContainsKey('DomainRole')) {
        $domainRole = [int]$stateTable['DomainRole']
    }

    $isDomainController = ($domainRole -ge 4)
    $isServerOs = ([bool]$stateTable['IsWindows'] -and [int]$stateTable['ProductType'] -ne 1)

    $currentDomainName = [string]$stateTable['CurrentDomainName']
    $domainMatches = $false
    if (-not [string]::IsNullOrWhiteSpace($currentDomainName)) {
        $domainMatches = $currentDomainName.Equals($domainName, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $isCompliant = (
        $isDomainController -and
        $domainMatches -and
        [bool]$stateTable['DomainLookupSucceeded'] -and
        [bool]$stateTable['DnsLookupSucceeded']
    )

    return [pscustomobject]@{
        IsCompliant          = $isCompliant
        IsWindows            = [bool]$stateTable['IsWindows']
        IsServerOS           = $isServerOs
        ProductType          = [int]$stateTable['ProductType']
        DomainRole           = $domainRole
        IsDomainController   = $isDomainController
        CurrentDomainName    = $currentDomainName
        DomainMatches        = $domainMatches
        FeatureInstalled     = [bool]$stateTable['FeatureInstalled']
        DomainLookupSucceeded = [bool]$stateTable['DomainLookupSucceeded']
        DnsLookupSucceeded   = [bool]$stateTable['DnsLookupSucceeded']
        DnsRecordValue       = [string]$stateTable['DnsRecordValue']
        Errors               = @($stateTable['Errors'])
        ExpectedDomainName   = $domainName
    }
}
