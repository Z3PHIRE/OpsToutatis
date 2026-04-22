function Show-OpsProgress {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,

        [Parameter()]
        [string]$SubActivity = '',

        [Parameter()]
        [ValidateRange(0, 2147483647)]
        [int]$Current = 0,

        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int]$Total = 100,

        [Parameter()]
        [AllowNull()]
        [hashtable]$HostProgress,

        [Parameter()]
        [switch]$Plain,

        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [switch]$Ascii,

        [Parameter()]
        [switch]$PassThru
    )

    if (-not $PSCmdlet.ShouldProcess('terminal', 'Afficher la progression OpsToutatis')) {
        return $null
    }

    $capabilities = Get-OpsUICapabilities -Plain:$Plain -NonInteractive:$NonInteractive -Ascii:$Ascii
    $percent = 0
    if ($Total -gt 0) {
        $percent = [Math]::Round(($Current * 100.0) / $Total, 1)
    }

    if ($percent -lt 0) {
        $percent = 0
    }

    if ($percent -gt 100) {
        $percent = 100
    }

    $barWidth = 32
    $filledCount = [Math]::Round(($percent / 100.0) * $barWidth, 0)
    if ($filledCount -lt 0) {
        $filledCount = 0
    }

    if ($filledCount -gt $barWidth) {
        $filledCount = $barWidth
    }

    $emptyCount = $barWidth - $filledCount
    $bar = '[' + ('#' * $filledCount) + ('-' * $emptyCount) + ']'

    $progressLine = '{0} {1} {2}%' -f $Activity, $bar, $percent
    $subActivityLine = ''
    if (-not [string]::IsNullOrWhiteSpace($SubActivity)) {
        $subActivityLine = 'Sous-étape : ' + $SubActivity
    }

    $hostsLine = ''
    if ($null -ne $HostProgress -and @($HostProgress.Keys).Count -gt 0) {
        $hostSegments = @()
        foreach ($hostName in @($HostProgress.Keys | Sort-Object)) {
            $hostPercent = [int]$HostProgress[$hostName]
            if ($hostPercent -lt 0) {
                $hostPercent = 0
            }

            if ($hostPercent -gt 100) {
                $hostPercent = 100
            }

            $hostSegments += ('{0}:{1}%' -f $hostName, $hostPercent)
        }

        $hostsLine = 'Hôtes : ' + ($hostSegments -join '  ')
    }

    $renderLines = @($progressLine)
    if (-not [string]::IsNullOrWhiteSpace($subActivityLine)) {
        $renderLines += $subActivityLine
    }

    if (-not [string]::IsNullOrWhiteSpace($hostsLine)) {
        $renderLines += $hostsLine
    }

    $renderedText = [string]::Join([Environment]::NewLine, $renderLines)
    if ($PassThru.IsPresent) {
        return $renderedText
    }

    foreach ($line in @($renderLines)) {
        Write-OpsUI -Text $line -Color Accent -Plain:$capabilities.IsPlainMode -NonInteractive:$NonInteractive -Ascii:$Ascii | Out-Null
    }

    return $null
}
