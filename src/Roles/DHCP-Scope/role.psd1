@{
    Id                   = 'DHCP-Scope'
    DisplayName          = 'DHCP - IPv4 Scope'
    Category             = 'Windows/DHCP'
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
    EstimatedDurationMin = 20
}
