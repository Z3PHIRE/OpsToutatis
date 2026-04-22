Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$uiPath = Join-Path -Path $repoRoot -ChildPath 'src'
$uiPath = Join-Path -Path $uiPath -ChildPath 'UI'

$uiFiles = @(
    'Theme.ps1',
    'Render.ps1',
    'Menu.ps1',
    'Checklist.ps1',
    'Form.ps1',
    'Progress.ps1',
    'Schema.ps1'
)

foreach ($uiFile in $uiFiles) {
    $uiFilePath = Join-Path -Path $uiPath -ChildPath $uiFile
    . $uiFilePath
}

$capabilities = Get-OpsUICapabilities
$nonInteractiveMode = -not $capabilities.IsInteractive

Write-OpsBanner -Title 'OpsToutatis UI Demo' -Subtitle 'Menu, checklist, formulaire, progression et topologie' -Ascii -NonInteractive:$nonInteractiveMode | Out-Null

$menuItems = @(
    @{ Id = 'deploy'; Label = 'Déployer'; Description = 'Préparer et appliquer un playbook' }
    @{ Id = 'validate'; Label = 'Valider'; Description = 'Contrôler inventaire et playbook' }
    @{ Id = 'report'; Label = 'Rapport'; Description = 'Générer un résumé d''exécution' }
)

$menuSelection = Show-OpsMenu -Title 'Menu principal' -Items $menuItems -DefaultIndex 0 -Ascii -NonInteractive:$nonInteractiveMode
Write-OpsUI -Text ("Option sélectionnée : {0}" -f $menuSelection.Label) -Color Success -Plain:$nonInteractiveMode -Ascii | Out-Null

$checkItems = @(
    @{ Id = 'ADDS-Forest'; Label = 'AD DS Forest'; Description = 'Provisionne la forêt Active Directory'; DefaultChecked = $true }
    @{ Id = 'DNS-Primary'; Label = 'DNS Primary'; Description = 'Configure le DNS primaire'; DefaultChecked = $true }
    @{ Id = 'Linux-Nginx'; Label = 'Linux Nginx'; Description = 'Déploie Nginx sur serveur Linux'; DefaultChecked = $false }
)

$selectedRoles = Show-OpsChecklist -Title 'Sélection des rôles à déployer' -Items $checkItems -Ascii -NonInteractive:$nonInteractiveMode
Write-OpsUI -Text ("Rôles retenus : {0}" -f ($selectedRoles -join ', ')) -Color Success -Plain:$nonInteractiveMode -Ascii | Out-Null

$formFields = @(
    @{
        Name                  = 'DomainName'
        Label                 = 'Nom du domaine'
        Type                  = 'String'
        DefaultValue          = 'corp.local'
        HelpText              = 'Utilisé pour créer ou rejoindre le domaine Active Directory.'
        Validation            = '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        ValidationDescription = 'Doit être un FQDN valide, exemple : corp.local'
    }
    @{
        Name                  = 'DSRMPassword'
        Label                 = 'Mot de passe DSRM'
        Type                  = 'SecureString'
        DefaultValue          = 'P@ssw0rd-Long-DSRM'
        HelpText              = 'Sert à restaurer AD en mode sans échec. 14 caractères minimum, complexité forte.'
        Validation            = { param($v) (Get-OpsPlainTextFromSecureString -SecureValue $v).Length -ge 14 }
        ValidationDescription = 'Au moins 14 caractères.'
    }
    @{
        Name                  = 'ParallelHosts'
        Label                 = 'Parallélisme hôtes'
        Type                  = 'Int'
        DefaultValue          = 3
        HelpText              = 'Nombre d''hôtes traités en parallèle pour accélérer le déploiement.'
        Validation            = { param($v) $v -ge 1 -and $v -le 20 }
        ValidationDescription = 'Valeur entière entre 1 et 20.'
    }
    @{
        Name                  = 'Transport'
        Label                 = 'Transport par défaut'
        Type                  = 'Choice'
        Choices               = @('WinRM', 'SSH', 'Local')
        DefaultValue          = 'WinRM'
        HelpText              = 'Canal de communication utilisé pour exécuter les actions distantes.'
        Validation            = '^(WinRM|SSH|Local)$'
        ValidationDescription = 'Choix autorisé : WinRM, SSH, Local.'
    }
)

$initialValues = @{
    DomainName    = 'corp.local'
    DSRMPassword  = 'P@ssw0rd-Long-DSRM'
    ParallelHosts = 3
    Transport     = 'WinRM'
}

$formValues = Show-OpsForm -Title 'Paramètres de déploiement' -Fields $formFields -InitialValues $initialValues -Ascii -NonInteractive:$nonInteractiveMode

$domainNameResult = [string]$formValues['DomainName']
$parallelHostsResult = [int]$formValues['ParallelHosts']
$transportResult = [string]$formValues['Transport']
Write-OpsUI -Text ("Paramètres saisis : domaine={0}, parallélisme={1}, transport={2}" -f $domainNameResult, $parallelHostsResult, $transportResult) -Color Success -Plain:$nonInteractiveMode -Ascii | Out-Null

$hostProgress = @{
    DC01  = 0
    WEB01 = 0
}

for ($step = 0; $step -le 10; $step++) {
    $percent = $step * 10
    $hostProgress['DC01'] = [Math]::Min(100, $percent + 10)
    $hostProgress['WEB01'] = [Math]::Min(100, $percent)
    Show-OpsProgress -Activity 'Déploiement global' -SubActivity ('Étape {0}/10' -f $step) -Current $step -Total 10 -HostProgress $hostProgress -Ascii -Plain:$nonInteractiveMode -NonInteractive:$nonInteractiveMode | Out-Null
    if (-not $nonInteractiveMode) {
        Start-Sleep -Milliseconds 100
    }
}

$sampleInventoryPath = Join-Path -Path $PSScriptRoot -ChildPath 'inventory.sample.psd1'
if (Test-Path -LiteralPath $sampleInventoryPath) {
    $sampleInventory = Import-PowerShellDataFile -Path $sampleInventoryPath
    Show-OpsTopology -InventoryData $sampleInventory -Ascii -Plain:$nonInteractiveMode -NonInteractive:$nonInteractiveMode | Out-Null
}

Write-OpsUI -Text 'Démo UI terminée.' -Color Success -Plain:$nonInteractiveMode -Ascii | Out-Null
