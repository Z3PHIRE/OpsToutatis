@{
    Id                   = 'ADDS-AdditionalDC'
    DisplayName          = 'AD DS - Additional Domain Controller'
    Category             = 'Windows/DirectoryServices'
    SupportedOS          = @(
        'WindowsServer2016',
        'WindowsServer2019',
        'WindowsServer2022',
        'WindowsServer2025'
    )
    Requires             = @()
    Conflicts            = @('ADDS-Forest')
    RiskLevel            = 'High'
    DestructivePotential = $true
    EstimatedDurationMin = 40
}
