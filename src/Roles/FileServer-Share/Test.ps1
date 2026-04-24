function Test-FileServer-ShareRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-FileServer-ShareEffectiveParameters -DesiredParameters $DesiredParameters
    $shareName = [string]$effectiveParameters['ShareName']
    $sharePath = [string]$effectiveParameters['Path']
    $fullAccessPrincipals = @($effectiveParameters['FullAccessPrincipals'])
    $readAccessPrincipals = @($effectiveParameters['ReadAccessPrincipals'])

    $remoteState = Invoke-OpsRemote -Target $Target -ScriptBlock {
        param(
            [string]$ShareName,
            [string]$SharePath,
            [string[]]$FullAccessPrincipals,
            [string[]]$ReadAccessPrincipals
        )

        $isWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
        $productType = 0
        $directoryExists = $false
        $shareExists = $false
        $sharePathMatches = $false
        $shareFullMatches = $false
        $shareReadMatches = $false
        $ntfsFullMatches = $false
        $ntfsReadMatches = $false
        $errors = @()

        if ($isWindows) {
            try {
                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $productType = [int]$osInfo.ProductType
            }
            catch {
                $errors += ('OS probe failed: {0}' -f $_.Exception.Message)
            }

            $directoryExists = Test-Path -LiteralPath $SharePath -PathType Container

            $share = $null
            try {
                $share = Get-SmbShare -Name $ShareName -ErrorAction Stop
            }
            catch {
                $share = $null
            }

            if ($null -ne $share) {
                $shareExists = $true
                if ($share.PSObject.Properties['Path']) {
                    $sharePathMatches = ([string]$share.Path).Equals($SharePath, [System.StringComparison]::OrdinalIgnoreCase)
                }

                try {
                    $shareAccessEntries = @(Get-SmbShareAccess -Name $ShareName -ErrorAction Stop)
                    $shareFullSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $shareReadSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                    foreach ($shareAccessEntry in $shareAccessEntries) {
                        $accountName = [string]$shareAccessEntry.AccountName
                        $accessRight = [string]$shareAccessEntry.AccessRight
                        if ($accessRight -eq 'Full') {
                            [void]$shareFullSet.Add($accountName)
                            [void]$shareReadSet.Add($accountName)
                        }
                        elseif ($accessRight -eq 'Read' -or $accessRight -eq 'Change') {
                            [void]$shareReadSet.Add($accountName)
                        }
                    }

                    $shareFullMatches = $true
                    foreach ($expectedFullPrincipal in @($FullAccessPrincipals)) {
                        if (-not $shareFullSet.Contains([string]$expectedFullPrincipal)) {
                            $shareFullMatches = $false
                            break
                        }
                    }

                    $shareReadMatches = $true
                    foreach ($expectedReadPrincipal in @($ReadAccessPrincipals)) {
                        if (-not $shareReadSet.Contains([string]$expectedReadPrincipal)) {
                            $shareReadMatches = $false
                            break
                        }
                    }
                }
                catch {
                    $errors += ('Share permission probe failed: {0}' -f $_.Exception.Message)
                }
            }

            if ($directoryExists) {
                try {
                    $acl = Get-Acl -LiteralPath $SharePath -ErrorAction Stop
                    $ntfsFullMatches = $true
                    foreach ($expectedFullPrincipal in @($FullAccessPrincipals)) {
                        $principalHasFull = $false
                        foreach ($accessEntry in @($acl.Access)) {
                            if ([string]$accessEntry.IdentityReference -eq [string]$expectedFullPrincipal -and
                                [string]$accessEntry.AccessControlType -eq 'Allow' -and
                                ([string]$accessEntry.FileSystemRights -match 'FullControl')) {
                                $principalHasFull = $true
                                break
                            }
                        }

                        if (-not $principalHasFull) {
                            $ntfsFullMatches = $false
                            break
                        }
                    }

                    $ntfsReadMatches = $true
                    foreach ($expectedReadPrincipal in @($ReadAccessPrincipals)) {
                        $principalHasRead = $false
                        foreach ($accessEntry in @($acl.Access)) {
                            if ([string]$accessEntry.IdentityReference -eq [string]$expectedReadPrincipal -and
                                [string]$accessEntry.AccessControlType -eq 'Allow' -and
                                (
                                    ([string]$accessEntry.FileSystemRights -match 'Read') -or
                                    ([string]$accessEntry.FileSystemRights -match 'FullControl')
                                )) {
                                $principalHasRead = $true
                                break
                            }
                        }

                        if (-not $principalHasRead) {
                            $ntfsReadMatches = $false
                            break
                        }
                    }
                }
                catch {
                    $errors += ('NTFS ACL probe failed: {0}' -f $_.Exception.Message)
                }
            }
        }

        return [pscustomobject]@{
            IsWindows        = [bool]$isWindows
            ProductType      = [int]$productType
            IsServerOS       = ([bool]$isWindows -and [int]$productType -ne 1)
            DirectoryExists  = [bool]$directoryExists
            ShareExists      = [bool]$shareExists
            SharePathMatches = [bool]$sharePathMatches
            ShareFullMatches = [bool]$shareFullMatches
            ShareReadMatches = [bool]$shareReadMatches
            NtfsFullMatches  = [bool]$ntfsFullMatches
            NtfsReadMatches  = [bool]$ntfsReadMatches
            Errors           = @($errors)
        }
    } -ArgumentList @($shareName, $sharePath, @($fullAccessPrincipals), @($readAccessPrincipals))

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $remoteState

    $isCompliant = (
        [bool]$stateTable['DirectoryExists'] -and
        [bool]$stateTable['ShareExists'] -and
        [bool]$stateTable['SharePathMatches'] -and
        [bool]$stateTable['ShareFullMatches'] -and
        [bool]$stateTable['ShareReadMatches'] -and
        [bool]$stateTable['NtfsFullMatches'] -and
        [bool]$stateTable['NtfsReadMatches']
    )

    return [pscustomobject]@{
        IsCompliant            = $isCompliant
        IsWindows              = [bool]$stateTable['IsWindows']
        IsServerOS             = [bool]$stateTable['IsServerOS']
        DirectoryExists        = [bool]$stateTable['DirectoryExists']
        ShareExists            = [bool]$stateTable['ShareExists']
        SharePathMatches       = [bool]$stateTable['SharePathMatches']
        ShareFullMatches       = [bool]$stateTable['ShareFullMatches']
        ShareReadMatches       = [bool]$stateTable['ShareReadMatches']
        NtfsFullMatches        = [bool]$stateTable['NtfsFullMatches']
        NtfsReadMatches        = [bool]$stateTable['NtfsReadMatches']
        ExpectedShareName      = $shareName
        ExpectedPath           = $sharePath
        ExpectedFullPrincipals = @($fullAccessPrincipals)
        ExpectedReadPrincipals = @($readAccessPrincipals)
        Errors                 = @($stateTable['Errors'])
    }
}
