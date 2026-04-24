@{
    Id                   = 'ADDS-Forest'
    DisplayName          = 'AD DS - New Forest'
    Category             = 'Windows/DirectoryServices'
    SupportedOS          = @(
        'WindowsServer2016',
        'WindowsServer2019',
        'WindowsServer2022',
        'WindowsServer2025'
    )
    Requires             = @()
    Conflicts            = @('ADDS-AdditionalDC')
    RiskLevel            = 'High'
    DestructivePotential = $true
    EstimatedDurationMin = 45
}
