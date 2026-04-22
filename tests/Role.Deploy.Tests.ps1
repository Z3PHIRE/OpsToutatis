Set-StrictMode -Version Latest
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'OpsToutatis role orchestration engine' {
    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    InModuleScope OpsToutatis {
        $script:RoleTestRoot = $null
        $script:RiskyRolePath = $null

        BeforeEach {
            if ($null -ne (Get-OpsSession)) {
                Close-OpsSession | Out-Null
            }

            $script:RoleTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('OpsToutatisRoleTests-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:RoleTestRoot -Force | Out-Null
        }

        AfterEach {
            if ($null -ne (Get-OpsSession)) {
                Close-OpsSession | Out-Null
            }

            if (-not [string]::IsNullOrWhiteSpace($script:RiskyRolePath) -and (Test-Path -LiteralPath $script:RiskyRolePath)) {
                Remove-Item -LiteralPath $script:RiskyRolePath -Recurse -Force
                $script:RiskyRolePath = $null
            }

            if ($script:OpsRoleCache.ContainsKey('demo-riskytemp')) {
                $script:OpsRoleCache.Remove('demo-riskytemp') | Out-Null
            }

            if (Test-Path -LiteralPath $script:RoleTestRoot) {
                Remove-Item -LiteralPath $script:RoleTestRoot -Recurse -Force
            }
        }

        It 'runs complete deployment cycle for Demo-Hello role on Local target' {
            $session = New-OpsSession -BasePath $script:RoleTestRoot
            if ($null -eq $session) {
                throw 'Expected an active session.'
            }

            $target = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }

            $outputPath = Join-Path -Path $script:RoleTestRoot -ChildPath 'demo-hello'
            $outputPath = Join-Path -Path $outputPath -ChildPath 'hello.txt'
            $desiredParameters = @{
                OutputPath = $outputPath
                HelloText  = 'Hello from role test.'
            }

            $deployResult = Invoke-OpsDeploy -Role 'Demo-Hello' -Target $target -DesiredParameters $desiredParameters -PassThru -Confirm:$false
            if (-not $deployResult.ApplyPerformed) {
                throw 'Expected ApplyPerformed to be true for first deployment.'
            }

            if (-not $deployResult.VerifyPassed) {
                throw 'Expected VerifyPassed to be true for first deployment.'
            }

            if (-not (Test-Path -LiteralPath $outputPath)) {
                throw "Expected output file '$outputPath' to exist."
            }

            $outputContent = Get-Content -LiteralPath $outputPath -Raw
            if ($outputContent -notmatch 'Hello from role test\.') {
                throw "Unexpected output content: '$outputContent'"
            }

            $actionsLogContent = Get-Content -LiteralPath $session.ActionsLogPath -Raw
            if ($actionsLogContent -notmatch 'Demo-Hello action:') {
                throw "Expected Demo-Hello actions to be logged in actions.log, got: $actionsLogContent"
            }
        }

        It 'is idempotent on second execution for Demo-Hello role' {
            New-OpsSession -BasePath $script:RoleTestRoot | Out-Null

            $target = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }

            $outputPath = Join-Path -Path $script:RoleTestRoot -ChildPath 'demo-hello'
            $outputPath = Join-Path -Path $outputPath -ChildPath 'hello.txt'
            $desiredParameters = @{
                OutputPath = $outputPath
                HelloText  = 'Hello from idempotence test.'
            }

            Invoke-OpsDeploy -Role 'Demo-Hello' -Target $target -DesiredParameters $desiredParameters -PassThru -Confirm:$false | Out-Null
            $secondRunResult = Invoke-OpsDeploy -Role 'Demo-Hello' -Target $target -DesiredParameters $desiredParameters -PassThru -Confirm:$false

            if ($secondRunResult.ApplyPerformed) {
                throw 'Expected ApplyPerformed to be false on second idempotent run.'
            }

            if (-not $secondRunResult.VerifyPassed) {
                throw 'Expected VerifyPassed to remain true on idempotent run.'
            }

            if (@($secondRunResult.PlanActions).Count -ne 0) {
                throw "Expected no plan actions on idempotent run, got $(@($secondRunResult.PlanActions).Count)."
            }

            if ([string]$secondRunResult.Message -ne 'État déjà conforme.') {
                throw "Expected message 'État déjà conforme.', got '$($secondRunResult.Message)'."
            }
        }

        It 'refuses High risk role deployment without explicit confirmation' {
            New-OpsSession -BasePath $script:RoleTestRoot | Out-Null

            $rolesRootPath = Get-OpsRolesRootPath
            $script:RiskyRolePath = Join-Path -Path $rolesRootPath -ChildPath 'Demo-RiskyTemp'
            New-Item -ItemType Directory -Path $script:RiskyRolePath -Force | Out-Null

            Set-Content -LiteralPath (Join-Path -Path $script:RiskyRolePath -ChildPath 'role.psd1') -Encoding UTF8 -Value @'
@{
    Id = 'Demo-RiskyTemp'
    DisplayName = 'Démo risquée temporaire'
    Category = 'Demo/Risk'
    SupportedOS = @('Windows','Linux')
    Requires = @()
    Conflicts = @()
    RiskLevel = 'High'
    DestructivePotential = $true
    EstimatedDurationMin = 1
}
'@

            Set-Content -LiteralPath (Join-Path -Path $script:RiskyRolePath -ChildPath 'Test.ps1') -Encoding UTF8 -Value @'
function Test-Demo-RiskyTempRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,
        [Parameter()]
        [hashtable]$DesiredParameters
    )

    return [pscustomobject]@{
        IsCompliant = $false
    }
}
'@

            Set-Content -LiteralPath (Join-Path -Path $script:RiskyRolePath -ChildPath 'Plan.ps1') -Encoding UTF8 -Value @'
