function Test-DemoHelloRunningOnWindows {
    [CmdletBinding()]
    param()

    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Get-DemoHelloDefaultPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    $targetTable = ConvertTo-OpsPropertyTable -InputObject $Target
    $transportName = ''
    $osName = ''
    if ($null -ne $targetTable) {
        if ($targetTable.ContainsKey('Transport')) {
            $transportName = [string]$targetTable['Transport']
        }

        if ($targetTable.ContainsKey('OS')) {
            $osName = [string]$targetTable['OS']
        }
    }

    $isWindowsPath = $false
    if (-not [string]::IsNullOrWhiteSpace($osName) -and $osName -like 'Windows*') {
        $isWindowsPath = $true
    }
    elseif (-not [string]::IsNullOrWhiteSpace($transportName) -and $transportName -eq 'WinRM') {
        $isWindowsPath = $true
    }
    elseif (Test-DemoHelloRunningOnWindows) {
        $isWindowsPath = $true
    }

    if ($isWindowsPath) {
        $tempRoot = $env:TEMP
        if ([string]::IsNullOrWhiteSpace($tempRoot)) {
            $tempRoot = [System.IO.Path]::GetTempPath()
        }

        $demoDirectory = Join-Path -Path $tempRoot -ChildPath 'OpsToutatis'
        $demoDirectory = Join-Path -Path $demoDirectory -ChildPath 'Demo-Hello'
        return (Join-Path -Path $demoDirectory -ChildPath 'hello.txt')
    }

    return '/tmp/opstoutatis/demo-hello/hello.txt'
}

function Get-Demo-HelloEffectiveParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Target,

        [Parameter()]
        [AllowNull()]
        [hashtable]$DesiredParameters
    )

    $effectiveParameters = @{
        OutputPath = Get-DemoHelloDefaultPath -Target $Target
        HelloText  = 'Bonjour depuis OpsToutatis Demo-Hello.'
    }

    if ($null -ne $DesiredParameters) {
        foreach ($parameterKey in @($DesiredParameters.Keys)) {
            $effectiveParameters[$parameterKey] = $DesiredParameters[$parameterKey]
        }
    }

    return $effectiveParameters
}

function Get-Demo-HelloParameterSchema {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    $defaultOutputPath = Get-DemoHelloDefaultPath -Target $Target
    return @(
        @{
            Name                  = 'OutputPath'
            Label                 = 'Chemin du fichier hello.txt'
            Type                  = 'String'
            DefaultValue          = $defaultOutputPath
            HelpText              = 'Chemin cible utilisé pour créer le fichier de démonstration.'
            Validation            = '.+'
            ValidationDescription = 'Le chemin ne doit pas être vide.'
        }
        @{
            Name                  = 'HelloText'
            Label                 = 'Texte du fichier'
            Type                  = 'String'
            DefaultValue          = 'Bonjour depuis OpsToutatis Demo-Hello.'
            HelpText              = 'Contenu pédagogique écrit dans hello.txt pour vérifier le cycle Test/Plan/Apply/Verify.'
            Validation            = '.+'
            ValidationDescription = 'Le contenu ne doit pas être vide.'
        }
    )
}
