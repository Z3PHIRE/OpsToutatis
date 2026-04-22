Set-StrictMode -Version Latest
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'OpsToutatis session and logger engine' {
    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    InModuleScope OpsToutatis {
        $script:TestBasePath = $null

        BeforeEach {
            if ($null -ne (Get-OpsSession)) {
                Close-OpsSession | Out-Null
            }

            $script:TestBasePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('OpsToutatisTests-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TestBasePath -Force | Out-Null
            Push-Location -LiteralPath $script:TestBasePath
        }

        AfterEach {
            if ($null -ne (Get-OpsSession)) {
                Close-OpsSession | Out-Null
            }

            Pop-Location

            if (Test-Path -LiteralPath $script:TestBasePath) {
                Remove-Item -LiteralPath $script:TestBasePath -Recurse -Force
            }
        }

        It 'creates expected session directory and log files' {
            $session = New-OpsSession
            if ($null -eq $session) {
                throw 'Expected a session object but got null.'
            }

            if (-not (Test-Path -LiteralPath $session.SessionPath)) {
                throw "Expected session path '$($session.SessionPath)' to exist."
            }

            $sessionDirectoryName = Split-Path -Path $session.SessionPath -Leaf
            if ($sessionDirectoryName -notmatch '^\d{8}-\d{6}-[a-f0-9]{8}$') {
                throw "Session directory name '$sessionDirectoryName' does not match expected format."
            }

            $expectedFiles = @(
                $session.SessionLogPath,
                $session.ActionsLogPath,
                $session.DecisionsLogPath,
                $session.ErrorsLogPath,
                $session.TranscriptLogPath
            )

            foreach ($expectedFile in $expectedFiles) {
                if (-not (Test-Path -LiteralPath $expectedFile)) {
                    throw "Expected log file '$expectedFile' to exist."
                }
            }
        }

        It 'does not write logs to console without PassThru' {
            New-OpsSession | Out-Null

            $output = Write-OpsLog -Level Info -Message 'Console should stay silent.'
            if ($null -ne $output) {
                throw "Expected no console output but got '$output'."
            }
        }

        It 'never writes clear-text password in log files' {
            $session = New-OpsSession
            $secretValue = 'UltraSensitive-Password-42'
            Write-OpsLog -Level Error -Message ("Deployment failed with password=$secretValue and token=eyJheader.payload.signature")

            $sessionContent = Get-Content -LiteralPath $session.SessionLogPath -Raw
            $errorsContent = Get-Content -LiteralPath $session.ErrorsLogPath -Raw

            if ($sessionContent -match [regex]::Escape($secretValue)) {
                throw 'Found clear-text secret in session.log.'
            }

            if ($errorsContent -match [regex]::Escape($secretValue)) {
                throw 'Found clear-text secret in errors.log.'
            }

            if ($sessionContent -notmatch '\*\*\*REDACTED\*\*\*') {
                throw 'Expected redaction marker in session.log.'
            }
        }

        It 'writes close summary with counters and duration' {
            $session = New-OpsSession

            Write-OpsLog -Level Action -Message 'Action one.' | Out-Null
            Write-OpsLog -Level Decision -Message 'Decision one.' | Out-Null
            Write-OpsLog -Level Error -Message 'Error one.' | Out-Null

            $closedSession = Close-OpsSession
            if ($null -eq $closedSession) {
                throw 'Expected closed session details but got null.'
            }

            $sessionContent = Get-Content -LiteralPath $session.SessionLogPath -Raw
            if ($sessionContent -notmatch 'Session summary: actions=1; decisions=1; errors=1; durationSeconds=') {
                throw "Expected close summary entry, got '$sessionContent'."
            }

            if ($null -ne (Get-OpsSession)) {
                throw 'Expected no active session after closing.'
            }
        }
    }
}
