Set-StrictMode -Version Latest

Describe 'OpsToutatis UI engine' {
    BeforeAll {
        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
        $uiRoot = Join-Path -Path $projectRoot -ChildPath 'src'
        $uiRoot = Join-Path -Path $uiRoot -ChildPath 'UI'

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
            . (Join-Path -Path $uiRoot -ChildPath $uiFile)
        }
    }

    AfterEach {
        foreach ($overrideName in @(
            'OpsUISupportsVTOverride',
            'OpsUIInputRedirectedOverride',
            'OpsUIOutputRedirectedOverride',
            'OpsUIUserInteractiveOverride'
        )) {
            if (Get-Variable -Name $overrideName -Scope Script -ErrorAction SilentlyContinue) {
                Remove-Variable -Name $overrideName -Scope Script -Force
            }
        }
    }

    It 'keeps plain banner rendering stable (golden file)' {
        $rendered = Write-OpsBanner -Title 'OpsToutatis' -Subtitle 'Mode plain' -Plain -Ascii -Width 40 -PassThru
        $captured = ($rendered | Out-String)
        $normalizedCaptured = ($captured -replace "`r`n", "`n").TrimEnd("`n")

        $goldenPath = Join-Path -Path $PSScriptRoot -ChildPath 'golden'
        $goldenPath = Join-Path -Path $goldenPath -ChildPath 'ui-plain-banner.txt'
        $golden = Get-Content -LiteralPath $goldenPath -Raw
        $normalizedGolden = ($golden -replace "`r`n", "`n").TrimEnd("`n")

        if ($normalizedCaptured -ne $normalizedGolden) {
            throw "Plain banner rendering changed.`nExpected:`n$normalizedGolden`nActual:`n$normalizedCaptured"
        }
    }

    It 'falls back to plain mode when virtual terminal support is disabled' {
        $script:OpsUISupportsVTOverride = $false
        $script:OpsUIInputRedirectedOverride = $false
        $script:OpsUIOutputRedirectedOverride = $false
        $script:OpsUIUserInteractiveOverride = $true

        $capabilities = Get-OpsUICapabilities
        if (-not $capabilities.IsPlainMode) {
            throw 'Expected plain mode fallback when SupportsVirtualTerminal is false.'
        }

        $selection = Show-OpsMenu -Title 'Fallback test' -Items @(
            @{ Id = 'one'; Label = 'One'; Description = 'Premier' }
            @{ Id = 'two'; Label = 'Two'; Description = 'Second' }
        ) -DefaultIndex 1 -NonInteractive -Ascii

        if ($selection.Id -ne 'two') {
            throw "Expected default selection 'two' in non-interactive fallback, got '$($selection.Id)'."
        }
    }
}
