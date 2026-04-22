Set-StrictMode -Version Latest
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'OpsToutatis inventory and playbook engine' {
    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    InModuleScope OpsToutatis {
        $script:TestRoot = $null

        BeforeEach {
            $script:OpsCurrentInventory = $null
            $script:OpsCurrentPlaybook = $null

            $script:TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('OpsToutatisInvPb-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
            Push-Location -LiteralPath $script:TestRoot
        }

        AfterEach {
            Pop-Location

            if (Test-Path -LiteralPath $script:TestRoot) {
                Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
            }
        }

        It 'imports and validates a valid inventory and playbook' {
            $inventoryPath = Join-Path -Path $script:TestRoot -ChildPath 'inventory.valid.psd1'
            $playbookPath = Join-Path -Path $script:TestRoot -ChildPath 'playbook.valid.psd1'

            $inventoryContent = @'
@{
    Hosts = @(
        @{ Name='DC01'; Address='192.168.1.10'; Transport='WinRM'; OS='WindowsServer2022'; CredentialRef='corp-admin' }
        @{ Name='WEB01'; Address='192.168.1.20'; Transport='SSH'; OS='Ubuntu2404'; CredentialRef='web-root' }
    )
    Groups = @{
        DomainControllers = @('DC01')
        WebServers = @('WEB01')
    }
}
'@

            $playbookContent = @'
@{
    Name = 'corp-baseline'
    Description = 'Déploiement socle domaine + web'
    Targets = @(
        @{ Host='DC01'; Roles=@('ADDS-Forest','DNS-Primary') }
        @{ Host='WEB01'; Roles=@('Linux-Nginx') }
    )
    Options = @{ ParallelHosts = 3; StopOnFirstError = $false }
}
'@

            Set-Content -LiteralPath $inventoryPath -Value $inventoryContent -Encoding UTF8
            Set-Content -LiteralPath $playbookPath -Value $playbookContent -Encoding UTF8

            $importedInventory = Import-OpsInventory -Path $inventoryPath
            if ($null -eq $importedInventory) {
                throw 'Expected inventory import to return data.'
            }

            $inventoryValidation = Test-OpsInventory -Path $inventoryPath -PassThru
            if (-not $inventoryValidation.IsValid) {
                throw "Expected valid inventory but got errors: $($inventoryValidation.Errors -join '; ')"
            }

            $importedPlaybook = Import-OpsPlaybook -Path $playbookPath
            if ($null -eq $importedPlaybook) {
                throw 'Expected playbook import to return data.'
            }

            $playbookValidation = Test-OpsPlaybook -Path $playbookPath -PassThru
            if (-not $playbookValidation.IsValid) {
                throw "Expected valid playbook but got errors: $($playbookValidation.Errors -join '; ')"
            }
        }

        It 'returns a clear french error for invalid IP address in inventory' {
            $inventoryPath = Join-Path -Path $script:TestRoot -ChildPath 'inventory.invalid-ip.psd1'
            $inventoryContent = @'
@{
    Hosts = @(
        @{ Name='DC01'; Address='999.999.10.10'; Transport='WinRM'; OS='WindowsServer2022'; CredentialRef='corp-admin' }
    )
    Groups = @{ DomainControllers = @('DC01') }
}
'@

            Set-Content -LiteralPath $inventoryPath -Value $inventoryContent -Encoding UTF8

            $caughtMessage = $null
            try {
                Test-OpsInventory -Path $inventoryPath | Out-Null
                throw 'Expected an invalid IP error.'
            }
            catch {
                $caughtMessage = $_.Exception.Message
            }

            if ($caughtMessage -notmatch 'Adresse IP invalide') {
                throw "Expected French invalid IP error, got: $caughtMessage"
            }

            if ($caughtMessage -notmatch 'Inventory\.Hosts\[0\]\.Address') {
                throw "Expected key path in error, got: $caughtMessage"
            }
        }

        It 'returns a clear french error when playbook references an unknown host' {
            $inventoryPath = Join-Path -Path $script:TestRoot -ChildPath 'inventory.valid.psd1'
            $playbookPath = Join-Path -Path $script:TestRoot -ChildPath 'playbook.unknown-host.psd1'

            $inventoryContent = @'
@{
    Hosts = @(
        @{ Name='WEB01'; Address='192.168.1.20'; Transport='SSH'; OS='Ubuntu2404'; CredentialRef='web-root' }
    )
    Groups = @{ WebServers = @('WEB01') }
}
'@

            $playbookContent = @'
@{
    Name = 'web-only'
    Description = 'Déploiement web'
    Targets = @(
        @{ Host='MISSING01'; Roles=@('Linux-Nginx') }
    )
    Options = @{ ParallelHosts = 1; StopOnFirstError = $false }
}
'@

            Set-Content -LiteralPath $inventoryPath -Value $inventoryContent -Encoding UTF8
            Set-Content -LiteralPath $playbookPath -Value $playbookContent -Encoding UTF8

            Import-OpsInventory -Path $inventoryPath | Out-Null

            $caughtMessage = $null
            try {
                Test-OpsPlaybook -Path $playbookPath | Out-Null
                throw 'Expected missing host reference error.'
            }
            catch {
                $caughtMessage = $_.Exception.Message
            }

            if ($caughtMessage -notmatch 'Référence d''hôte inexistante') {
                throw "Expected French missing host error, got: $caughtMessage"
            }
        }

        It 'detects missing playbook file' {
            $inventoryPath = Join-Path -Path $script:TestRoot -ChildPath 'inventory.valid.psd1'
            $inventoryContent = @'
@{
    Hosts = @(
        @{ Name='WEB01'; Address='192.168.1.20'; Transport='SSH'; OS='Ubuntu2404'; CredentialRef='web-root' }
    )
    Groups = @{ WebServers = @('WEB01') }
}
'@
            Set-Content -LiteralPath $inventoryPath -Value $inventoryContent -Encoding UTF8
            Import-OpsInventory -Path $inventoryPath | Out-Null

            $caughtMessage = $null
            try {
                Test-OpsPlaybook -Path (Join-Path -Path $script:TestRoot -ChildPath 'missing.psd1') | Out-Null
                throw 'Expected missing file error.'
            }
            catch {
                $caughtMessage = $_.Exception.Message
            }

            if ($caughtMessage -notmatch 'introuvable') {
                throw "Expected missing file error message, got: $caughtMessage"
            }
        }

        It 'detects syntax errors with line information' {
            $inventoryPath = Join-Path -Path $script:TestRoot -ChildPath 'inventory.valid.psd1'
            $playbookPath = Join-Path -Path $script:TestRoot -ChildPath 'playbook.syntax-error.psd1'

            $inventoryContent = @'
@{
    Hosts = @(
        @{ Name='WEB01'; Address='192.168.1.20'; Transport='SSH'; OS='Ubuntu2404'; CredentialRef='web-root' }
    )
    Groups = @{ WebServers = @('WEB01') }
}
'@

            $playbookContent = @'
@{
    Name = 'bad-playbook'
    Description = 'Syntax error'
    Targets = @(
        @{ Host='WEB01'; Roles=@('Linux-Nginx') }
    )
    Options = @{ ParallelHosts = 1; StopOnFirstError = $false
}
'@

            Set-Content -LiteralPath $inventoryPath -Value $inventoryContent -Encoding UTF8
            Set-Content -LiteralPath $playbookPath -Value $playbookContent -Encoding UTF8
            Import-OpsInventory -Path $inventoryPath | Out-Null

            $caughtMessage = $null
            try {
                Test-OpsPlaybook -Path $playbookPath | Out-Null
                throw 'Expected syntax error.'
            }
            catch {
                $caughtMessage = $_.Exception.Message
            }

            if ($caughtMessage -notmatch 'Erreur de syntaxe') {
                throw "Expected syntax error message, got: $caughtMessage"
            }

            if ($caughtMessage -notmatch 'ligne') {
                throw "Expected syntax error line information, got: $caughtMessage"
            }
        }

        It 'detects missing key, invalid type, missing reference and unsupported OS classes' {
            $playbookMissingKeyPath = Join-Path -Path $script:TestRoot -ChildPath 'playbook.missing-key.psd1'
            $playbookInvalidTypePath = Join-Path -Path $script:TestRoot -ChildPath 'playbook.invalid-type.psd1'
            $playbookMissingReferencePath = Join-Path -Path $script:TestRoot -ChildPath 'playbook.missing-reference.psd1'

            $playbookMissingKeyContent = @'
@{
    Name = 'missing-options'
    Description = 'missing options key'
    Targets = @(
        @{ Host='WEB01'; Roles=@('Linux-Nginx') }
    )
}
'@

            $playbookInvalidTypeContent = @'
@{
    Name = 'invalid-types'
    Description = 'invalid options type'
    Targets = @(
        @{ Host='WEB01'; Roles='Linux-Nginx' }
    )
    Options = @{ ParallelHosts = 'three'; StopOnFirstError = 'no' }
}
'@

            $playbookMissingReferenceContent = @'
@{
    Name = 'missing-reference'
    Description = 'unknown role and host'
    Targets = @(
        @{ Host='UNKNOWN01'; Roles=@('Role-Does-Not-Exist') }
    )
    Options = @{ ParallelHosts = 1; StopOnFirstError = $false }
}
'@

            Set-Content -LiteralPath $playbookMissingKeyPath -Value $playbookMissingKeyContent -Encoding UTF8
            Set-Content -LiteralPath $playbookInvalidTypePath -Value $playbookInvalidTypeContent -Encoding UTF8
            Set-Content -LiteralPath $playbookMissingReferencePath -Value $playbookMissingReferenceContent -Encoding UTF8

            $unsupportedInventory = @{
                Hosts  = @(
                    @{
                        Name          = 'WEB01'
                        Address       = '192.168.1.20'
                        Transport     = 'SSH'
                        OS            = 'UnknownOS999'
                        CredentialRef = 'web-root'
                    }
                )
                Groups = @{
                    WebServers = @('WEB01')
                }
            }

            $missingKeyResult = Test-OpsPlaybook -Path $playbookMissingKeyPath -InventoryData $unsupportedInventory -PassThru
            $invalidTypeResult = Test-OpsPlaybook -Path $playbookInvalidTypePath -InventoryData $unsupportedInventory -PassThru
            $missingReferenceResult = Test-OpsPlaybook -Path $playbookMissingReferencePath -InventoryData $unsupportedInventory -PassThru

            if ($missingKeyResult.IsValid) {
                throw 'Expected missing key result to be invalid.'
            }

            if ($invalidTypeResult.IsValid) {
                throw 'Expected invalid type result to be invalid.'
            }

            if ($missingReferenceResult.IsValid) {
                throw 'Expected missing reference result to be invalid.'
            }

            if ($missingKeyResult.ErrorClasses -notcontains 'missing_or_invalid_key') {
                throw "Expected missing_or_invalid_key class, got: $($missingKeyResult.ErrorClasses -join ', ')"
            }

            if ($invalidTypeResult.ErrorClasses -notcontains 'invalid_type') {
                throw "Expected invalid_type class, got: $($invalidTypeResult.ErrorClasses -join ', ')"
            }

            if ($missingReferenceResult.ErrorClasses -notcontains 'missing_reference') {
                throw "Expected missing_reference class, got: $($missingReferenceResult.ErrorClasses -join ', ')"
            }

            if ($missingReferenceResult.ErrorClasses -notcontains 'unsupported_os') {
                throw "Expected unsupported_os class, got: $($missingReferenceResult.ErrorClasses -join ', ')"
            }
        }
    }
}