function Get-Demo-RiskyTempPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,
        [Parameter(Mandatory = $true)]
        [object]$CurrentState,
        [Parameter()]
        [hashtable]$DesiredParameters
    )

    return [pscustomobject]@{
        Summary = 'One risky action'
        Actions = @(
            [pscustomobject]@{
                Type  = 'DangerousAction'
                Label = 'Action risquée de test'
                Data  = @{}
            }
        )
    }
}
'@

            Set-Content -LiteralPath (Join-Path -Path $script:RiskyRolePath -ChildPath 'Apply.ps1') -Encoding UTF8 -Value @'
function Invoke-Demo-RiskyTempApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,
        [Parameter(Mandatory = $true)]
        [object[]]$PlanActions,
        [Parameter()]
        [hashtable]$DesiredParameters,
        [Parameter()]
        [object]$CurrentState
    )

    return [pscustomobject]@{
        AppliedActionCount = @($PlanActions).Count
    }
}
'@

            Set-Content -LiteralPath (Join-Path -Path $script:RiskyRolePath -ChildPath 'Verify.ps1') -Encoding UTF8 -Value @'
function Test-Demo-RiskyTempApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,
        [Parameter()]
        [hashtable]$DesiredParameters,
        [Parameter()]
        [object]$CurrentState,
        [Parameter()]
        [object]$ApplyResult
    )

    return [pscustomobject]@{
        IsCompliant = $true
        Message     = 'OK'
    }
}
'@

            Set-Content -LiteralPath (Join-Path -Path $script:RiskyRolePath -ChildPath 'Parameters.ps1') -Encoding UTF8 -Value @'
function Get-Demo-RiskyTempParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Target
    )

    return @()
}
'@

            $target = @{
                Name      = 'LOCALHOST'
                Address   = '127.0.0.1'
                Transport = 'Local'
            }

            $errorMessage = $null
            try {
                Invoke-OpsDeploy -Role 'Demo-RiskyTemp' -Target $target -DesiredParameters @{} -NonInteractive -Confirm:$false | Out-Null
                throw 'Expected high risk deployment to be refused without explicit confirmation.'
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            if ($errorMessage -notmatch 'Confirmation explicite absente') {
                throw "Expected explicit confirmation refusal, got: $errorMessage"
            }
        }
    }
}
