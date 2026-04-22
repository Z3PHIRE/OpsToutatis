Set-StrictMode -Version Latest
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'OpsToutatis.psd1'
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'OpsToutatis credential wrapper' {
    AfterAll {
        Remove-Module -Name OpsToutatis -ErrorAction SilentlyContinue
    }

    InModuleScope OpsToutatis {
        It 'returns a pedagogical warning without throwing when SecretManagement is unavailable' {
            Mock -CommandName Initialize-OpsSecretVault -MockWith {
                return [pscustomobject]@{
                    Success = $false
                    Message = "Le module SecretManagement n'est pas disponible. Installez-le avec : Install-Module Microsoft.PowerShell.SecretManagement,Microsoft.PowerShell.SecretStore -Scope CurrentUser."
                }
            }

            $warningMessages = $null
            $secret = ConvertTo-SecureString -String 'TemporarySecret!123' -AsPlainText -Force
            $setResult = Set-OpsCredential -Name 'ops-missing-module-test' -Secret $secret -WarningVariable warningMessages -WarningAction Continue -Confirm:$false

            if ($setResult -ne $false) {
                throw "Expected Set-OpsCredential to return false when SecretManagement is unavailable, got '$setResult'."
            }

            $warningText = @($warningMessages) -join ' '
            if ($warningText -notmatch 'Installez-le') {
                throw "Expected pedagogical installation warning, got: $warningText"
            }
        }

        It 'supports Set/Get credential round-trip with SecureString' {
            $secretName = 'ops-cred-' + [guid]::NewGuid().ToString('N')
            $plainSecret = 'RoundTrip-Secret-123!'
            $secureSecret = ConvertTo-SecureString -String $plainSecret -AsPlainText -Force

            $setResult = Set-OpsCredential -Name $secretName -Secret $secureSecret -Confirm:$false
            if (-not $setResult) {
                Set-ItResult -Skipped -Because "SecretManagement n'est pas disponible ou non configuré dans cet environnement."
                return
            }

            $retrievedSecret = Get-OpsCredential -Name $secretName -Confirm:$false
            if ($null -eq $retrievedSecret) {
                throw "Expected Get-OpsCredential to return a value for '$secretName'."
            }

            if (-not ($retrievedSecret -is [SecureString])) {
                throw "Expected a SecureString result but got '$($retrievedSecret.GetType().FullName)'."
            }

            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrievedSecret)
            try {
                $retrievedPlainText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }

            if ($retrievedPlainText -ne $plainSecret) {
                throw "Round-trip mismatch for '$secretName'."
            }

            if (Get-Command -Name Remove-Secret -ErrorAction SilentlyContinue) {
                Remove-Secret -Name $secretName -Vault 'OpsToutatisVault' -ErrorAction SilentlyContinue
            }
        }
    }
}
