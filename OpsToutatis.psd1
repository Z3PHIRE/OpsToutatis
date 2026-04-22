@{
    RootModule        = 'OpsToutatis.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '7dbfc694-9a7d-4e8d-92a9-d123bc8d3f6d'
    Author            = 'OpsToutatis Contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 OpsToutatis Contributors. All rights reserved.'
    Description       = 'OpsToutatis is a cross-platform PowerShell infrastructure orchestration module.'
    PowerShellVersion = '5.1'

    CompatiblePSEditions = @(
        'Desktop',
        'Core'
    )

    FunctionsToExport = @(
        'Start-OpsToutatis',
        'Import-OpsInventory',
        'Import-OpsPlaybook',
        'Test-OpsInventory',
        'Test-OpsPlaybook',
        'Set-OpsCredential',
        'Get-OpsCredential'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('PowerShell', 'Infrastructure', 'Orchestration', 'CrossPlatform')
            LicenseUri = 'https://github.com/Z3PHIRE/OpsToutatis/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Z3PHIRE/OpsToutatis'
        }
    }
}
