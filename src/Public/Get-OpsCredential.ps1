function Get-OpsCredential {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'OpsToutatisVault'
    )

    $vaultState = Initialize-OpsSecretVault -VaultName $VaultName
    if (-not $vaultState.Success) {
        Write-Warning $vaultState.Message
        return $null
    }

    if (-not $PSCmdlet.ShouldProcess("$VaultName/$Name", 'Récupérer un secret depuis le coffre OpsToutatis')) {
        return $null
    }

    try {
        return Get-Secret -Name $Name -Vault $VaultName -ErrorAction Stop
    }
    catch {
        Write-Warning "Impossible de lire le secret '$Name' dans le coffre '$VaultName'. Détail : $($_.Exception.Message)"
        return $null
    }
}
