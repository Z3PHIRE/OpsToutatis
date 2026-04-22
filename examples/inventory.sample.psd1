@{
    Hosts = @(
        @{
            Name          = 'DC01'
            Address       = '192.168.1.10'
            Transport     = 'WinRM'
            OS            = 'WindowsServer2022'
            CredentialRef = 'corp-admin'
        }
        @{
            Name          = 'WEB01'
            Address       = '192.168.1.20'
            Transport     = 'SSH'
            OS            = 'Ubuntu2404'
            CredentialRef = 'web-root'
        }
    )
    Groups = @{
        DomainControllers = @('DC01')
        WebServers        = @('WEB01')
    }
}
