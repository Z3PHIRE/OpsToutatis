function Get-OpsTargetInfo {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSec = 120
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $transportName = Get-OpsTransportName -TargetTable $targetTable
    $address = Get-OpsTransportAddress -TargetTable $targetTable
    $targetName = $address
    if ($targetTable.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$targetTable['Name'])) {
        $targetName = [string]$targetTable['Name']
    }

    if (-not $PSCmdlet.ShouldProcess($targetName, 'Collecter les informations système de la cible')) {
        return $null
    }

    $remoteProbeScript = {
        $opsIsWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
        $hostName = [System.Net.Dns]::GetHostName()
        $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()

        if ($opsIsWindows) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $payload = [pscustomobject]@{
                Family           = 'Windows'
                DistributionRaw  = [string]$os.Caption
                Version          = [string]$os.Version
                ArchitectureRaw  = [string]$architecture
                HostName         = [string]$hostName
                OsReleaseId      = ''
                OsReleaseVersion = ''
            }

            return (@($payload) | ConvertTo-Json -Compress)
        }

        $releaseId = ''
        $releaseVersion = ''
        if (Test-Path -LiteralPath '/etc/os-release') {
            foreach ($line in @(Get-Content -LiteralPath '/etc/os-release')) {
                if ($line -match '^\s*ID\s*=\s*(.+)\s*$') {
                    $releaseId = $matches[1].Trim().Trim('"').Trim("'")
                    continue
                }

                if ($line -match '^\s*VERSION_ID\s*=\s*(.+)\s*$') {
                    $releaseVersion = $matches[1].Trim().Trim('"').Trim("'")
                    continue
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($releaseId)) {
            $releaseId = 'linux'
        }

        $distributionRaw = $releaseId
        if (-not [string]::IsNullOrWhiteSpace($releaseVersion)) {
            $distributionRaw = '{0} {1}' -f $releaseId, $releaseVersion
        }

        $kernelVersion = [System.Environment]::OSVersion.Version.ToString()
        $effectiveVersion = $releaseVersion
        if ([string]::IsNullOrWhiteSpace($effectiveVersion)) {
            $effectiveVersion = $kernelVersion
        }

        $linuxPayload = [pscustomobject]@{
            Family           = 'Linux'
            DistributionRaw  = $distributionRaw
            Version          = $effectiveVersion
            ArchitectureRaw  = [string]$architecture
            HostName         = [string]$hostName
            OsReleaseId      = [string]$releaseId
            OsReleaseVersion = [string]$releaseVersion
        }

        return (@($linuxPayload) | ConvertTo-Json -Compress)
    }

    Write-OpsTransportLog -Level Action -Message ("Target info collection started for '{0}' via {1}." -f $targetName, $transportName)

    try {
        $probeResult = Invoke-OpsRemote -Target $targetTable -ScriptBlock $remoteProbeScript -TimeoutSec $TimeoutSec
        $probeLines = @()
        foreach ($probeLine in @($probeResult)) {
            $probeLines += [string]$probeLine
        }

        $jsonPayload = $null
        for ($lineIndex = @($probeLines).Count - 1; $lineIndex -ge 0; $lineIndex--) {
            $candidateLine = $probeLines[$lineIndex].Trim()
            if ($candidateLine.StartsWith('{') -and $candidateLine.EndsWith('}')) {
                $jsonPayload = $candidateLine
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($jsonPayload)) {
            $singlePayload = (@($probeLines) -join '').Trim()
            if ($singlePayload.StartsWith('{') -and $singlePayload.EndsWith('}')) {
                $jsonPayload = $singlePayload
            }
        }

        if ([string]::IsNullOrWhiteSpace($jsonPayload)) {
            throw "Réponse distante non JSON. Détail brut : $(@($probeLines) -join ' | ')"
        }

        $rawInfo = ConvertFrom-Json -InputObject $jsonPayload -ErrorAction Stop

        $family = [string]$rawInfo.Family
        if ([string]::IsNullOrWhiteSpace($family)) {
            throw 'Famille OS vide dans la réponse distante.'
        }

        $normalizedDistribution = 'Unknown'
        $distributionRaw = [string]$rawInfo.DistributionRaw
        if ($family -eq 'Windows') {
            if ($distributionRaw -match '2025') {
                $normalizedDistribution = 'WindowsServer2025'
            }
            elseif ($distributionRaw -match '2022') {
                $normalizedDistribution = 'WindowsServer2022'
            }
            elseif ($distributionRaw -match '2019') {
                $normalizedDistribution = 'WindowsServer2019'
            }
            else {
                $normalizedDistribution = 'Windows'
            }
        }
        else {
            $releaseId = ([string]$rawInfo.OsReleaseId).ToLowerInvariant()
            $releaseVersion = [string]$rawInfo.OsReleaseVersion
            if ($releaseId -eq 'ubuntu') {
                if ($releaseVersion.StartsWith('24.04')) {
                    $normalizedDistribution = 'Ubuntu2404'
                }
                elseif ($releaseVersion.StartsWith('22.04')) {
                    $normalizedDistribution = 'Ubuntu2204'
                }
                else {
                    $normalizedDistribution = 'Ubuntu'
                }
            }
            elseif ($releaseId -eq 'debian') {
                if ($releaseVersion.StartsWith('12')) {
                    $normalizedDistribution = 'Debian12'
                }
                else {
                    $normalizedDistribution = 'Debian'
                }
            }
            elseif ($releaseId -eq 'rhel' -or $releaseId -eq 'redhat' -or $releaseId -eq 'rocky' -or $releaseId -eq 'almalinux') {
                if ($releaseVersion.StartsWith('9')) {
                    $normalizedDistribution = 'RHEL9'
                }
                else {
                    $normalizedDistribution = 'RHEL'
                }
            }
            else {
                $normalizedDistribution = $distributionRaw
                if ([string]::IsNullOrWhiteSpace($normalizedDistribution)) {
                    $normalizedDistribution = 'Linux'
                }
            }
        }

        $architectureRaw = [string]$rawInfo.ArchitectureRaw
        $normalizedArchitecture = 'unknown'
        switch -Regex ($architectureRaw.ToLowerInvariant()) {
            '^(x64|amd64|x86_64)$' {
                $normalizedArchitecture = 'x64'
            }
            '^(x86|i386|i686)$' {
                $normalizedArchitecture = 'x86'
            }
            '^(arm64|aarch64)$' {
                $normalizedArchitecture = 'arm64'
            }
            default {
                if (-not [string]::IsNullOrWhiteSpace($architectureRaw)) {
                    $normalizedArchitecture = $architectureRaw
                }
            }
        }

        $normalizedVersion = [string]$rawInfo.Version
        if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
            $normalizedVersion = 'unknown'
        }

        $result = [pscustomobject]@{
            TargetName       = $targetName
            Address          = $address
            Transport        = $transportName
            Family           = [string]$family
            Distribution     = $normalizedDistribution
            Version          = $normalizedVersion
            Architecture     = $normalizedArchitecture
            HostName         = [string]$rawInfo.HostName
            RawDistribution  = $distributionRaw
            CollectedAtUtc   = (Get-Date).ToUniversalTime()
        }

        Write-OpsTransportLog -Level Decision -Message ("Target info collection succeeded for '{0}'." -f $targetName)
        return $result
    }
    catch {
        $errorMessage = "Impossible de collecter les informations de la cible '$targetName'. Cause probable : connexion distante incomplète ou shell non compatible. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
}
