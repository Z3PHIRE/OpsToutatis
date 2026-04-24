function Test-ADDS-AdditionalDCRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-ADDS-AdditionalDCEffectiveParameters -DesiredParameters $DesiredParameters
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
        [bool]$stateTable['DomainLookupSucceeded']
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
        Errors               = @($stateTable['Errors'])
        ExpectedDomainName   = $domainName
    }
}
