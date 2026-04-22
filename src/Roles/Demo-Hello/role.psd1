@{
    Id                   = 'Demo-Hello'
    DisplayName          = 'Demo - Creation du fichier hello.txt'
    Category             = 'Demo/Basics'
    SupportedOS          = @(
        'Windows',
        'Linux',
        'WindowsServer2016',
        'WindowsServer2019',
        'WindowsServer2022',
        'WindowsServer2025',
        'Ubuntu2204',
        'Ubuntu2404',
        'Debian12',
        'RHEL9'
    )
    Requires             = @()
    Conflicts            = @()
    RiskLevel            = 'Low'
    DestructivePotential = $false
    EstimatedDurationMin = 1
}
