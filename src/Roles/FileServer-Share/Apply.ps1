function Invoke-FileServer-ShareApply {
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

    foreach ($planAction in @($PlanActions)) {
        $actionTable = ConvertTo-OpsPropertyTable -InputObject $planAction
        if ($null -eq $actionTable) {
            throw 'Action FileServer-Share invalide. Type/Label requis.'
        }

        $actionType = [string]$actionTable['Type']
        $actionLabel = [string]$actionTable['Label']
        $actionData = ConvertTo-OpsPropertyTable -InputObject $actionTable['Data']
        if ($null -eq $actionData) {
            $actionData = @{}
        }

        Write-OpsTransportLog -Level Action -Message ("FileServer-Share action: type={0}; label={1}" -f $actionType, $actionLabel)

        switch ($actionType) {
            'EnsureDirectory' {
                $path = [string]$actionData['Path']
                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$Path
                    )

                    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
                        New-Item -ItemType Directory -Path $Path -Force | Out-Null
                    }
                } -ArgumentList @($path) | Out-Null
            }
            'SetNtfsAcl' {
                $path = [string]$actionData['Path']
                $fullAccessPrincipals = @($actionData['FullAccessPrincipals'])
                $readAccessPrincipals = @($actionData['ReadAccessPrincipals'])

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$Path,
                        [string[]]$FullAccessPrincipals,
                        [string[]]$ReadAccessPrincipals
                    )

                    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
                        New-Item -ItemType Directory -Path $Path -Force | Out-Null
                    }

                    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
                    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
                    $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None

                    foreach ($fullPrincipal in @($FullAccessPrincipals)) {
                        $hasRule = $false
                        foreach ($accessEntry in @($acl.Access)) {
                            if ([string]$accessEntry.IdentityReference -eq [string]$fullPrincipal -and
                                [string]$accessEntry.AccessControlType -eq 'Allow' -and
                                ([string]$accessEntry.FileSystemRights -match 'FullControl')) {
                                $hasRule = $true
                                break
                            }
                        }

                        if (-not $hasRule) {
                            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                                [string]$fullPrincipal,
                                [System.Security.AccessControl.FileSystemRights]::FullControl,
                                $inheritanceFlags,
                                $propagationFlags,
                                [System.Security.AccessControl.AccessControlType]::Allow
                            )
                            $null = $acl.AddAccessRule($rule)
                        }
                    }

                    foreach ($readPrincipal in @($ReadAccessPrincipals)) {
                        $hasRule = $false
                        foreach ($accessEntry in @($acl.Access)) {
                            if ([string]$accessEntry.IdentityReference -eq [string]$readPrincipal -and
                                [string]$accessEntry.AccessControlType -eq 'Allow' -and
                                (
                                    ([string]$accessEntry.FileSystemRights -match 'Read') -or
                                    ([string]$accessEntry.FileSystemRights -match 'FullControl')
                                )) {
                                $hasRule = $true
                                break
                            }
                        }

                        if (-not $hasRule) {
                            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                                [string]$readPrincipal,
                                [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                                $inheritanceFlags,
                                $propagationFlags,
                                [System.Security.AccessControl.AccessControlType]::Allow
                            )
                            $null = $acl.AddAccessRule($rule)
                        }
                    }

                    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
                } -ArgumentList @($path, @($fullAccessPrincipals), @($readAccessPrincipals)) | Out-Null
            }
            'EnsureSmbShare' {
                $shareName = [string]$actionData['ShareName']
                $path = [string]$actionData['Path']
                $fullAccessPrincipals = @($actionData['FullAccessPrincipals'])
                $readAccessPrincipals = @($actionData['ReadAccessPrincipals'])

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$ShareName,
                        [string]$Path,
                        [string[]]$FullAccessPrincipals,
                        [string[]]$ReadAccessPrincipals
                    )

                    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
                        New-Item -ItemType Directory -Path $Path -Force | Out-Null
                    }

                    $share = $null
                    try {
                        $share = Get-SmbShare -Name $ShareName -ErrorAction Stop
                    }
                    catch {
                        $share = $null
                    }

                    if ($null -eq $share) {
                        New-SmbShare -Name $ShareName -Path $Path -FullAccess @($FullAccessPrincipals) -ReadAccess @($ReadAccessPrincipals) -ErrorAction Stop | Out-Null
                    }
                    else {
                        if (-not ([string]$share.Path).Equals($Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                            Remove-SmbShare -Name $ShareName -Force -ErrorAction Stop | Out-Null
                            New-SmbShare -Name $ShareName -Path $Path -FullAccess @($FullAccessPrincipals) -ReadAccess @($ReadAccessPrincipals) -ErrorAction Stop | Out-Null
                        }
                    }
                } -ArgumentList @($shareName, $path, @($fullAccessPrincipals), @($readAccessPrincipals)) | Out-Null
            }
            'SetSmbSharePermissions' {
                $shareName = [string]$actionData['ShareName']
                $fullAccessPrincipals = @($actionData['FullAccessPrincipals'])
                $readAccessPrincipals = @($actionData['ReadAccessPrincipals'])

                Invoke-OpsRemote -Target $Target -ScriptBlock {
                    param(
                        [string]$ShareName,
                        [string[]]$FullAccessPrincipals,
                        [string[]]$ReadAccessPrincipals
                    )

                    foreach ($fullPrincipal in @($FullAccessPrincipals)) {
                        Grant-SmbShareAccess -Name $ShareName -AccountName $fullPrincipal -AccessRight Full -Force -ErrorAction Stop | Out-Null
                    }

                    foreach ($readPrincipal in @($ReadAccessPrincipals)) {
                        Grant-SmbShareAccess -Name $ShareName -AccountName $readPrincipal -AccessRight Read -Force -ErrorAction Stop | Out-Null
                    }
                } -ArgumentList @($shareName, @($fullAccessPrincipals), @($readAccessPrincipals)) | Out-Null
            }
            default {
                throw "Action FileServer-Share non supportée : '$actionType'."
            }
        }

        $appliedActions += [pscustomobject]@{
            Type  = $actionType
            Label = $actionLabel
        }
    }

    return [pscustomobject]@{
        AppliedActionCount = @($appliedActions).Count
        AppliedActions     = @($appliedActions)
    }
}
