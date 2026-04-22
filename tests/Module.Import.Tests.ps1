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

    It 'exports Start-OpsToutatis command' {
        $module = Get-Module -Name OpsToutatis | Select-Object -First 1
        if ($null -eq $module) {
            throw 'Module is not loaded.'
        }

        $exportedCommands = @($module.ExportedCommands.Keys)
        if (@($exportedCommands).Count -ne 1) {
            throw "Expected exactly one exported command but found $(@($exportedCommands).Count)."
        }

        if ($exportedCommands[0] -ne 'Start-OpsToutatis') {
            throw "Expected Start-OpsToutatis to be exported but found '$($exportedCommands[0])'."
        }
    }
}
