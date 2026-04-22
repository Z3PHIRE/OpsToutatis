function Test-OpsSshRemotingSupport {
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        return $false
    }

    $newPSSessionCommand = Get-Command -Name New-PSSession -ErrorAction SilentlyContinue
    if ($null -eq $newPSSessionCommand) {
        return $false
    }

    if (-not $newPSSessionCommand.Parameters.ContainsKey('HostName')) {
        return $false
    }

    return $true
}

function Get-OpsSshToolPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ssh', 'scp')]
        [string]$ToolName
    )

    $opsRunningOnWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
    $candidates = @()
    if ($opsRunningOnWindows) {
        $candidates += ('{0}.exe' -f $ToolName)
    }

    $candidates += $ToolName

    foreach ($candidate in $candidates) {
        $commandInfo = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -ne $commandInfo) {
            return $commandInfo.Source
        }
    }

    throw "Outil '$ToolName' introuvable. Correction attendue : installez OpenSSH client et vérifiez PATH."
}

function Get-OpsSshConnectionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable,

        [Parameter()]
        [AllowNull()]
        [pscredential]$Credential
    )

    $address = Get-OpsTransportAddress -TargetTable $TargetTable
    $userName = Get-OpsTransportOptionalUserName -TargetTable $TargetTable -Credential $Credential
    if ([string]::IsNullOrWhiteSpace($userName)) {
        throw "Nom d'utilisateur SSH manquant pour '$address'. Correction attendue : renseignez UserName dans l'inventaire ou dans le secret."
    }

    $port = Get-OpsTransportPort -TargetTable $TargetTable
    $keyPath = Get-OpsSshKeyPath -TargetTable $TargetTable
    $sshEndpoint = '{0}@{1}' -f $userName, $address

    $sshArguments = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=10',
        '-p', [string]$port
    )

    $scpArguments = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=10',
        '-P', [string]$port
    )

    if (-not [string]::IsNullOrWhiteSpace($keyPath)) {
        $sshArguments += @('-i', $keyPath)
        $scpArguments += @('-i', $keyPath)
    }

    return [pscustomobject]@{
        Address      = $address
        UserName     = $userName
        Port         = $port
        KeyPath      = $keyPath
        Endpoint     = $sshEndpoint
        SshArguments = @($sshArguments)
        ScpArguments = @($scpArguments)
    }
}

function ConvertTo-OpsSshEncodedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object[]]$ArgumentList = @()
    )

    $scriptText = $ScriptBlock.ToString()
    $scriptPayload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptText))
    $serializedArguments = [System.Management.Automation.PSSerializer]::Serialize(@($ArgumentList))
    $argumentPayload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($serializedArguments))

    $remoteLines = @(
        '$ErrorActionPreference = ''Stop'''
        ('$scriptPayload = ''{0}''' -f $scriptPayload)
        ('$argumentPayload = ''{0}''' -f $argumentPayload)
        '$scriptText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($scriptPayload))'
        '$argumentXml = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($argumentPayload))'
        '$argumentList = [System.Management.Automation.PSSerializer]::Deserialize($argumentXml)'
        'if ($null -eq $argumentList) { $argumentList = @() }'
        'elseif ($argumentList -is [string] -or -not ($argumentList -is [System.Collections.IEnumerable])) { $argumentList = @($argumentList) }'
        '$scriptBlock = [scriptblock]::Create($scriptText)'
        '& $scriptBlock @($argumentList)'
    )

    $remoteScript = [string]::Join('; ', $remoteLines)
    return [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($remoteScript))
}

