function Test-Demo-HelloRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = Get-Demo-HelloEffectiveParameters -Target $Target -DesiredParameters $DesiredParameters
    $outputPath = [string]$effectiveParameters['OutputPath']
    $expectedContent = [string]$effectiveParameters['HelloText']

    $remoteState = Invoke-OpsRemote -Target $Target -ScriptBlock {
        param(
            [string]$TargetOutputPath
        )

        $directoryPath = Split-Path -Path $TargetOutputPath -Parent
        $directoryExists = $false
        if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
            $directoryExists = Test-Path -LiteralPath $directoryPath
        }

        $fileExists = Test-Path -LiteralPath $TargetOutputPath
        $currentContent = ''
        if ($fileExists) {
            $currentContent = Get-Content -LiteralPath $TargetOutputPath -Raw -ErrorAction Stop
            if ($null -eq $currentContent) {
                $currentContent = ''
            }
        }

        return [pscustomobject]@{
            DirectoryPath   = $directoryPath
            DirectoryExists = [bool]$directoryExists
            FileExists      = [bool]$fileExists
            CurrentContent  = [string]$currentContent
        }
    } -ArgumentList @($outputPath)

    $stateTable = ConvertTo-OpsPropertyTable -InputObject $remoteState
    $currentContent = [string]$stateTable['CurrentContent']
    $normalizedCurrentContent = $currentContent.TrimEnd("`r", "`n")
    $normalizedExpectedContent = $expectedContent.TrimEnd("`r", "`n")
    $isCompliant = ([bool]$stateTable['FileExists'] -and ($normalizedCurrentContent -eq $normalizedExpectedContent))

    return [pscustomobject]@{
        IsCompliant      = $isCompliant
        OutputPath       = $outputPath
        DirectoryPath    = [string]$stateTable['DirectoryPath']
        DirectoryExists  = [bool]$stateTable['DirectoryExists']
        FileExists       = [bool]$stateTable['FileExists']
        CurrentContent   = $currentContent
        ExpectedContent  = $expectedContent
    }
}
