if (-not (Get-Variable -Name OpsTheme -Scope Script -ErrorAction SilentlyContinue)) {
    $escape = [char]27
    $script:OpsTheme = @{
        Reset      = "$escape[0m"
        Title      = "$escape[1;36m"
        Accent     = "$escape[36m"
        Text       = "$escape[37m"
        Subtle     = "$escape[90m"
        Success    = "$escape[32m"
        Warning    = "$escape[33m"
        Error      = "$escape[31m"
        Border     = "$escape[36m"
        Highlight  = "$escape[30;47m"
        Selection  = "$escape[30;46m"
    }
}

function ConvertTo-OpsUIHashtable {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [hashtable]) {
        return $InputObject
    }

    if ($InputObject -is [pscustomobject] -or $InputObject -is [System.Management.Automation.PSObject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = $property.Value
        }

        return $result
    }

    return $null
}

function Get-OpsPlainTextFromSecureString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureValue
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-OpsUICapabilities {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii
    )

    $supportsVirtualTerminal = $false
    $overrideSupport = Get-Variable -Name OpsUISupportsVTOverride -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $overrideSupport) {
        $supportsVirtualTerminal = [bool]$overrideSupport.Value
    }
    else {
        try {
            $uiObject = $Host.UI
            if ($null -ne $uiObject) {
                $supportsVTProperty = $uiObject.PSObject.Properties['SupportsVirtualTerminal']
                if ($null -ne $supportsVTProperty) {
                    $supportsVirtualTerminal = [bool]$supportsVTProperty.Value
                }
            }
        }
        catch {
            $supportsVirtualTerminal = $false
        }
    }

    $inputRedirected = $false
    $overrideInput = Get-Variable -Name OpsUIInputRedirectedOverride -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $overrideInput) {
        $inputRedirected = [bool]$overrideInput.Value
    }
    else {
        try {
            $inputRedirected = [Console]::IsInputRedirected
        }
        catch {
            $inputRedirected = $false
        }
    }

    $outputRedirected = $false
    $overrideOutput = Get-Variable -Name OpsUIOutputRedirectedOverride -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $overrideOutput) {
        $outputRedirected = [bool]$overrideOutput.Value
    }
    else {
        try {
            $outputRedirected = [Console]::IsOutputRedirected
        }
        catch {
            $outputRedirected = $false
        }
    }

    $userInteractive = $true
    $overrideInteractive = Get-Variable -Name OpsUIUserInteractiveOverride -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $overrideInteractive) {
        $userInteractive = [bool]$overrideInteractive.Value
    }
    else {
        try {
            $userInteractive = [Environment]::UserInteractive
        }
        catch {
            $userInteractive = $true
        }
    }

    $hostName = 'UnknownHost'
    try {
        if ($null -ne $Host -and -not [string]::IsNullOrWhiteSpace($Host.Name)) {
            $hostName = [string]$Host.Name
        }
    }
    catch {
        $hostName = 'UnknownHost'
    }

    $noColor = $false
    if ($env:NO_COLOR) {
        $noColor = ($env:NO_COLOR.Trim().Length -gt 0)
    }

    $isTty = (-not $inputRedirected) -and (-not $outputRedirected)
    $isInteractive = $isTty -and $userInteractive -and (-not $NonInteractive.IsPresent)
    $isPlainMode = $Plain.IsPresent -or $noColor -or (-not $supportsVirtualTerminal) -or (-not $isInteractive)

    return [pscustomobject]@{
        HostName                = $hostName
        SupportsVirtualTerminal = $supportsVirtualTerminal
        NoColor                 = $noColor
        IsInputRedirected       = $inputRedirected
        IsOutputRedirected      = $outputRedirected
        IsInteractive           = $isInteractive
        IsPlainMode             = $isPlainMode
        UseAscii                = $Ascii.IsPresent
    }
}

function Get-OpsUISymbolSet {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Ascii
    )

    if ($Ascii.IsPresent) {
        return @{
            TopLeft       = '+'
            TopRight      = '+'
            BottomLeft    = '+'
            BottomRight   = '+'
            Horizontal    = '-'
            Vertical      = '|'
            JunctionLeft  = '+'
            JunctionRight = '+'
            Branch        = '|-- '
            LastBranch    = '`-- '
            Stem          = '|   '
            Gap           = '    '
            Selected      = '>'
            Checked       = '[x]'
            Unchecked     = '[ ]'
        }
    }

    return @{
        TopLeft       = [char]0x250C
        TopRight      = [char]0x2510
        BottomLeft    = [char]0x2514
        BottomRight   = [char]0x2518
        Horizontal    = [char]0x2500
        Vertical      = [char]0x2502
        JunctionLeft  = [char]0x251C
        JunctionRight = [char]0x2524
        Branch        = ([char]0x251C + [char]0x2500 + ' ')
        LastBranch    = ([char]0x2514 + [char]0x2500 + ' ')
        Stem          = ([char]0x2502 + '  ')
        Gap           = '   '
        Selected      = [char]0x25B6
        Checked       = '[x]'
        Unchecked     = '[ ]'
    }
}
