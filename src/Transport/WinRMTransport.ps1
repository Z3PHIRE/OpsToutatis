function Get-OpsWinRMAuthentication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable
    )

    if (-not $TargetTable.ContainsKey('Authentication')) {
        return 'Default'
    }

    $authentication = [string]$TargetTable['Authentication']
    if ([string]::IsNullOrWhiteSpace($authentication)) {
        return 'Default'
    }

    switch -Regex ($authentication.ToLowerInvariant()) {
        '^default$' {
            return 'Default'
        }
        '^credssp$' {
            return 'Credssp'
        }
        '^kerberos$' {
            return 'Kerberos'
        }
        '^ntlm$' {
            return 'Negotiate'
        }
        '^negotiate$' {
            return 'Negotiate'
        }
        '^basic$' {
            return 'Basic'
        }
        default {
            throw "Authentification WinRM non supportée '$authentication'. Correction attendue : utilisez Default, Kerberos, NTLM, CredSSP, Negotiate ou Basic."
        }
    }
}

function New-OpsWinRMSessionOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSec
    )

    if ($null -eq (Get-Command -Name New-PSSessionOption -ErrorAction SilentlyContinue)) {
        return $null
    }

    $timeoutMilliseconds = [int]([Math]::Min([int64]2147483647, [int64]$TimeoutSec * 1000))
    try {
        return New-PSSessionOption -OpenTimeout $timeoutMilliseconds -OperationTimeout $timeoutMilliseconds -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function New-OpsWinRMSessionInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSec
    )

    $address = Get-OpsTransportAddress -TargetTable $TargetTable
    $credential = Resolve-OpsTransportCredential -TargetTable $TargetTable -TransportName 'WinRM' -Mandatory:$true
    $authentication = Get-OpsWinRMAuthentication -TargetTable $TargetTable
    $port = Get-OpsTransportPort -TargetTable $TargetTable
    $useSsl = Get-OpsTransportBooleanValue -TargetTable $TargetTable -Key 'UseSsl' -DefaultValue:($port -eq 5986)
    $sessionOption = New-OpsWinRMSessionOption -TimeoutSec $TimeoutSec

    $newSessionParameters = @{
        ComputerName   = $address
        Authentication = $authentication
        Credential     = $credential
        Port           = $port
        ErrorAction    = 'Stop'
    }

    if ($useSsl) {
        $newSessionParameters['UseSSL'] = $true
    }

    if ($null -ne $sessionOption) {
        $newSessionParameters['SessionOption'] = $sessionOption
    }

    return New-PSSession @newSessionParameters
}

