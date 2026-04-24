@{
    Id                   = 'IIS-SiteBasic'
    DisplayName          = 'IIS - Basic Site'
    Category             = 'Windows/Web'
    SupportedOS          = @(
        'WindowsServer2016',
        'WindowsServer2019',
        'WindowsServer2022',
        'WindowsServer2025'
    )
    Requires             = @()
    Conflicts            = @()
    RiskLevel            = 'High'
    DestructivePotential = $true
    EstimatedDurationMin = 15
}