function Invoke-SSHCommand {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object[]]$ArgumentList = @(),

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSec = 120
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $effectiveTimeoutSec = Get-OpsTransportTimeoutSec -TargetTable $targetTable -Kind 'Command' -DefaultValue $TimeoutSec
    $credential = Resolve-OpsTransportCredential -TargetTable $targetTable -TransportName 'SSH' -Mandatory:$false
    $state = Get-OpsSshConnectionState -TargetTable $targetTable -Credential $credential

    if (-not $PSCmdlet.ShouldProcess($state.Endpoint, 'Exécuter une commande SSH')) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("SSH command execution started on '{0}'." -f $state.Endpoint)

    if (Test-OpsSshRemotingSupport) {
        $session = $null
        try {
            $newSessionParameters = @{
                HostName    = $state.Address
                UserName    = $state.UserName
                Port        = $state.Port
                ErrorAction = 'Stop'
            }

            if (-not [string]::IsNullOrWhiteSpace($state.KeyPath)) {
                $newSessionParameters['KeyFilePath'] = $state.KeyPath
            }

            $session = New-PSSession @newSessionParameters
            $result = Invoke-Command -Session $session -ScriptBlock $ScriptBlock -ArgumentList @($ArgumentList) -ErrorAction Stop
            Write-OpsTransportLog -Level Decision -Message ("SSH command execution completed on '{0}' (PSSession)." -f $state.Endpoint)
            return $result
        }
        catch {
            $rawError = $_.Exception.Message
            $errorMessage = "Échec d'exécution SSH vers '$($state.Endpoint)' via PSSession. Cause probable : authentification SSH invalide ou clé absente. Détail : $rawError"
            Write-OpsTransportLog -Level Error -Message $errorMessage
            throw $errorMessage
        }
        finally {
            if ($null -ne $session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $sshToolPath = Get-OpsSshToolPath -ToolName 'ssh'
        $encodedCommand = ConvertTo-OpsSshEncodedCommand -ScriptBlock $ScriptBlock -ArgumentList @($ArgumentList)
        $remoteCommand = 'pwsh -NoLogo -NoProfile -EncodedCommand {0}' -f $encodedCommand
        $sshArguments = @($state.SshArguments + @($state.Endpoint, $remoteCommand))
        $nativeResult = Invoke-OpsNativeCommand -ExecutablePath $sshToolPath -ArgumentList $sshArguments -TimeoutSec $effectiveTimeoutSec

        Write-OpsTransportLog -Level Decision -Message ("SSH command execution completed on '{0}' (ssh.exe fallback)." -f $state.Endpoint)

        $outputLines = @($nativeResult.Output)
        if (@($outputLines).Count -eq 1) {
            return [string]$outputLines[0]
        }

        return @($outputLines)
    }
    catch {
        $rawError = $_.Exception.Message
        $guidance = 'Vérifiez la route réseau, la clé SSH et la présence de pwsh sur la cible.'
        if ($rawError -match 'Permission denied') {
            $guidance = 'Authentification SSH refusée. Correction attendue : vérifiez UserName, clé privée ou agent SSH.'
        }
        elseif ($rawError -match 'Connection refused') {
            $guidance = 'Port 22 fermé. Correction attendue : activez SSH côté cible.'
        }
        elseif ($rawError -match 'Could not resolve hostname') {
            $guidance = 'Nom d''hôte non résolu. Correction attendue : vérifiez Address dans l''inventaire.'
        }
        elseif ($rawError -match 'pwsh: command not found|pwsh n''est pas reconnu') {
            $guidance = 'pwsh absent sur la cible SSH. Correction attendue : installez PowerShell 7+ côté cible.'
        }

        $errorMessage = "Échec d'exécution SSH vers '$($state.Endpoint)'. Cause probable : $guidance Détail technique : $rawError"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
}

function Send-SSHFile {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RemotePath
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $effectiveTimeoutSec = Get-OpsTransportTimeoutSec -TargetTable $targetTable -Kind 'Transfer' -DefaultValue 600
    $resolvedLocalPath = [System.IO.Path]::GetFullPath($LocalPath)
    if (-not (Test-Path -LiteralPath $resolvedLocalPath)) {
        throw "Le fichier local '$resolvedLocalPath' est introuvable. Correction attendue : vérifiez le chemin source."
    }

    $credential = Resolve-OpsTransportCredential -TargetTable $targetTable -TransportName 'SSH' -Mandatory:$false
    $state = Get-OpsSshConnectionState -TargetTable $targetTable -Credential $credential
    if (-not $PSCmdlet.ShouldProcess($state.Endpoint, "Transférer un fichier vers '$RemotePath' via SSH")) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("SSH upload started: {0} -> {1}:{2}" -f $resolvedLocalPath, $state.Endpoint, $RemotePath)

    try {
        $scpToolPath = Get-OpsSshToolPath -ToolName 'scp'
        $remoteSpec = '{0}:{1}' -f $state.Endpoint, $RemotePath
        $scpArguments = @($state.ScpArguments + @($resolvedLocalPath, $remoteSpec))
        Invoke-OpsNativeCommand -ExecutablePath $scpToolPath -ArgumentList $scpArguments -TimeoutSec $effectiveTimeoutSec | Out-Null

        Write-OpsTransportLog -Level Decision -Message ("SSH upload completed: {0}" -f $resolvedLocalPath)
        return [pscustomobject]@{
            LocalPath  = $resolvedLocalPath
            RemotePath = $RemotePath
            Target     = $state.Endpoint
        }
    }
    catch {
        $errorMessage = "Échec du transfert SSH vers '$($state.Endpoint)'. Cause probable : permissions distantes insuffisantes ou chemin distant invalide. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
}

function Receive-SSHFile {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RemotePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalPath
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $effectiveTimeoutSec = Get-OpsTransportTimeoutSec -TargetTable $targetTable -Kind 'Transfer' -DefaultValue 600
    $resolvedLocalPath = [System.IO.Path]::GetFullPath($LocalPath)
    $destinationDirectory = Split-Path -Path $resolvedLocalPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    $credential = Resolve-OpsTransportCredential -TargetTable $targetTable -TransportName 'SSH' -Mandatory:$false
    $state = Get-OpsSshConnectionState -TargetTable $targetTable -Credential $credential
    if (-not $PSCmdlet.ShouldProcess($state.Endpoint, "Récupérer un fichier '$RemotePath' via SSH")) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("SSH download started: {0}:{1} -> {2}" -f $state.Endpoint, $RemotePath, $resolvedLocalPath)

    try {
        $scpToolPath = Get-OpsSshToolPath -ToolName 'scp'
        $remoteSpec = '{0}:{1}' -f $state.Endpoint, $RemotePath
        $scpArguments = @($state.ScpArguments + @($remoteSpec, $resolvedLocalPath))
        Invoke-OpsNativeCommand -ExecutablePath $scpToolPath -ArgumentList $scpArguments -TimeoutSec $effectiveTimeoutSec | Out-Null

        Write-OpsTransportLog -Level Decision -Message ("SSH download completed: {0}" -f $resolvedLocalPath)
        return [pscustomobject]@{
            RemotePath = $RemotePath
            LocalPath  = $resolvedLocalPath
            Target     = $state.Endpoint
        }
    }
    catch {
        $errorMessage = "Échec de la récupération SSH depuis '$($state.Endpoint)'. Cause probable : fichier distant introuvable ou permissions insuffisantes. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
}

function Test-SSHConnection {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $credential = Resolve-OpsTransportCredential -TargetTable $targetTable -TransportName 'SSH' -Mandatory:$false
    $state = Get-OpsSshConnectionState -TargetTable $targetTable -Credential $credential
    if (-not $PSCmdlet.ShouldProcess($state.Endpoint, 'Tester la connexion SSH')) {
        return [pscustomobject]@{
            Success = $false
            Message = 'Test de connexion SSH ignoré (WhatIf/Confirm).'
        }
    }

    if (Test-OpsSshRemotingSupport) {
        $session = $null
        try {
            $newSessionParameters = @{
                HostName    = $state.Address
                UserName    = $state.UserName
                Port        = $state.Port
                ErrorAction = 'Stop'
            }

            if (-not [string]::IsNullOrWhiteSpace($state.KeyPath)) {
                $newSessionParameters['KeyFilePath'] = $state.KeyPath
            }

            $session = New-PSSession @newSessionParameters
            $probe = Invoke-Command -Session $session -ScriptBlock { [System.Net.Dns]::GetHostName() } -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace((@($probe) -join ''))) {
                return [pscustomobject]@{
                    Success = $false
                    Message = "Connexion SSH établie vers '$($state.Endpoint)' mais réponse inattendue."
                }
            }

            return [pscustomobject]@{
                Success = $true
                Message = "Connexion SSH authentifiée vers '$($state.Endpoint)'."
            }
        }
        catch {
            return [pscustomobject]@{
                Success = $false
                Message = "Connexion SSH impossible vers '$($state.Endpoint)'. Détail : $($_.Exception.Message)"
            }
        }
        finally {
            if ($null -ne $session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $sshToolPath = Get-OpsSshToolPath -ToolName 'ssh'
        $probeCommand = 'pwsh -NoLogo -NoProfile -Command "$PSVersionTable.PSEdition"'
        $sshArguments = @($state.SshArguments + @($state.Endpoint, $probeCommand))
        $probeResult = Invoke-OpsNativeCommand -ExecutablePath $sshToolPath -ArgumentList $sshArguments -TimeoutSec 30
        $probeText = @($probeResult.Output) -join ' '
        if ($probeText -notmatch 'Core') {
            return [pscustomobject]@{
                Success = $false
                Message = "SSH accessible vers '$($state.Endpoint)', mais pwsh n'a pas répondu correctement."
            }
        }

        return [pscustomobject]@{
            Success = $true
            Message = "Connexion SSH authentifiée vers '$($state.Endpoint)' avec pwsh disponible."
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Message = "Connexion SSH impossible vers '$($state.Endpoint)'. Détail : $($_.Exception.Message)"
        }
    }
}
