Set-StrictMode -Version Latest
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'OpsToutatis transport layer' {
    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    InModuleScope OpsToutatis {
        $script:TransportTestRoot = $null

        BeforeEach {
            $script:TransportTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('OpsToutatisTransportTests-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TransportTestRoot -Force | Out-Null
        }

        AfterEach {
            if (-not [string]::IsNullOrWhiteSpace($script:TransportTestRoot) -and (Test-Path -LiteralPath $script:TransportTestRoot)) {
                Remove-Item -LiteralPath $script:TransportTestRoot -Recurse -Force
            }
        }

        It 'executes local command through LocalTransport' {
            $target = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }

            $result = Invoke-LocalCommand -Target $target -ScriptBlock { param($Left, $Right) $Left + $Right } -ArgumentList @(2, 3) -TimeoutSec 30
            if ([int]@($result)[0] -ne 5) {
                throw "Expected local command result 5, got '$result'."
            }
        }

        It 'copies files with LocalTransport send and receive operations' {
            $target = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }

            $sourcePath = Join-Path -Path $script:TransportTestRoot -ChildPath 'source.txt'
            $middlePath = Join-Path -Path $script:TransportTestRoot -ChildPath 'middle.txt'
            $destinationPath = Join-Path -Path $script:TransportTestRoot -ChildPath 'destination.txt'

            Set-Content -LiteralPath $sourcePath -Value 'ops-transport-local' -Encoding UTF8
            Send-LocalFile -Target $target -LocalPath $sourcePath -RemotePath $middlePath | Out-Null
            Receive-LocalFile -Target $target -RemotePath $middlePath -LocalPath $destinationPath | Out-Null

            if (-not (Test-Path -LiteralPath $destinationPath)) {
                throw "Expected downloaded file '$destinationPath' to exist."
            }

            $finalContent = Get-Content -LiteralPath $destinationPath -Raw
            if ($finalContent -notmatch 'ops-transport-local') {
                throw "Unexpected downloaded content: '$finalContent'."
            }
        }

        It 'dispatches WinRM through Invoke-OpsRemote facade' {
            Mock -CommandName Invoke-WinRMCommand -MockWith {
                return 'WINRM_OK'
            } -Verifiable

            $target = @{
                Name          = 'DC01'
                Address       = '192.0.2.10'
                Transport     = 'WinRM'
                CredentialRef = 'corp-admin'
            }

            $result = Invoke-OpsRemote -Target $target -ScriptBlock { hostname } -TimeoutSec 15
            if ([string]$result -ne 'WINRM_OK') {
                throw "Expected WINRM_OK, got '$result'."
            }

            Assert-MockCalled -CommandName Invoke-WinRMCommand -Times 1 -Exactly
        }

        It 'dispatches SSH through Invoke-OpsRemote facade' {
            Mock -CommandName Invoke-SSHCommand -MockWith {
                return 'SSH_OK'
            } -Verifiable

            $target = @{
                Name          = 'WEB01'
                Address       = '192.0.2.20'
                Transport     = 'SSH'
                CredentialRef = 'web-root'
                UserName      = 'root'
            }

            $result = Invoke-OpsRemote -Target $target -ScriptBlock { hostname } -TimeoutSec 15
            if ([string]$result -ne 'SSH_OK') {
                throw "Expected SSH_OK, got '$result'."
            }

            Assert-MockCalled -CommandName Invoke-SSHCommand -Times 1 -Exactly
        }

        It 'returns normalized target info fields for Local transport' {
            $target = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }

            $info = Get-OpsTargetInfo -Target $target -TimeoutSec 60
            if ($null -eq $info) {
                throw 'Expected target info object but got null.'
            }

            $expectedProperties = @(
                'TargetName',
                'Address',
                'Transport',
                'Family',
                'Distribution',
                'Version',
                'Architecture',
                'HostName',
                'RawDistribution',
                'CollectedAtUtc'
            )

            foreach ($expectedProperty in $expectedProperties) {
                if (-not $info.PSObject.Properties.Name.Contains($expectedProperty)) {
                    throw "Missing expected property '$expectedProperty' in Get-OpsTargetInfo result."
                }
            }
        }

        It 'passes all five preflight checks on localhost Local transport' {
            $target = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }

            $result = Test-OpsTarget -Target $target -TimeoutSec 60
            if ($null -eq $result) {
                throw 'Expected Test-OpsTarget result but got null.'
            }

            $expectedProperties = @(
                'TargetName',
                'Address',
                'Transport',
                'Success',
                'Family',
                'Distribution',
                'Version',
                'Architecture',
                'HostName',
                'IsElevated',
                'SystemFreeBytes',
                'PreflightChecks',
                'TestedAtUtc'
            )

            foreach ($expectedProperty in $expectedProperties) {
                if (-not $result.PSObject.Properties.Name.Contains($expectedProperty)) {
                    throw "Missing expected property '$expectedProperty' in Test-OpsTarget result."
                }
            }

            if (@($result.PreflightChecks).Count -ne 5) {
                throw "Expected exactly 5 preflight checks, got $(@($result.PreflightChecks).Count)."
            }

            $failedChecks = @($result.PreflightChecks | Where-Object { -not $_.Success })
            if (@($failedChecks).Count -gt 0) {
                $failedSummary = @($failedChecks | ForEach-Object { "[$($_.StepNumber)] $($_.StepName): $($_.Message)" }) -join '; '
                throw "Expected all preflight checks to pass on Local transport. Failures: $failedSummary"
            }

            if (-not [bool]$result.Success) {
                throw 'Expected overall Success to be true for Local preflight.'
            }
        }
    }
}
