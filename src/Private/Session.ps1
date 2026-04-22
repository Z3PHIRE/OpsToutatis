if (-not (Get-Variable -Name OpsCurrentSession -Scope Script -ErrorAction SilentlyContinue)) {
    $script:OpsCurrentSession = $null
}

function New-OpsSession {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath = (Get-Location).Path
    )

    $resolvedBasePath = [System.IO.Path]::GetFullPath($BasePath)
    if (-not (Test-Path -LiteralPath $resolvedBasePath)) {
        throw "Le chemin de base '$resolvedBasePath' est introuvable."
    }

    if ($null -ne $script:OpsCurrentSession) {
        Close-OpsSession | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $randomSuffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $sessionId = ('{0}-{1}' -f $timestamp, $randomSuffix)

    $logsRootPath = [System.IO.Path]::GetFullPath((Join-Path -Path $resolvedBasePath -ChildPath 'logs'))
    $sessionPath = [System.IO.Path]::GetFullPath((Join-Path -Path $logsRootPath -ChildPath $sessionId))

    if (-not $PSCmdlet.ShouldProcess($sessionPath, 'Create OpsToutatis session directory and log files')) {
        return
    }

    New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null

    $sessionLogPath = Join-Path -Path $sessionPath -ChildPath 'session.log'
    $actionsLogPath = Join-Path -Path $sessionPath -ChildPath 'actions.log'
    $decisionsLogPath = Join-Path -Path $sessionPath -ChildPath 'decisions.log'
    $errorsLogPath = Join-Path -Path $sessionPath -ChildPath 'errors.log'
    $transcriptLogPath = Join-Path -Path $sessionPath -ChildPath 'transcript.log'

    $logFiles = @(
        $sessionLogPath,
        $actionsLogPath,
        $decisionsLogPath,
        $errorsLogPath,
        $transcriptLogPath
    )

    foreach ($logFile in $logFiles) {
        if (-not (Test-Path -LiteralPath $logFile)) {
            New-Item -ItemType File -Path $logFile -Force | Out-Null
        }
    }

    $session = [pscustomobject]@{
        SessionId         = $sessionId
        BasePath          = $resolvedBasePath
        LogsRootPath      = $logsRootPath
        SessionPath       = $sessionPath
        SessionLogPath    = [System.IO.Path]::GetFullPath($sessionLogPath)
        ActionsLogPath    = [System.IO.Path]::GetFullPath($actionsLogPath)
        DecisionsLogPath  = [System.IO.Path]::GetFullPath($decisionsLogPath)
        ErrorsLogPath     = [System.IO.Path]::GetFullPath($errorsLogPath)
        TranscriptLogPath = [System.IO.Path]::GetFullPath($transcriptLogPath)
        StartedAtUtc      = (Get-Date).ToUniversalTime()
        EndedAtUtc        = $null
        DurationSeconds   = 0.0
        ActionCount       = 0
        DecisionCount     = 0
        ErrorCount        = 0
        IsClosed          = $false
    }

    $script:OpsCurrentSession = $session
    return $script:OpsCurrentSession
}

function Get-OpsSession {
    [CmdletBinding()]
    param()

    if ($null -eq $script:OpsCurrentSession) {
        return $null
    }

    if ($script:OpsCurrentSession.IsClosed) {
        return $null
    }

    return $script:OpsCurrentSession
}

function Close-OpsSession {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()

    $session = Get-OpsSession
    if ($null -eq $session) {
        return $null
    }

    if (-not $PSCmdlet.ShouldProcess($session.SessionPath, 'Close OpsToutatis session')) {
        return $session
    }

    $endedAtUtc = (Get-Date).ToUniversalTime()
    $durationSeconds = [Math]::Round(($endedAtUtc - $session.StartedAtUtc).TotalSeconds, 3)
    $summaryMessage = ('Session summary: actions={0}; decisions={1}; errors={2}; durationSeconds={3}' -f
        $session.ActionCount,
        $session.DecisionCount,
        $session.ErrorCount,
        $durationSeconds)

    Write-OpsLog -Level Info -Message $summaryMessage | Out-Null

    $session.EndedAtUtc = $endedAtUtc
    $session.DurationSeconds = $durationSeconds
    $session.IsClosed = $true

    $script:OpsCurrentSession = $null
    return $session
}