function Invoke-WinRMCommand {
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
    $address = Get-OpsTransportAddress -TargetTable $targetTable
    $effectiveTimeoutSec = Get-OpsTransportTimeoutSec -TargetTable $targetTable -Kind 'Command' -DefaultValue $TimeoutSec
    $authentication = Get-OpsWinRMAuthentication -TargetTable $targetTable
    $credential = Resolve-OpsTransportCredential -TargetTable $targetTable -TransportName 'WinRM' -Mandatory:$true
    $port = Get-OpsTransportPort -TargetTable $targetTable
    $useSsl = Get-OpsTransportBooleanValue -TargetTable $targetTable -Key 'UseSsl' -DefaultValue:($port -eq 5986)
    $sessionOption = New-OpsWinRMSessionOption -TimeoutSec $effectiveTimeoutSec

    if (-not $PSCmdlet.ShouldProcess($address, 'Exécuter une commande WinRM')) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("WinRM command execution started on '{0}:{1}'." -f $address, $port)

    try {
        $invokeParameters = @{
            ComputerName   = $address
            ScriptBlock    = $ScriptBlock
            ArgumentList   = @($ArgumentList)
            Authentication = $authentication
            Credential     = $credential
            Port           = $port
            ErrorAction    = 'Stop'
        }

        if ($useSsl) {
            $invokeParameters['UseSSL'] = $true
        }

        if ($null -ne $sessionOption) {
            $invokeParameters['SessionOption'] = $sessionOption
        }

        $result = Invoke-Command @invokeParameters
        Write-OpsTransportLog -Level Decision -Message ("WinRM command execution completed on '{0}'." -f $address)
        return $result
    }
    catch {
        $rawError = $_.Exception.Message
        $guidance = "Vérifiez la connectivité réseau et les paramètres d'authentification WinRM."
        if ($rawError -match 'Access is denied|access denied|Unauthorized') {
            $guidance = "Authentification WinRM refusée. Correction attendue : vérifiez CredentialRef, Kerberos/NTLM/CredSSP et les droits du compte."
        }
        elseif ($rawError -match 'WinRM client cannot process|connect to the destination specified') {
            if ($port -eq 5985 -or $port -eq 5986) {
                $guidance = "Port $port fermé ou service WinRM inactif. Activez WinRM côté cible avec Enable-PSRemoting."
            }
        }

        $errorMessage = "Échec d'exécution WinRM vers '$address'. Cause probable : $guidance Détail technique : $rawError"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
}

function Send-WinRMFile {
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
    $address = Get-OpsTransportAddress -TargetTable $targetTable
    $effectiveTimeoutSec = Get-OpsTransportTimeoutSec -TargetTable $targetTable -Kind 'Transfer' -DefaultValue 600
    $resolvedLocalPath = [System.IO.Path]::GetFullPath($LocalPath)
    if (-not (Test-Path -LiteralPath $resolvedLocalPath)) {
        throw "Le fichier local '$resolvedLocalPath' est introuvable. Correction attendue : vérifiez le chemin source."
    }

    if (-not $PSCmdlet.ShouldProcess($address, "Transférer un fichier vers '$RemotePath' via WinRM")) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("WinRM upload started: {0} -> {1}:{2}" -f $resolvedLocalPath, $address, $RemotePath)

    $session = $null
    try {
        $session = New-OpsWinRMSessionInternal -TargetTable $targetTable -TimeoutSec $effectiveTimeoutSec
        Copy-Item -LiteralPath $resolvedLocalPath -Destination $RemotePath -ToSession $session -Force -ErrorAction Stop
        Write-OpsTransportLog -Level Decision -Message ("WinRM upload completed: {0}" -f $resolvedLocalPath)
        return [pscustomobject]@{
            LocalPath  = $resolvedLocalPath
            RemotePath = $RemotePath
            Target     = $address
        }
    }
    catch {
        $errorMessage = "Échec du transfert WinRM vers '$address'. Cause probable : droits insuffisants ou chemin distant invalide. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
    finally {
        if ($null -ne $session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }
    }
}

function Receive-WinRMFile {
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
    $address = Get-OpsTransportAddress -TargetTable $targetTable
    $effectiveTimeoutSec = Get-OpsTransportTimeoutSec -TargetTable $targetTable -Kind 'Transfer' -DefaultValue 600
    $resolvedLocalPath = [System.IO.Path]::GetFullPath($LocalPath)
    $destinationDirectory = Split-Path -Path $resolvedLocalPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    if (-not $PSCmdlet.ShouldProcess($address, "Récupérer un fichier '$RemotePath' via WinRM")) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("WinRM download started: {0}:{1} -> {2}" -f $address, $RemotePath, $resolvedLocalPath)

    $session = $null
    try {
        $session = New-OpsWinRMSessionInternal -TargetTable $targetTable -TimeoutSec $effectiveTimeoutSec
        Copy-Item -Path $RemotePath -Destination $resolvedLocalPath -FromSession $session -Force -ErrorAction Stop
        Write-OpsTransportLog -Level Decision -Message ("WinRM download completed: {0}" -f $resolvedLocalPath)
        return [pscustomobject]@{
            RemotePath = $RemotePath
            LocalPath  = $resolvedLocalPath
            Target     = $address
        }
    }
    catch {
        $errorMessage = "Échec de la récupération WinRM depuis '$address'. Cause probable : fichier distant introuvable ou droits insuffisants. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
    }
    finally {
        if ($null -ne $session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }
    }
}

function Test-WinRMConnection {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $address = Get-OpsTransportAddress -TargetTable $targetTable
    if (-not $PSCmdlet.ShouldProcess($address, 'Tester la connexion WinRM')) {
        return [pscustomobject]@{
            Success = $false
            Message = 'Test de connexion WinRM ignoré (WhatIf/Confirm).'
        }
    }

    try {
        $probeResult = Invoke-WinRMCommand -Target $targetTable -ScriptBlock { [System.Net.Dns]::GetHostName() } -TimeoutSec 30
        $probeText = @($probeResult) -join ''
        if ([string]::IsNullOrWhiteSpace($probeText)) {
            return [pscustomobject]@{
                Success = $false
                Message = "Connexion WinRM établie vers '$address' mais réponse inattendue."
            }
        }

        return [pscustomobject]@{
            Success = $true
            Message = "Connexion WinRM authentifiée vers '$address'."
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Message = "Connexion WinRM impossible vers '$address'. Détail : $($_.Exception.Message)"
        }
    }
}
