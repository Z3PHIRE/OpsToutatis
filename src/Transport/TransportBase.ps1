function Get-OpsTransportTargetTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target
    )

    $targetTable = ConvertTo-OpsPropertyTable -InputObject $Target
    if ($null -eq $targetTable) {
        throw "Cible invalide. Correction attendue : fournissez une hashtable contenant au minimum Name, Address et Transport."
    }

    return $targetTable
}

function Get-OpsTransportName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable
    )

    if (-not $TargetTable.ContainsKey('Transport')) {
        throw "Transport manquant dans la cible. Correction attendue : ajoutez Transport='Local'|'WinRM'|'SSH'."
    }

    $transportName = [string]$TargetTable['Transport']
    if ([string]::IsNullOrWhiteSpace($transportName)) {
        throw "Transport vide dans la cible. Correction attendue : utilisez Local, WinRM ou SSH."
    }

    switch -Regex ($transportName.ToLowerInvariant()) {
        '^local$' {
            return 'Local'
        }
        '^winrm$' {
            return 'WinRM'
        }
        '^ssh$' {
            return 'SSH'
        }
        default {
            throw "Transport non supporté '$transportName'. Correction attendue : utilisez Local, WinRM ou SSH."
        }
    }
}

function Get-OpsTransportAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable
    )

    if ($TargetTable.ContainsKey('Address')) {
        $address = [string]$TargetTable['Address']
        if (-not [string]::IsNullOrWhiteSpace($address)) {
            return $address
        }
    }

    if ($TargetTable.ContainsKey('Name')) {
        $name = [string]$TargetTable['Name']
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name
        }
    }

    throw "Adresse cible manquante. Correction attendue : renseignez Address (ou Name) dans la cible."
}

function Get-OpsTransportBooleanValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter()]
        [bool]$DefaultValue = $false
    )

    if (-not $TargetTable.ContainsKey($Key)) {
        return $DefaultValue
    }

    $value = $TargetTable[$Key]
    if ($value -is [bool]) {
        return [bool]$value
    }

    if ($value -is [int] -or $value -is [long]) {
        return ([int64]$value -ne 0)
    }

    $valueText = [string]$value
    if ([string]::IsNullOrWhiteSpace($valueText)) {
        return $DefaultValue
    }

    switch -Regex ($valueText.Trim().ToLowerInvariant()) {
        '^(1|true|yes|y|on)$' {
            return $true
        }
        '^(0|false|no|n|off)$' {
            return $false
        }
        default {
            return $DefaultValue
        }
    }
}

function Get-OpsTransportPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable
    )

    $transportName = Get-OpsTransportName -TargetTable $TargetTable

    if ($TargetTable.ContainsKey('Port')) {
        $portValue = 0
        if ([int]::TryParse([string]$TargetTable['Port'], [ref]$portValue)) {
            if ($portValue -gt 0 -and $portValue -le 65535) {
                return $portValue
            }
        }
    }

    switch ($transportName) {
        'Local' {
            return 0
        }
        'WinRM' {
            $useSsl = Get-OpsTransportBooleanValue -TargetTable $TargetTable -Key 'UseSsl' -DefaultValue:$false
            if ($useSsl) {
                return 5986
            }

            return 5985
        }
        'SSH' {
            return 22
        }
        default {
            return 0
        }
    }
}

function Get-OpsTransportTimeoutSec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Command', 'Transfer')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 86400)]
        [int]$DefaultValue
    )

    $candidateKeys = @()
    if ($Kind -eq 'Command') {
        $candidateKeys = @('CommandTimeoutSec', 'TimeoutSec')
    }
    else {
        $candidateKeys = @('TransferTimeoutSec', 'TimeoutSec')
    }

    foreach ($candidateKey in $candidateKeys) {
        if (-not $TargetTable.ContainsKey($candidateKey)) {
            continue
        }

        $parsedValue = 0
        if ([int]::TryParse([string]$TargetTable[$candidateKey], [ref]$parsedValue)) {
            if ($parsedValue -ge 1 -and $parsedValue -le 86400) {
                return $parsedValue
            }
        }
    }

    return $DefaultValue
}

