function Format-OpsRedactedString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$InputText
    )

    if ($null -eq $InputText) {
        return $null
    }

    $redactedText = [string]$InputText
    $redactionToken = '***REDACTED***'

    # Private key blocks
    $redactedText = [regex]::Replace(
        $redactedText,
        '(?is)-----BEGIN[\s\S]*?-----END[\s\S]*?-----',
        $redactionToken
    )

    # Authorization bearer values
    $redactedText = [regex]::Replace(
        $redactedText,
        '(?i)\bBearer\s+([A-Za-z0-9\-\._~\+\/]+=*)',
        {
            param($match)
            return 'Bearer ' + $redactionToken
        }
    )

    # JWT-like tokens
    $redactedText = [regex]::Replace(
        $redactedText,
        '(?<![A-Za-z0-9_-])(eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,})(?![A-Za-z0-9_-])',
        $redactionToken
    )

    # Key-value style secrets
    $redactedText = [regex]::Replace(
        $redactedText,
        '(?i)\b(password|pwd|passphrase|secret|token|api[-_]?key)\s*=\s*("[^"]*"|''[^'']*''|[^;\s,]+)',
        {
            param($match)
            return $match.Groups[1].Value + '=' + $redactionToken
        }
    )

    # Parameter style secrets
    $redactedText = [regex]::Replace(
        $redactedText,
        '(?i)(-(?:password|pwd)\s+)("[^"]*"|''[^'']*''|\S+)',
        {
            param($match)
            return $match.Groups[1].Value + $redactionToken
        }
    )

    # AsCredential next argument
    $redactedText = [regex]::Replace(
        $redactedText,
        '(?i)(-ascredential\s+)("[^"]*"|''[^'']*''|\S+)',
        {
            param($match)
            return $match.Groups[1].Value + $redactionToken
        }
    )

    return $redactedText
}
