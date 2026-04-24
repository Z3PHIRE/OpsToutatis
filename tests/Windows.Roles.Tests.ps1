Set-StrictMode -Version Latest
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'OpsToutatis Windows Server roles' {
    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    InModuleScope OpsToutatis {
        BeforeAll {
            $script:WindowsRoleIds = @(
                'ADDS-Forest',
                'ADDS-AdditionalDC',
                'DNS-Primary',
                'DHCP-Scope',
                'FileServer-Share',
                'IIS-SiteBasic'
            )

            foreach ($roleId in $script:WindowsRoleIds) {
                Import-OpsRoleDefinition -RoleId $roleId -Force | Out-Null
            }

            $script:LocalTarget = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }
        }

        Context 'Parameter schema contract' {
            It 'returns valid Show-OpsForm schema entries for every Windows role' {
                foreach ($roleId in $script:WindowsRoleIds) {
                    $roleDefinition = Import-OpsRoleDefinition -RoleId $roleId -Force
                    $schemaFunctionName = [string]$roleDefinition.FunctionMap.Parameters
                    $schema = & $schemaFunctionName -Target $script:LocalTarget

                    if (@($schema).Count -eq 0) {
                        throw "Expected non-empty parameter schema for role '$roleId'."
                    }

                    foreach ($field in @($schema)) {
                        $fieldTable = ConvertTo-OpsPropertyTable -InputObject $field
                        if ($null -eq $fieldTable) {
                            throw "Invalid schema field object for role '$roleId'."
                        }

                        foreach ($requiredKey in @('Name', 'Label', 'Type')) {
                            if (-not $fieldTable.ContainsKey($requiredKey)) {
                                throw "Schema key '$requiredKey' is missing for role '$roleId'."
                            }

                            if ([string]::IsNullOrWhiteSpace([string]$fieldTable[$requiredKey])) {
                                throw "Schema key '$requiredKey' is empty for role '$roleId'."
                            }
                        }
                    }
                }
            }
        }

        Context 'Plan phase' {
            It 'builds expected plan actions without executing Install-WindowsFeature' {
                $createdInstallFeatureStub = $false
                $installFeatureCommand = Get-Command -Name Install-WindowsFeature -ErrorAction SilentlyContinue
                if ($null -eq $installFeatureCommand) {
                    Set-Item -Path Function:\Install-WindowsFeature -Value {
                        throw 'Install-WindowsFeature must not be called during Plan.'
                    } -Force
                    $createdInstallFeatureStub = $true
                }
                else {
                    Mock -CommandName Install-WindowsFeature -MockWith {
                        throw 'Install-WindowsFeature must not be called during Plan.'
                    }
                }

                $planCases = @(
                    @{
                        RoleId            = 'ADDS-Forest'
                        DesiredParameters = @{
                            DomainName            = 'corp.example'
                            NetBIOSName           = 'CORP'
                            DSRMPassword          = (ConvertTo-SecureString -String 'ComplexPass!1234' -AsPlainText -Force)
                            ForestFunctionalLevel = 'WinThreshold'
                            SiteName              = 'Default-First-Site-Name'
                            InstallDNS            = $true
                        }
                        CurrentState      = [pscustomobject]@{
                            IsWindows         = $true
                            IsServerOS        = $true
                            FeatureInstalled  = $false
                            IsDomainController = $false
                            DomainMatches     = $false
                            CurrentDomainName = ''
                        }
                        ExpectedActions   = @('InstallWindowsFeature', 'InstallADDSForest', 'ManualRebootRequired')
                    }
                    @{
                        RoleId            = 'ADDS-AdditionalDC'
                        DesiredParameters = @{
                            DomainName          = 'corp.example'
                            SiteName            = 'Default-First-Site-Name'
                            DSRMPassword        = (ConvertTo-SecureString -String 'ComplexPass!1234' -AsPlainText -Force)
                            InstallDNS          = $true
                            ReplicationSourceDC = 'DC01.corp.example'
                        }
                        CurrentState      = [pscustomobject]@{
                            IsWindows          = $true
                            IsServerOS         = $true
                            FeatureInstalled   = $false
                            IsDomainController = $false
                            DomainMatches      = $false
                            CurrentDomainName  = ''
                        }
                        ExpectedActions   = @('InstallWindowsFeature', 'PromoteAdditionalDomainController', 'ManualRebootRequired')
                    }
                    @{
                        RoleId            = 'DNS-Primary'
                        DesiredParameters = @{
                            ZoneName = 'corp.example'
                            ZoneFile = 'corp.example.dns'
                        }
                        CurrentState      = [pscustomobject]@{
                            IsWindows           = $true
                            IsServerOS          = $true
                            DnsFeatureInstalled = $false
                            ZoneExists          = $false
                            ZoneIsDsIntegrated  = $false
                        }
                        ExpectedActions   = @('InstallWindowsFeature', 'CreatePrimaryZone')
                    }
                    @{
                        RoleId            = 'DHCP-Scope'
                        DesiredParameters = @{
                            ScopeName          = 'Corp Clients'
                            StartRange         = '10.0.10.100'
                            EndRange           = '10.0.10.250'
                            SubnetMask         = '255.255.255.0'
                            Router             = '10.0.10.1'
                            DnsServers         = @('10.0.10.10', '10.0.10.11')
                            LeaseDurationHours = 24
                        }
                        CurrentState      = [pscustomobject]@{
                            IsWindows            = $true
                            IsServerOS           = $true
                            IsAuthorizedInAD     = $true
                            DhcpFeatureInstalled = $false
                            ScopeExists          = $false
                            ScopeMatchesRange    = $false
                            ScopeMatchesMask     = $false
                            ScopeMatchesLease    = $false
                            RouterMatches        = $false
                            DnsMatches           = $false
                        }
                        ExpectedActions   = @('InstallWindowsFeature', 'EnsureDhcpScope', 'ConfigureDhcpOptions')
                    }
                    @{
                        RoleId            = 'FileServer-Share'
                        DesiredParameters = @{
                            ShareName            = 'OpsData'
                            Path                 = 'C:\Shares\OpsData'
                            FullAccessPrincipals = @('BUILTIN\Administrators')
                            ReadAccessPrincipals = @('BUILTIN\Users')
                        }
                        CurrentState      = [pscustomobject]@{
                            IsWindows        = $true
                            IsServerOS       = $true
                            DirectoryExists  = $false
                            NtfsFullMatches  = $false
                            NtfsReadMatches  = $false
                            ShareExists      = $false
                            SharePathMatches = $false
                            ShareFullMatches = $false
                            ShareReadMatches = $false
                        }
                        ExpectedActions   = @('EnsureDirectory', 'SetNtfsAcl', 'EnsureSmbShare', 'SetSmbSharePermissions')
                    }
                    @{
                        RoleId            = 'IIS-SiteBasic'
                        DesiredParameters = @{
                            SiteName     = 'OpsSite'
                            BindingPort  = 8080
                            PhysicalPath = 'C:\inetpub\OpsSite'
                            AppPoolName  = 'OpsSitePool'
                        }
                        CurrentState      = [pscustomobject]@{
                            IsWindows           = $true
                            IsServerOS          = $true
                            IisFeatureInstalled = $false
                            DirectoryExists     = $false
                            AppPoolExists       = $false
                            SiteExists          = $false
                            SitePathMatches     = $false
                            SiteAppPoolMatches  = $false
                            BindingPortMatches  = $false
                        }
                        ExpectedActions   = @('InstallWindowsFeature', 'EnsureDirectory', 'EnsureAppPool', 'EnsureWebsite')
                    }
                )

                foreach ($planCase in $planCases) {
                    $roleDefinition = Import-OpsRoleDefinition -RoleId ([string]$planCase['RoleId']) -Force
                    $planFunctionName = [string]$roleDefinition.FunctionMap.Plan
                    $planResult = & $planFunctionName -Target $script:LocalTarget -CurrentState $planCase['CurrentState'] -DesiredParameters $planCase['DesiredParameters']
                    $planActions = ConvertTo-OpsPlanActionList -PlanResult $planResult
                    $actionTypes = @($planActions | ForEach-Object { [string]$_.Type })

                    foreach ($expectedActionType in @($planCase['ExpectedActions'])) {
                        if ($actionTypes -notcontains [string]$expectedActionType) {
                            throw "Expected action '$expectedActionType' missing in role '$([string]$planCase['RoleId'])'. Got: $($actionTypes -join ', ')"
                        }
                    }
                }

                if ($createdInstallFeatureStub -and (Test-Path -LiteralPath Function:\Install-WindowsFeature)) {
                    Remove-Item -LiteralPath Function:\Install-WindowsFeature -Force
                }
            }

            It 'refuses ADDS-Forest on non-server Windows explicitly' {
                $roleDefinition = Import-OpsRoleDefinition -RoleId 'ADDS-Forest' -Force
                $planFunctionName = [string]$roleDefinition.FunctionMap.Plan

                $errorMessage = $null
                try {
                    & $planFunctionName -Target $script:LocalTarget -CurrentState ([pscustomobject]@{
                        IsWindows          = $true
                        IsServerOS         = $false
                        FeatureInstalled   = $false
                        IsDomainController = $false
                        DomainMatches      = $false
                        CurrentDomainName  = ''
                    }) -DesiredParameters @{
                        DomainName            = 'corp.example'
                        NetBIOSName           = 'CORP'
                        DSRMPassword          = (ConvertTo-SecureString -String 'ComplexPass!1234' -AsPlainText -Force)
                        ForestFunctionalLevel = 'WinThreshold'
                        SiteName              = 'Default-First-Site-Name'
                        InstallDNS            = $true
                    } | Out-Null
                    throw 'Expected ADDS-Forest to refuse non-server Windows.'
                }
                catch {
                    $errorMessage = $_.Exception.Message
                }

                if ($errorMessage -notmatch 'non serveur') {
                    throw "Expected explicit non-server message, got: $errorMessage"
                }
            }

            It 'refuses protected system paths for FileServer-Share' {
                $roleDefinition = Import-OpsRoleDefinition -RoleId 'FileServer-Share' -Force
                $planFunctionName = [string]$roleDefinition.FunctionMap.Plan

                $errorMessage = $null
                try {
                    & $planFunctionName -Target $script:LocalTarget -CurrentState ([pscustomobject]@{
                        IsWindows        = $true
                        IsServerOS       = $true
                        DirectoryExists  = $false
                        NtfsFullMatches  = $false
                        NtfsReadMatches  = $false
                        ShareExists      = $false
                        SharePathMatches = $false
                        ShareFullMatches = $false
                        ShareReadMatches = $false
                    }) -DesiredParameters @{
                        ShareName            = 'ForbiddenShare'
                        Path                 = 'C:\Windows\Temp\ForbiddenShare'
                        FullAccessPrincipals = @('BUILTIN\Administrators')
                        ReadAccessPrincipals = @('BUILTIN\Users')
                    } | Out-Null
                    throw 'Expected FileServer-Share to refuse protected path.'
                }
                catch {
                    $errorMessage = $_.Exception.Message
                }

                if ($errorMessage -notmatch 'Chemin refusé') {
                    throw "Expected protected-path refusal message, got: $errorMessage"
                }
            }

            It 'refuses DHCP scope deployment when DHCP is not AD-authorized' {
                $roleDefinition = Import-OpsRoleDefinition -RoleId 'DHCP-Scope' -Force
                $planFunctionName = [string]$roleDefinition.FunctionMap.Plan

                $errorMessage = $null
                try {
                    & $planFunctionName -Target $script:LocalTarget -CurrentState ([pscustomobject]@{
                        IsWindows            = $true
                        IsServerOS           = $true
                        IsAuthorizedInAD     = $false
                        AuthorizationReason  = 'DHCP server not authorized in AD.'
                        DhcpFeatureInstalled = $false
                        ScopeExists          = $false
                        ScopeMatchesRange    = $false
                        ScopeMatchesMask     = $false
                        ScopeMatchesLease    = $false
                        RouterMatches        = $false
                        DnsMatches           = $false
                    }) -DesiredParameters @{
                        ScopeName          = 'Corp Clients'
                        StartRange         = '10.0.10.100'
                        EndRange           = '10.0.10.250'
                        SubnetMask         = '255.255.255.0'
                        Router             = '10.0.10.1'
                        DnsServers         = @('10.0.10.10')
                        LeaseDurationHours = 24
                    } | Out-Null
                    throw 'Expected DHCP-Scope to refuse non-authorized DHCP server.'
                }
                catch {
                    $errorMessage = $_.Exception.Message
                }

                if ($errorMessage -notmatch 'DHCP non autorisé') {
                    throw "Expected AD authorization refusal message, got: $errorMessage"
                }
            }
        }

        Context 'Verify phase' {
            It 'returns compliant = true for mocked compliant states' {
                $verifyCases = @(
                    @{
                        VerifyCommand = 'Test-ADDS-ForestApplied'
                        TestCommand   = 'Test-ADDS-ForestRole'
                        MockState     = [pscustomobject]@{ IsCompliant = $true; ExpectedDomainName = 'corp.example' }
                    }
                    @{
                        VerifyCommand = 'Test-ADDS-AdditionalDCApplied'
                        TestCommand   = 'Test-ADDS-AdditionalDCRole'
                        MockState     = [pscustomobject]@{ IsCompliant = $true; ExpectedDomainName = 'corp.example' }
                    }
                    @{
                        VerifyCommand = 'Test-DNS-PrimaryApplied'
                        TestCommand   = 'Test-DNS-PrimaryRole'
                        MockState     = [pscustomobject]@{ IsCompliant = $true; ExpectedZoneName = 'corp.example' }
                    }
                    @{
                        VerifyCommand = 'Test-DHCP-ScopeApplied'
                        TestCommand   = 'Test-DHCP-ScopeRole'
                        MockState     = [pscustomobject]@{ IsCompliant = $true; ExpectedScopeName = 'Corp Clients' }
                    }
                    @{
                        VerifyCommand = 'Test-FileServer-ShareApplied'
                        TestCommand   = 'Test-FileServer-ShareRole'
                        MockState     = [pscustomobject]@{ IsCompliant = $true; ExpectedShareName = 'OpsData' }
                    }
                    @{
                        VerifyCommand = 'Test-IIS-SiteBasicApplied'
                        TestCommand   = 'Test-IIS-SiteBasicRole'
                        MockState     = [pscustomobject]@{ IsCompliant = $true; ExpectedSiteName = 'OpsSite' }
                    }
                )

                foreach ($verifyCase in $verifyCases) {
                    $mockState = $verifyCase['MockState']
                    Mock -CommandName ([string]$verifyCase['TestCommand']) -MockWith {
                        return $mockState
                    }

                    $verifyResult = & ([string]$verifyCase['VerifyCommand']) -Target $script:LocalTarget -DesiredParameters @{} -CurrentState $null -ApplyResult $null
                    $verifyTable = ConvertTo-OpsPropertyTable -InputObject $verifyResult
                    if (-not [bool]$verifyTable['IsCompliant']) {
                        throw "Expected Verify to return IsCompliant=true for '$([string]$verifyCase['VerifyCommand'])'."
                    }
                }
            }
        }

        Context 'Supported OS and catalog' {
            It 'returns explicit french unsupported OS error for each Windows role on Linux target info' {
                Mock -CommandName Get-OpsTargetInfo -MockWith {
                    return [pscustomobject]@{
                        Family          = 'Linux'
                        Distribution    = 'Ubuntu2404'
                        RawDistribution = 'ubuntu 24.04'
                    }
                }

                foreach ($roleId in $script:WindowsRoleIds) {
                    $caughtMessage = $null
                    try {
                        Invoke-OpsDeploy -Role $roleId -Target $script:LocalTarget -NonInteractive -Confirm:$false | Out-Null
                        throw "Expected unsupported OS error for role '$roleId'."
                    }
                    catch {
                        $caughtMessage = $_.Exception.Message
                    }

                    if ($caughtMessage -notmatch 'ne supporte pas la cible') {
                        throw "Expected explicit unsupported OS message for role '$roleId', got: $caughtMessage"
                    }
                }
            }

            It "lists all six roles with Show-OpsRoleCatalog -Category 'Windows/*'" {
                $catalog = Show-OpsRoleCatalog -Category 'Windows/*' -Confirm:$false
                $catalogIds = @(
                    $catalog |
                        Where-Object {
                            $null -ne $_ -and
                            $_ -is [System.Management.Automation.PSObject] -and
                            $null -ne $_.PSObject.Properties['Id']
                        } |
                        ForEach-Object { [string]$_.Id }
                )

                foreach ($roleId in $script:WindowsRoleIds) {
                    if ($catalogIds -notcontains $roleId) {
                        throw "Expected role '$roleId' in Windows category catalog. Got: $($catalogIds -join ', ')"
                    }
                }
            }
        }

        Context 'Playbook mode' {
            BeforeEach {
                $script:PlaybookTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('OpsToutatisPlaybookMode-' + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $script:PlaybookTestRoot -Force | Out-Null
            }

            AfterEach {
                if (Test-Path -LiteralPath $script:PlaybookTestRoot) {
                    Remove-Item -LiteralPath $script:PlaybookTestRoot -Recurse -Force
                }
            }

            It 'builds complete WhatIf plans with Invoke-OpsDeploy -Playbook' {
                $inventoryPath = Join-Path -Path $script:PlaybookTestRoot -ChildPath 'inventory.playbook-mode.psd1'
                $inventoryContent = @"
@{
    Hosts = @(
        @{ Name='DC01'; Address='127.0.0.1'; Transport='Local'; OS='WindowsServer2022'; CredentialRef='corp-admin' }
        @{ Name='FS01'; Address='127.0.0.1'; Transport='Local'; OS='WindowsServer2022'; CredentialRef='corp-admin' }
    )
    Groups = @{ WindowsHosts = @('DC01','FS01') }
}
"@
                Set-Content -LiteralPath $inventoryPath -Value $inventoryContent -Encoding UTF8

                Mock -CommandName Get-OpsTargetInfo -MockWith {
                    return [pscustomobject]@{
                        Family          = 'Windows'
                        Distribution    = 'WindowsServer2022'
                        RawDistribution = 'Microsoft Windows Server 2022'
                    }
                }

                Mock -CommandName Test-ADDS-ForestRole -MockWith {
                    return [pscustomobject]@{
                        IsWindows          = $true
                        IsServerOS         = $true
                        FeatureInstalled   = $false
                        IsDomainController = $false
                        DomainMatches      = $false
                        CurrentDomainName  = ''
                        IsCompliant        = $false
                    }
                }

                Mock -CommandName Get-ADDS-ForestPlan -MockWith {
                    return [pscustomobject]@{
                        Summary = 'ADDS-Forest mock plan'
                        Actions = @(
                            [pscustomobject]@{ Type = 'InstallADDSForest'; Label = 'Mock'; Data = @{} }
                        )
                    }
                }

                Mock -CommandName Test-DNS-PrimaryRole -MockWith {
                    return [pscustomobject]@{
                        IsWindows           = $true
                        IsServerOS          = $true
                        DnsFeatureInstalled = $false
                        ZoneExists          = $false
                        ZoneIsDsIntegrated  = $false
                        IsCompliant         = $false
                    }
                }

                Mock -CommandName Get-DNS-PrimaryPlan -MockWith {
                    return [pscustomobject]@{
                        Summary = 'DNS mock plan'
                        Actions = @(
                            [pscustomobject]@{ Type = 'CreatePrimaryZone'; Label = 'Mock'; Data = @{} }
                        )
                    }
                }

                Mock -CommandName Test-FileServer-ShareRole -MockWith {
                    return [pscustomobject]@{
                        IsWindows        = $true
                        IsServerOS       = $true
                        DirectoryExists  = $false
                        NtfsFullMatches  = $false
                        NtfsReadMatches  = $false
                        ShareExists      = $false
                        SharePathMatches = $false
                        ShareFullMatches = $false
                        ShareReadMatches = $false
                        IsCompliant      = $false
                    }
                }

                Mock -CommandName Get-FileServer-SharePlan -MockWith {
                    return [pscustomobject]@{
                        Summary = 'FileShare mock plan'
                        Actions = @(
                            [pscustomobject]@{ Type = 'EnsureSmbShare'; Label = 'Mock'; Data = @{} }
                        )
                    }
                }

                $playbookPath = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath 'examples\playbook-baseline-ad.psd1'))
                $playbookResult = Invoke-OpsDeploy -Playbook $playbookPath -InventoryPath $inventoryPath -WhatIf -NonInteractive -PassThru -Confirm:$false

                $playbookTable = ConvertTo-OpsPropertyTable -InputObject $playbookResult
                if ([int]$playbookTable['RoleInvocationCount'] -ne 3) {
                    throw "Expected 3 role invocations from playbook, got $([int]$playbookTable['RoleInvocationCount'])."
                }

                foreach ($roleResult in @($playbookTable['Results'])) {
                    $roleResultTable = ConvertTo-OpsPropertyTable -InputObject $roleResult
                    if (-not [bool]$roleResultTable['WasWhatIf']) {
                        throw 'Expected every playbook role invocation to run in WhatIf mode.'
                    }

                    if (@($roleResultTable['PlanActions']).Count -eq 0) {
                        throw 'Expected non-empty plan actions for each role in playbook WhatIf mode.'
                    }
                }
            }
        }
    }
}
