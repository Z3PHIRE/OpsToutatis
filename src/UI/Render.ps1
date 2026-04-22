function Get-OpsUIConsoleWidth {
    [CmdletBinding()]
    param()

    $width = 80
    try {
        if ([Console]::WindowWidth -gt 0) {
            $width = [Console]::WindowWidth
        }
    }
    catch {
        try {
            if ($Host.UI.RawUI.WindowSize.Width -gt 0) {
                $width = $Host.UI.RawUI.WindowSize.Width
            }
        }
        catch {
            $width = 80
        }
    }

    if ($width -lt 20) {
        $width = 20
    }

    return $width
}

function Write-OpsUI {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Color = 'Text',

        [Parameter()]
        [switch]$NoNewLine,

        [Parameter()]
        [int]$Row = -1,

        [Parameter()]
        [int]$Column = -1,

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii,

        [Parameter()]
        [switch]$PassThru
    )

    $capabilities = Get-OpsUICapabilities -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Render OpsToutatis UI text')) {
        return $null
    }

    $plainText = $Text
    if ($capabilities.IsPlainMode) {
        if ($PassThru.IsPresent) {
            return $plainText
        }

        if ($NoNewLine.IsPresent) {
            [Console]::Write($plainText)
        }
        else {
            [Console]::WriteLine($plainText)
        }

        return $null
    }

    $escape = [char]27
    $positionSequence = ''
    if ($Row -ge 1 -and $Column -ge 1) {
        $positionSequence = "$escape[$Row;${Column}H"
    }

    $colorSequence = ''
    if ($script:OpsTheme.ContainsKey($Color)) {
        $colorSequence = [string]$script:OpsTheme[$Color]
    }
    else {
        $colorSequence = [string]$script:OpsTheme['Text']
    }

    $renderedText = $positionSequence + $colorSequence + $plainText + $script:OpsTheme.Reset
    if ($PassThru.IsPresent) {
        return $renderedText
    }

    if ($NoNewLine.IsPresent) {
        [Console]::Write($renderedText)
    }
    else {
        [Console]::WriteLine($renderedText)
    }

    return $null
}

function Write-OpsBox {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [string]$Title = '',

        [Parameter()]
        [AllowNull()]
        [string[]]$ContentLines = @(),

        [Parameter()]
        [ValidateRange(20, 300)]
        [int]$Width = 72,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Color = 'Text',

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii,

        [Parameter()]
        [switch]$PassThru
    )

    $capabilities = Get-OpsUICapabilities -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii
    $symbols = Get-OpsUISymbolSet -Ascii:($Ascii -or $capabilities.UseAscii)

    $safeWidth = $Width
    $consoleWidth = Get-OpsUIConsoleWidth
    if ($safeWidth -gt $consoleWidth) {
        $safeWidth = $consoleWidth
    }

    if ($safeWidth -lt 20) {
        $safeWidth = 20
    }

    $innerWidth = $safeWidth - 2

    $renderLines = @()
    $titleText = $Title
    if ([string]::IsNullOrWhiteSpace($titleText)) {
        $renderLines += ($symbols.TopLeft + ($symbols.Horizontal * $innerWidth) + $symbols.TopRight)
    }
    else {
        $titleBlock = (' ' + $titleText + ' ')
        if ($titleBlock.Length -gt $innerWidth) {
            $titleBlock = $titleBlock.Substring(0, $innerWidth)
        }

        $remaining = $innerWidth - $titleBlock.Length
        $renderLines += ($symbols.TopLeft + $titleBlock + ($symbols.Horizontal * $remaining) + $symbols.TopRight)
    }

    $normalizedContent = @()
    foreach ($contentLine in @($ContentLines)) {
        if ($null -eq $contentLine) {
            $normalizedContent += ''
            continue
        }

        $splitLines = @($contentLine -split "`r?`n")
        if (@($splitLines).Count -eq 0) {
            $normalizedContent += ''
        }
        else {
            $normalizedContent += @($splitLines)
        }
    }

    if (@($normalizedContent).Count -eq 0) {
        $normalizedContent = @('')
    }

    foreach ($line in @($normalizedContent)) {
        $lineText = [string]$line
        if ($lineText.Length -gt $innerWidth) {
            $lineText = $lineText.Substring(0, $innerWidth)
        }

        $renderLines += ($symbols.Vertical + $lineText.PadRight($innerWidth) + $symbols.Vertical)
    }

    $renderLines += ($symbols.BottomLeft + ($symbols.Horizontal * $innerWidth) + $symbols.BottomRight)

    $renderedText = [string]::Join([Environment]::NewLine, $renderLines)
    if ($PassThru.IsPresent) {
        return $renderedText
    }

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Render OpsToutatis UI box')) {
        return $null
    }

    foreach ($renderLine in @($renderLines)) {
        Write-OpsUI -Text $renderLine -Color $Color -Plain:$capabilities.IsPlainMode -Ascii:($Ascii -or $capabilities.UseAscii) | Out-Null
    }

    return $null
}

function Write-OpsBanner {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter()]
        [string]$Subtitle,

        [Parameter()]
        [ValidateRange(20, 300)]
        [int]$Width = 72,

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii,

        [Parameter()]
        [switch]$PassThru
    )

    $content = @()
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        $content += $Subtitle
    }

    if ($PassThru.IsPresent) {
        return Write-OpsBox -Title $Title -ContentLines $content -Width $Width -Color Border -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii -PassThru
    }

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Render OpsToutatis banner')) {
        return $null
    }

    Write-OpsBox -Title $Title -ContentLines $content -Width $Width -Color Border -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii | Out-Null
    return $null
}