function Get-OpsTransportOptionalUserName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable,

        [Parameter()]
        [AllowNull()]
        [pscredential]$Credential
    )

    $candidateKeys = @('UserName', 'Username', 'SshUser', 'SSHUser')
    foreach ($candidateKey in $candidateKeys) {
        if (-not $TargetTable.ContainsKey($candidateKey)) {
            continue
        }

        $candidateValue = [string]$TargetTable[$candidateKey]
        if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
            return $candidateValue
        }
    }

    if ($null -ne $Credential -and -not [string]::IsNullOrWhiteSpace($Credential.UserName)) {
        return [string]$Credential.UserName
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USER)) {
        return [string]$env:USER
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        return [string]$env:USERNAME
    }

    return $null
}

function Resolve-OpsTransportCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TransportName,

        [Parameter()]
        [bool]$Mandatory = $true
    )

    if (-not $TargetTable.ContainsKey('CredentialRef')) {
        if ($Mandatory) {
            throw "CredentialRef manquant pour le transport $TransportName. Correction attendue : stockez un secret via Set-OpsCredential puis référencez-le."
        }

        return $null
    }

    $credentialRef = [string]$TargetTable['CredentialRef']
    if ([string]::IsNullOrWhiteSpace($credentialRef)) {
        if ($Mandatory) {
            throw "CredentialRef vide pour le transport $TransportName. Correction attendue : renseignez un nom de secret non vide."
        }

        return $null
    }

    $secretValue = Get-OpsCredential -Name $credentialRef
    if ($null -eq $secretValue) {
        if ($Mandatory) {
            throw "Le secret '$credentialRef' est introuvable. Correction attendue : exécutez Set-OpsCredential -Name '$credentialRef'."
        }

        return $null
    }

    if ($secretValue -is [pscredential]) {
        return $secretValue
    }

    if ($secretValue -is [SecureString]) {
        $userName = Get-OpsTransportOptionalUserName -TargetTable $TargetTable -Credential $null
        if ([string]::IsNullOrWhiteSpace($userName)) {
            throw "Le secret '$credentialRef' est un SecureString sans nom d'utilisateur. Correction attendue : ajoutez UserName dans l'inventaire ou stockez un PSCredential."
        }

        return [pscredential]::new($userName, $secretValue)
    }

    if ($secretValue.PSObject.Properties['UserName'] -and $secretValue.PSObject.Properties['Password']) {
        $passwordValue = $secretValue.PSObject.Properties['Password'].Value
        if ($passwordValue -is [SecureString]) {
            return [pscredential]::new([string]$secretValue.PSObject.Properties['UserName'].Value, $passwordValue)
        }
    }

    throw "Le secret '$credentialRef' a un type non supporté. Correction attendue : stockez un PSCredential ou un SecureString."
}

function Get-OpsSshKeyPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TargetTable
    )

    $candidateKeys = @('SshKeyPath', 'SSHKeyPath', 'PrivateKeyPath')
    foreach ($candidateKey in $candidateKeys) {
        if (-not $TargetTable.ContainsKey($candidateKey)) {
            continue
        }

        $candidatePath = [string]$TargetTable[$candidateKey]
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        $resolvedPath = [System.IO.Path]::GetFullPath($candidatePath)
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            throw "Clé privée SSH introuvable : '$resolvedPath'. Correction attendue : vérifiez le chemin SshKeyPath."
        }

        return $resolvedPath
    }

    return $null
}

