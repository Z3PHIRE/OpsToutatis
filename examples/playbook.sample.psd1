@{
    Name        = 'corp-baseline'
    Description = 'Déploiement socle domaine + web'
    Targets     = @(
        @{
            Host  = 'DC01'
            Roles = @('ADDS-Forest', 'DNS-Primary')
        }
        @{
            Host  = 'WEB01'
            Roles = @('Linux-Nginx')
        }
    )
    Options     = @{
        ParallelHosts    = 3
        StopOnFirstError = $false
    }
}
