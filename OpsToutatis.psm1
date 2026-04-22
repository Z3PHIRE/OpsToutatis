Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$sourceRoot = Join-Path -Path $moduleRoot -ChildPath 'src'
$publicPath = Join-Path -Path $sourceRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $sourceRoot -ChildPath 'Private'
$transportPath = Join-Path -Path $sourceRoot -ChildPath 'Transport'

$publicScripts = @()
$privateScripts = @()
$transportScripts = @()

if (Test-Path -LiteralPath $publicPath) {
    $publicScripts = @(
        Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File -Recurse |
            Sort-Object -Property FullName
    )
}

if (Test-Path -LiteralPath $privatePath) {
    $privateScripts = @(
        Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File -Recurse |
            Sort-Object -Property FullName
    )
}

if (Test-Path -LiteralPath $transportPath) {
    $transportScripts = @(
        Get-ChildItem -LiteralPath $transportPath -Filter '*.ps1' -File -Recurse |
            Sort-Object -Property FullName
    )
}

$scriptsToLoad = @($privateScripts + $transportScripts + $publicScripts)
foreach ($scriptItem in $scriptsToLoad) {
    try {
        . $scriptItem.FullName
    }
    catch {
        throw "Failed to load script '$($scriptItem.FullName)'. Error: $($_.Exception.Message)"
    }
}

$publicFunctionNames = @()
foreach ($scriptItem in $publicScripts) {
    $tokens = $null
    $parserErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptItem.FullName,
        [ref]$tokens,
        [ref]$parserErrors
    )

    if (@($parserErrors).Count -gt 0) {
        $errorMessages = @($parserErrors | ForEach-Object { $_.Message }) -join '; '
        throw "Unable to parse '$($scriptItem.FullName)'. Errors: $errorMessages"
    }

    $functionAsts = @(
        $scriptAst.FindAll(
            {
                param($astNode)
                $astNode -is [System.Management.Automation.Language.FunctionDefinitionAst]
            },
            $false
        )
    )

    foreach ($functionAst in $functionAsts) {
        if (-not [string]::IsNullOrWhiteSpace($functionAst.Name)) {
            $publicFunctionNames += $functionAst.Name
        }
    }
}

$publicFunctionNames = @($publicFunctionNames | Sort-Object -Unique)
Export-ModuleMember -Function $publicFunctionNames -Alias @()