function Write-OpsTransportLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Info', 'Warn', 'Error', 'Action', 'Decision')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Message
    )

    $writeOpsLogCommand = Get-Command -Name Write-OpsLog -ErrorAction SilentlyContinue
    $getOpsSessionCommand = Get-Command -Name Get-OpsSession -ErrorAction SilentlyContinue
    if ($null -eq $writeOpsLogCommand -or $null -eq $getOpsSessionCommand) {
        return
    }

    $session = $null
    try {
        $session = Get-OpsSession
    }
    catch {
        $session = $null
    }

    if ($null -eq $session) {
        return
    }

    try {
        Write-OpsLog -Level $Level -Message $Message | Out-Null
    }
    catch {
    }
}

function Test-OpsTcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter()]
        [ValidateRange(1, 120)]
        [int]$TimeoutSec = 5
    )

    $tcpClient = $null
    $waitHandle = $null
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        $completed = $waitHandle.WaitOne($TimeoutSec * 1000, $false)
        if (-not $completed) {
            return $false
        }

        $tcpClient.EndConnect($asyncResult) | Out-Null
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $waitHandle) {
            $waitHandle.Close()
        }

        if ($null -ne $tcpClient) {
            $tcpClient.Close()
            $tcpClient.Dispose()
        }
    }
}

function Invoke-OpsNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExecutablePath,

        [Parameter()]
        [string[]]$ArgumentList = @(),

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSec = 120,

        [Parameter()]
        [switch]$IgnoreExitCode
    )

    $commandInfo = Get-Command -Name $ExecutablePath -ErrorAction SilentlyContinue
    if ($null -eq $commandInfo) {
        throw "Exécutable introuvable '$ExecutablePath'. Correction attendue : installez l'outil puis vérifiez qu'il est présent dans PATH."
    }

    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param(
                [string]$InnerExecutablePath,
                [string[]]$InnerArgumentList
            )

            $output = & $InnerExecutablePath @InnerArgumentList 2>&1
            $normalizedOutput = @()
            foreach ($line in @($output)) {
                $normalizedOutput += [string]$line
            }

            $nativeExitCode = $LASTEXITCODE
            if ($null -eq $nativeExitCode) {
                $nativeExitCode = 0
            }

            return [pscustomobject]@{
                ExitCode = [int]$nativeExitCode
                Output   = @($normalizedOutput)
            }
        } -ArgumentList $commandInfo.Source, @($ArgumentList)

        $completedJob = Wait-Job -Job $job -Timeout $TimeoutSec
        if ($null -eq $completedJob) {
            throw "Le processus '$ExecutablePath' a dépassé le timeout de $TimeoutSec seconde(s)."
        }

        $result = Receive-Job -Job $job -ErrorAction Stop
        if (-not $IgnoreExitCode.IsPresent -and [int]$result.ExitCode -ne 0) {
            $errorText = ''
            if (@($result.Output).Count -gt 0) {
                $errorText = @($result.Output) -join [Environment]::NewLine
            }

            if ([string]::IsNullOrWhiteSpace($errorText)) {
                throw "Le processus '$ExecutablePath' a échoué avec le code de sortie $($result.ExitCode)."
            }

            throw "Le processus '$ExecutablePath' a échoué avec le code de sortie $($result.ExitCode). Détail : $errorText"
        }

        return $result
    }
    catch {
        throw $_
    }
    finally {
        if ($null -ne $job) {
            try {
                Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
            }

            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Test-OpsTransportContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Local', 'WinRM', 'SSH')]
        [string]$TransportName
    )

    $requiredFunctions = @(
        ('Invoke-{0}Command' -f $TransportName),
        ('Send-{0}File' -f $TransportName),
        ('Receive-{0}File' -f $TransportName),
        ('Test-{0}Connection' -f $TransportName)
    )

    $missingFunctions = @()
    foreach ($requiredFunction in $requiredFunctions) {
        if ($null -eq (Get-Command -Name $requiredFunction -ErrorAction SilentlyContinue)) {
            $missingFunctions += $requiredFunction
        }
    }

    if (@($missingFunctions).Count -gt 0) {
        throw "Implémentation transport incomplète pour '$TransportName'. Fonctions manquantes : $($missingFunctions -join ', ')."
    }

    return $true
}
