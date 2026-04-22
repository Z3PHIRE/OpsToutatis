function Invoke-LocalCommand {
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

    if (-not $PSCmdlet.ShouldProcess('localhost', 'Exécuter une commande locale')) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("Local command execution started (timeout={0}s)." -f $effectiveTimeoutSec)

    $job = $null
    try {
        $scriptText = $ScriptBlock.ToString()
        $serializedArguments = [System.Management.Automation.PSSerializer]::Serialize(@($ArgumentList))
        $job = Start-Job -ScriptBlock {
            param(
                [string]$InnerScriptText,
                [string]$InnerArgumentPayload
            )

            $innerArgumentList = [System.Management.Automation.PSSerializer]::Deserialize($InnerArgumentPayload)
            if ($null -eq $innerArgumentList) {
                $innerArgumentList = @()
            }
            elseif ($innerArgumentList -is [string] -or -not ($innerArgumentList -is [System.Collections.IEnumerable])) {
                $innerArgumentList = @($innerArgumentList)
            }

            $innerScriptBlock = [scriptblock]::Create($InnerScriptText)
            & $innerScriptBlock @innerArgumentList
        } -ArgumentList $scriptText, $serializedArguments

        $completedJob = Wait-Job -Job $job -Timeout $effectiveTimeoutSec
        if ($null -eq $completedJob) {
            throw "Timeout atteint après $effectiveTimeoutSec seconde(s) lors de l'exécution locale."
        }

        $result = Receive-Job -Job $job -ErrorAction Stop
        Write-OpsTransportLog -Level Decision -Message 'Local command execution completed successfully.'
        return $result
    }
    catch {
        $errorMessage = "Échec de l'exécution locale. Cause probable : script invalide ou timeout. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
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

function Send-LocalFile {
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
    $resolvedRemotePath = [System.IO.Path]::GetFullPath($RemotePath)
    if (-not (Test-Path -LiteralPath $resolvedLocalPath)) {
        throw "Le fichier source '$resolvedLocalPath' est introuvable. Correction attendue : vérifiez le chemin local."
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedRemotePath, 'Copier un fichier en transport Local')) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("Local file upload started: {0} -> {1}" -f $resolvedLocalPath, $resolvedRemotePath)

    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param(
                [string]$InnerLocalPath,
                [string]$InnerRemotePath
            )

            $destinationDirectory = Split-Path -Path $InnerRemotePath -Parent
            if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -LiteralPath $destinationDirectory)) {
                New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            }

            Copy-Item -LiteralPath $InnerLocalPath -Destination $InnerRemotePath -Force -ErrorAction Stop
            return [pscustomobject]@{
                LocalPath  = $InnerLocalPath
                RemotePath = $InnerRemotePath
            }
        } -ArgumentList $resolvedLocalPath, $resolvedRemotePath

        $completedJob = Wait-Job -Job $job -Timeout $effectiveTimeoutSec
        if ($null -eq $completedJob) {
            throw "Timeout atteint après $effectiveTimeoutSec seconde(s) pendant la copie de fichier locale."
        }

        $copyResult = Receive-Job -Job $job -ErrorAction Stop
        Write-OpsTransportLog -Level Decision -Message 'Local file upload completed successfully.'
        return $copyResult
    }
    catch {
        $errorMessage = "Échec de copie locale vers '$resolvedRemotePath'. Cause probable : droits insuffisants ou chemin invalide. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
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

function Receive-LocalFile {
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

    $resolvedRemotePath = [System.IO.Path]::GetFullPath($RemotePath)
    $resolvedLocalPath = [System.IO.Path]::GetFullPath($LocalPath)

    if (-not (Test-Path -LiteralPath $resolvedRemotePath)) {
        throw "Le fichier distant simulé '$resolvedRemotePath' est introuvable. Correction attendue : vérifiez le chemin source."
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedLocalPath, 'Copier un fichier depuis transport Local')) {
        return $null
    }

    Write-OpsTransportLog -Level Action -Message ("Local file download started: {0} -> {1}" -f $resolvedRemotePath, $resolvedLocalPath)

    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param(
                [string]$InnerRemotePath,
                [string]$InnerLocalPath
            )

            $destinationDirectory = Split-Path -Path $InnerLocalPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -LiteralPath $destinationDirectory)) {
                New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            }

            Copy-Item -LiteralPath $InnerRemotePath -Destination $InnerLocalPath -Force -ErrorAction Stop
            return [pscustomobject]@{
                RemotePath = $InnerRemotePath
                LocalPath  = $InnerLocalPath
            }
        } -ArgumentList $resolvedRemotePath, $resolvedLocalPath

        $completedJob = Wait-Job -Job $job -Timeout $effectiveTimeoutSec
        if ($null -eq $completedJob) {
            throw "Timeout atteint après $effectiveTimeoutSec seconde(s) pendant la récupération de fichier locale."
        }

        $copyResult = Receive-Job -Job $job -ErrorAction Stop
        Write-OpsTransportLog -Level Decision -Message 'Local file download completed successfully.'
        return $copyResult
    }
    catch {
        $errorMessage = "Échec de copie locale depuis '$resolvedRemotePath'. Cause probable : droits insuffisants ou chemin invalide. Détail : $($_.Exception.Message)"
        Write-OpsTransportLog -Level Error -Message $errorMessage
        throw $errorMessage
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

function Test-LocalConnection {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target
    )

    $targetTable = Get-OpsTransportTargetTable -Target $Target
    $targetName = Get-OpsTransportAddress -TargetTable $targetTable
    if (-not $PSCmdlet.ShouldProcess($targetName, 'Tester la connexion locale')) {
        return [pscustomobject]@{
            Success = $false
            Message = 'Test de connexion locale ignoré (WhatIf/Confirm).'
        }
    }

    try {
        $probe = Invoke-LocalCommand -Target $targetTable -ScriptBlock { 'OPS_LOCAL_OK' } -TimeoutSec 15
        if (@($probe).Count -ge 1 -and [string]@($probe)[0] -eq 'OPS_LOCAL_OK') {
            return [pscustomobject]@{
                Success = $true
                Message = 'Connexion locale opérationnelle.'
            }
        }

        return [pscustomobject]@{
            Success = $false
            Message = 'Connexion locale indéterminée : réponse inattendue.'
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Message = "Connexion locale en échec. Détail : $($_.Exception.Message)"
        }
    }
}
