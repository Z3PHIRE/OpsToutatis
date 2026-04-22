if (-not (Get-Variable -Name OpsCurrentPlaybook -Scope Script -ErrorAction SilentlyContinue)) {
    $script:OpsCurrentPlaybook = $null
}

function Import-OpsPlaybook {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [string]$InventoryPath,

        [Parameter()]
        [AllowNull()]
        [object]$InventoryData
    )

    $loadedPlaybook = Import-OpsDataFile -Path $Path -DocumentKind 'playbook'
    $validation = Test-OpsPlaybook -PlaybookData $loadedPlaybook.Data -SourcePath $loadedPlaybook.Path -InventoryPath $InventoryPath -InventoryData $InventoryData -PassThru
    if (-not $validation.IsValid) {
        throw $validation.Message
    }

    if (-not $PSCmdlet.ShouldProcess($loadedPlaybook.Path, 'Importer le playbook OpsToutatis')) {
        return $null
    }

    $script:OpsCurrentPlaybook = [pscustomobject]@{
        Path          = $loadedPlaybook.Path
        Data          = $validation.Playbook
        ImportedAtUtc = (Get-Date).ToUniversalTime()
    }

    return $script:OpsCurrentPlaybook
}
