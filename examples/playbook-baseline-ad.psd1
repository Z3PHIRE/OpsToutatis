@{
    Name        = 'baseline-ad'
    Description = 'Déploiement baseline Active Directory + partage de fichiers'
    Targets     = @(
        @{
            Host  = 'DC01'
            Roles = @('ADDS-Forest', 'DNS-Primary')
        }
        @{
            Host  = 'FS01'
            Roles = @('FileServer-Share')
        }
    )
    Options     = @{
        ParallelHosts    = 1
        StopOnFirstError = $true
    }
}
