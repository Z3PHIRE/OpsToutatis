Set-StrictMode -Version Latest

Describe 'OpsToutatis module import' {
    BeforeAll {
        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
        $manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'

        if (-not (Test-Path -LiteralPath $manifestPath)) {
            throw "Manifest not found at '$manifestPath'."
        }
    }

    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    It 'imports without errors' {
        $importFailed = $false
        try {
            Import-Module -Name $manifestPath -Force -ErrorAction Stop
        }
        catch {
            $importFailed = $true
            throw "Module import failed: $($_.Exception.Message)"
        }

        if ($importFailed) {
            throw 'Module import failed.'
        }
    }

    It 'exports expected public commands' {
        $module = Get-Module -Name OpsToutatis | Select-Object -First 1
        if ($null -eq $module) {
            throw 'Module is not loaded.'
        }

        $exportedCommands = @($module.ExportedCommands.Keys)
        $expectedCommands = @(
            'Get-OpsTargetInfo',
            'Get-OpsCredential',
            'Import-OpsInventory',
            'Import-OpsPlaybook',
            'Invoke-OpsRemote',
            'Set-OpsCredential',
            'Start-OpsToutatis',
            'Test-OpsTarget',
            'Test-OpsInventory',
            'Test-OpsPlaybook'
        )

        $missingCommands = @()
        foreach ($expectedCommand in $expectedCommands) {
            if ($exportedCommands -notcontains $expectedCommand) {
                $missingCommands += $expectedCommand
            }
        }

        if (@($missingCommands).Count -gt 0) {
            throw "Missing exported command(s): $($missingCommands -join ', ')."
        }

        if (@($exportedCommands).Count -ne @($expectedCommands).Count) {
            throw "Expected $(@($expectedCommands).Count) exported commands but found $(@($exportedCommands).Count)."
        }
    }
}
