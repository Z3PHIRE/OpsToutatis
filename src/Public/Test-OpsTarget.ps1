function Test-OpsTarget {
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

    if (-not $PSCmdlet.ShouldProcess($targetName, 'Lancer les pré-vols de connectivité et capacité')) {
        return $null
    }

    $preflightChecks = [System.Collections.Generic.List[object]]::new()
    $stepCount = 5
    $progressId = 701
    $progressActivity = "Pré-vol OpsToutatis pour $targetName"
    $targetInfo = $null
    $authSucceeded = $false
    $isElevated = $false
    $systemFreeBytes = [int64]0

    $appendCheck = {
        param(
            [int]$StepNumber,
            [string]$StepName,
            [bool]$Success,
            [string]$Message
        )

        $preflightChecks.Add([pscustomobject]@{
            StepNumber = $StepNumber
            StepName   = $StepName
            Success    = $Success
            Message    = $Message
        }) | Out-Null
    }

    try {
        $port = Get-OpsTransportPort -TargetTable $targetTable

        Write-Progress -Id $progressId -Activity $progressActivity -Status "Étape 1/5 - Vérification de la joignabilité réseau (ping ou TCP)." -PercentComplete 10
        $step1Success = $true
        $step1Message = "Joignabilité locale validée pour '$targetName'."
        if ($transportName -ne 'Local') {
            $pingReachable = $false
            try {
                $pingReachable = Test-Connection -ComputerName $address -Count 1 -Quiet -ErrorAction Stop
            }
            catch {
                $pingReachable = $false
            }

            $tcpReachable = Test-OpsTcpPort -ComputerName $address -Port $port -TimeoutSec 5
            $step1Success = ($pingReachable -or $tcpReachable)

            if ($step1Success) {
                if ($pingReachable) {
                    $step1Message = "La cible répond au ping. Le réseau semble opérationnel."
                }
                else {
                    $step1Message = "Le ping est filtré, mais la cible répond en TCP. Le réseau reste exploitable."
                }
            }
            else {
                $step1Message = "La cible n'est pas joignable en ping/TCP. Correction attendue : vérifiez l'adresse, la route réseau et les règles de pare-feu."
            }
        }

        & $appendCheck -StepNumber 1 -StepName 'Reachability' -Success:$step1Success -Message $step1Message

        Write-Progress -Id $progressId -Activity $progressActivity -Status "Étape 2/5 - Vérification de l'ouverture du port de transport." -PercentComplete 30
        $step2Success = $true
        $step2Message = "Aucun port réseau requis pour le transport Local."
        if ($transportName -ne 'Local') {
            $step2Success = Test-OpsTcpPort -ComputerName $address -Port $port -TimeoutSec 5
            if ($step2Success) {
                $step2Message = "Port $port accessible sur '$address'."
            }
            else {
                if ($transportName -eq 'WinRM') {
                    $step2Message = "Port $port fermé. Activez WinRM avec Enable-PSRemoting côté cible, puis ouvrez 5985/5986."
                }
                else {
                    $step2Message = "Port $port fermé. Activez SSH côté cible et ouvrez le port 22 (ou le port configuré)."
                }
            }
        }

        & $appendCheck -StepNumber 2 -StepName 'TransportPort' -Success:$step2Success -Message $step2Message

        Write-Progress -Id $progressId -Activity $progressActivity -Status "Étape 3/5 - Vérification de l'authentification." -PercentComplete 50
        $authResult = $null
        switch ($transportName) {
            'Local' {
                $authResult = Test-LocalConnection -Target $targetTable
            }
            'WinRM' {
                $authResult = Test-WinRMConnection -Target $targetTable
            }
            'SSH' {
                $authResult = Test-SSHConnection -Target $targetTable
            }
            default {
                $authResult = [pscustomobject]@{
                    Success = $false
                    Message = "Transport non supporté '$transportName'."
                }
            }
        }

        $authSucceeded = [bool]$authResult.Success
        $step3Message = [string]$authResult.Message
        if ([string]::IsNullOrWhiteSpace($step3Message)) {
            if ($authSucceeded) {
                $step3Message = "Authentification réussie sur '$targetName'."
            }
            else {
                $step3Message = "Échec d'authentification sur '$targetName'."
            }
        }

        & $appendCheck -StepNumber 3 -StepName 'Authentication' -Success:$authSucceeded -Message $step3Message

        if ($authSucceeded) {
            $targetInfo = Get-OpsTargetInfo -Target $targetTable -TimeoutSec $TimeoutSec
        }

        Write-Progress -Id $progressId -Activity $progressActivity -Status "Étape 4/5 - Vérification des privilèges (admin/sudo)." -PercentComplete 70
        $step4Success = $false
        $step4Message = "Impossible d'évaluer les privilèges sans authentification réussie."
        if ($authSucceeded -and $null -ne $targetInfo) {
            try {
                if ([string]$targetInfo.Family -eq 'Windows') {
                    $elevationProbe = Invoke-OpsRemote -Target $targetTable -TimeoutSec $TimeoutSec -ScriptBlock {
                        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
                        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
                        $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    }

                    $isElevated = [bool](@($elevationProbe)[0])
                    $step4Success = $isElevated
                    $step4Message = "Privilèges administrateur détectés sur la cible Windows."
                    if (-not $isElevated) {
                        $step4Message = "Le compte distant n'a pas de privilèges administrateur. Correction attendue : utilisez un compte administrateur."
                    }
                }
                else {
                    $elevationProbe = Invoke-OpsRemote -Target $targetTable -TimeoutSec $TimeoutSec -ScriptBlock {
                        $isRoot = $false
                        try {
                            $uidText = (& id -u 2>$null)
                            if (-not [string]::IsNullOrWhiteSpace($uidText)) {
                                $isRoot = ([int]$uidText -eq 0)
                            }
                        }
                        catch {
                            $isRoot = $false
                        }

                        if ($isRoot) {
                            return $true
                        }

                        if ($null -eq (Get-Command -Name sudo -ErrorAction SilentlyContinue)) {
                            return $false
                        }

                        & sudo -n true 2>$null
                        return ($LASTEXITCODE -eq 0)
                    }

                    $isElevated = [bool](@($elevationProbe)[0])
                    $step4Success = $isElevated
                    $step4Message = "Sudo/root disponible sur la cible Linux."
                    if (-not $isElevated) {
                        $step4Message = "Sudo non disponible pour ce compte. Correction attendue : utilisez un compte root ou autorisez sudo sans interaction."
                    }
                }

                if ($transportName -eq 'Local' -and -not $step4Success) {
                    $step4Success = $true
                    $step4Message = "Mode Local sans élévation explicite. Pré-vol validé, mais certaines actions système pourront exiger un shell élevé."
                }
            }
            catch {
                $step4Success = $false
                $step4Message = "Impossible de vérifier les privilèges. Détail : $($_.Exception.Message)"
            }
        }

        & $appendCheck -StepNumber 4 -StepName 'Elevation' -Success:$step4Success -Message $step4Message

        Write-Progress -Id $progressId -Activity $progressActivity -Status "Étape 5/5 - Vérification de l'espace disque système (> 1 Go)." -PercentComplete 90
        $step5Success = $false
        $step5Message = "Impossible d'évaluer l'espace disque sans connexion valide."
        if ($authSucceeded -and $null -ne $targetInfo) {
            try {
                if ([string]$targetInfo.Family -eq 'Windows') {
                    $diskProbe = Invoke-OpsRemote -Target $targetTable -TimeoutSec $TimeoutSec -ScriptBlock {
                        $systemDrive = $env:SystemDrive
                        if ([string]::IsNullOrWhiteSpace($systemDrive)) {
                            $systemDrive = 'C:'
                        }

                        $filter = "DeviceID='$systemDrive'"
                        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter $filter -ErrorAction Stop
                        [int64]$disk.FreeSpace
                    }
                }
                else {
                    $diskProbe = Invoke-OpsRemote -Target $targetTable -TimeoutSec $TimeoutSec -ScriptBlock {
                        $dfLine = (df -Pk / | Select-Object -Skip 1 | Select-Object -First 1)
                        if ([string]::IsNullOrWhiteSpace($dfLine)) {
                            throw 'Sortie df vide.'
                        }

                        $parts = @($dfLine -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        if (@($parts).Count -lt 4) {
                            throw "Sortie df inattendue: $dfLine"
                        }

                        [int64]$parts[3] * 1024
                    }
                }

                $systemFreeBytes = [int64](@($diskProbe)[0])
                $minimumBytes = [int64]1GB
                $step5Success = ($systemFreeBytes -gt $minimumBytes)
                if ($step5Success) {
                    $step5Message = "Espace disque système suffisant : $systemFreeBytes octets libres."
                }
                else {
                    $step5Message = "Espace disque insuffisant : $systemFreeBytes octets libres. Correction attendue : libérez au moins 1 Go sur le disque système."
                }
            }
            catch {
                $step5Success = $false
                $step5Message = "Impossible d'évaluer l'espace disque système. Détail : $($_.Exception.Message)"
            }
        }

        & $appendCheck -StepNumber 5 -StepName 'SystemDisk' -Success:$step5Success -Message $step5Message
    }
    finally {
        Write-Progress -Id $progressId -Activity $progressActivity -Completed
    }

    $overallSuccess = (@($preflightChecks | Where-Object { -not $_.Success }).Count -eq 0)
    $result = [pscustomobject]@{
        TargetName       = $targetName
        Address          = $address
        Transport        = $transportName
        Success          = $overallSuccess
        Family           = $(if ($null -ne $targetInfo) { [string]$targetInfo.Family } else { 'Unknown' })
        Distribution     = $(if ($null -ne $targetInfo) { [string]$targetInfo.Distribution } else { 'Unknown' })
        Version          = $(if ($null -ne $targetInfo) { [string]$targetInfo.Version } else { 'Unknown' })
        Architecture     = $(if ($null -ne $targetInfo) { [string]$targetInfo.Architecture } else { 'Unknown' })
        HostName         = $(if ($null -ne $targetInfo) { [string]$targetInfo.HostName } else { '' })
        IsElevated       = [bool]$isElevated
        SystemFreeBytes  = [int64]$systemFreeBytes
        PreflightChecks  = @($preflightChecks)
        TestedAtUtc      = (Get-Date).ToUniversalTime()
    }

    return $result
}
