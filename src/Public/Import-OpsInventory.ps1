if (-not (Get-Variable -Name OpsCurrentInventory -Scope Script -ErrorAction SilentlyContinue)) {
    $script:OpsCurrentInventory = $null
}

function Import-OpsInventory {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $loadedInventory = Import-OpsDataFile -Path $Path -DocumentKind 'inventaire'
    $validation = Test-OpsInventory -InventoryData $loadedInventory.Data -SourcePath $loadedInventory.Path -PassThru
    if (-not $validation.IsValid) {
        throw $validation.Message
    }

    if (-not $PSCmdlet.ShouldProcess($loadedInventory.Path, 'Importer l''inventaire OpsToutatis')) {
        return $null
    }

    $script:OpsCurrentInventory = [pscustomobject]@{
        Path          = $loadedInventory.Path
        Data          = $validation.Inventory
        ImportedAtUtc = (Get-Date).ToUniversalTime()
    }

    return $script:OpsCurrentInventory
}
