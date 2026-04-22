function Set-OpsCredential {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [SecureString]$Secret,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'OpsToutatisVault'
    )

    $vaultState = Initialize-OpsSecretVault -VaultName $VaultName
    if (-not $vaultState.Success) {
        Write-Warning $vaultState.Message
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess("$VaultName/$Name", 'Enregistrer un secret dans le coffre OpsToutatis')) {
        return $false
    }

    try {
        Set-Secret -Name $Name -Secret $Secret -Vault $VaultName -ErrorAction Stop
    }
    catch {
        Write-Warning "Impossible d'enregistrer le secret '$Name' dans le coffre '$VaultName'. Détail : $($_.Exception.Message)"
        return $false
    }

    return $true
}
