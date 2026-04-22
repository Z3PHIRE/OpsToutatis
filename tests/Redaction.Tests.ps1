Set-StrictMode -Version Latest
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'OpsToutatis redaction engine' {
    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    InModuleScope OpsToutatis {
        It 'returns empty string when input is empty' {
            $result = Format-OpsRedactedString -InputText ''
            if ($result -ne '') {
                throw "Expected empty output for empty input but got '$result'."
            }
        }

        It 'masks password assignment values' {
            $result = Format-OpsRedactedString -InputText 'password=MySecret123'
            if ($result -ne 'password=***REDACTED***') {
                throw "Unexpected redaction output: '$result'."
            }
        }

        It 'masks pwd assignment while preserving surrounding text' {
            $input = 'Connection failed: pwd="TopSecret!" for user ops'
            $result = Format-OpsRedactedString -InputText $input
            if ($result -notmatch 'pwd=\*\*\*REDACTED\*\*\*') {
                throw "Expected pwd value to be redacted but got '$result'."
            }

            if ($result -notmatch 'Connection failed:') {
                throw 'Expected non-secret prefix to remain unchanged.'
            }
        }

        It 'masks bearer token values' {
            $result = Format-OpsRedactedString -InputText 'Authorization: Bearer abcDEF123._-+/='
            if ($result -ne 'Authorization: Bearer ***REDACTED***') {
                throw "Unexpected bearer redaction output: '$result'."
            }
        }

        It 'masks JWT tokens' {
            $jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4iLCJpYXQiOjE1MTYyMzkwMjJ9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c'
            $result = Format-OpsRedactedString -InputText ("token=$jwt")
            if ($result -notmatch 'token=\*\*\*REDACTED\*\*\*') {
                throw "Expected JWT token to be redacted but got '$result'."
            }

            if ($result -match 'eyJ') {
                throw 'JWT token prefix should not be visible after redaction.'
            }
        }

        It 'masks private key blocks' {
            $input = @'
-----BEGIN PRIVATE KEY-----
ABC123DEF456
-----END PRIVATE KEY-----
'@
            $result = Format-OpsRedactedString -InputText $input
            if ($result -notmatch '\*\*\*REDACTED\*\*\*') {
                throw 'Expected private key block to be redacted.'
            }

            if ($result -match 'BEGIN PRIVATE KEY') {
                throw 'Private key marker should not remain in output.'
            }
        }

        It 'masks argument after -AsCredential' {
            $input = 'Invoke-Thing -AsCredential domain\user:SuperSecret!'
            $result = Format-OpsRedactedString -InputText $input
            if ($result -ne 'Invoke-Thing -AsCredential ***REDACTED***') {
                throw "Unexpected -AsCredential redaction output: '$result'."
            }
        }

        It 'does not alter regular sentence containing the word password' {
            $input = 'The password policy is strong and reviewed quarterly.'
            $result = Format-OpsRedactedString -InputText $input
            if ($result -ne $input) {
                throw "Expected sentence to remain unchanged but got '$result'."
            }
        }

        It 'masks multiple sensitive patterns in one line' {
            $input = 'password=OneSecret token=TwoSecret -password ThreeSecret'
            $result = Format-OpsRedactedString -InputText $input

            $redactedCount = ([regex]::Matches($result, '\*\*\*REDACTED\*\*\*')).Count
            if ($redactedCount -lt 3) {
                throw "Expected at least 3 redactions but found $redactedCount in '$result'."
            }

            if ($result -match 'OneSecret|TwoSecret|ThreeSecret') {
                throw 'Found clear-text secret after redaction.'
            }
        }
    }
}
