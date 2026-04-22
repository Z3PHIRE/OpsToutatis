function Start-OpsToutatis {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath = (Get-Location).Path
    )

    $resolvedBasePath = [System.IO.Path]::GetFullPath($BasePath)
    if (-not (Test-Path -LiteralPath $resolvedBasePath)) {
        throw "Le chemin '$resolvedBasePath' est introuvable."
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedBasePath, 'Start OpsToutatis session')) {
        return
    }

    $session = New-OpsSession -BasePath $resolvedBasePath
    $welcomeMessage = ('Bienvenue dans OpsToutatis. Session ouverte : {0}. Logs : {1}' -f
        $session.SessionId,
        $session.SessionPath)

    Write-Output $welcomeMessage
}
