[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Repository = 'Z3PHIRE/OpsToutatis',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Tag,

    [Parameter()]
    [switch]$ForceReinstall,

    [Parameter()]
    [string]$ConfirmKeyword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Allowed outbound network hosts:
# - api.github.com (release metadata)
# - github.com / objects.githubusercontent.com (release archive download)

function Invoke-WebDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile
    )

    $downloadParameters = @{
        Uri     = $Uri
        OutFile = $OutFile
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $downloadParameters.UseBasicParsing = $true
    }

    Invoke-WebRequest @downloadParameters
}

function Get-ReleaseMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Repo,

        [Parameter()]
        [string]$ReleaseTag
    )

    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $releaseEndpoint = "https://api.github.com/repos/$Repo/releases/latest"
    }
    else {
        $releaseEndpoint = "https://api.github.com/repos/$Repo/releases/tags/$ReleaseTag"
    }

    $headers = @{
        'Accept'     = 'application/vnd.github+json'
        'User-Agent' = 'OpsToutatis-Installer'
    }

    return Invoke-RestMethod -Method Get -Uri $releaseEndpoint -Headers $headers
}

function Get-ModuleSourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExtractPath
    )

    $manifestPath = Get-ChildItem -LiteralPath $ExtractPath -Filter 'OpsToutatis.psd1' -File -Recurse |
        Select-Object -First 1 -ExpandProperty FullName

    if ([string]::IsNullOrWhiteSpace($manifestPath)) {
        throw "Impossible de localiser le manifest OpsToutatis.psd1 dans l'archive téléchargée."
    }

    return [System.IO.Path]::GetFullPath((Split-Path -Path $manifestPath -Parent))
}

$release = Get-ReleaseMetadata -Repo $Repository -ReleaseTag $Tag
if ([string]::IsNullOrWhiteSpace($release.tag_name)) {
    throw "La release GitHub ne contient pas de tag exploitable. L'installation est annulée."
}

$downloadUrl = $null
$zipAsset = @($release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1)
if (@($zipAsset).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($zipAsset[0].browser_download_url)) {
    $downloadUrl = $zipAsset[0].browser_download_url
}
elseif (-not [string]::IsNullOrWhiteSpace($release.zipball_url)) {
    $downloadUrl = $release.zipball_url
}

if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    throw "Aucune archive ZIP de release n'a été trouvée pour le tag '$($release.tag_name)'."
}

$tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OpsToutatisInstall-" + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path -Path $tempRoot -ChildPath 'OpsToutatis.zip'
$extractPath = Join-Path -Path $tempRoot -ChildPath 'Extracted'
$moduleInstallPath = Join-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath 'Documents\PowerShell\Modules') -ChildPath 'OpsToutatis'

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

try {
    Write-Host "Téléchargement de la release taguée $($release.tag_name) depuis GitHub..."
    Invoke-WebDownload -Uri $downloadUrl -OutFile $archivePath

    Write-Host "Extraction de l'archive..."
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

    $moduleSourcePath = Get-ModuleSourcePath -ExtractPath $extractPath

    if (Test-Path -LiteralPath $moduleInstallPath) {
        if (-not $ForceReinstall.IsPresent) {
            throw "Une installation existe déjà dans '$moduleInstallPath'. Relancez avec -ForceReinstall et -ConfirmKeyword REINSTALL."
        }

        if ($ConfirmKeyword -ne 'REINSTALL') {
            throw "Confirmation explicite requise. Relancez avec -ConfirmKeyword REINSTALL pour remplacer l'installation existante."
        }

        Remove-Item -LiteralPath $moduleInstallPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $moduleInstallPath -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $moduleSourcePath -ChildPath '*') -Destination $moduleInstallPath -Recurse -Force

    Write-Host "Installation terminée dans : $moduleInstallPath"
    Write-Host "Pour démarrer l'interface, ouvrez une nouvelle session PowerShell puis exécutez :"
    Write-Host "Import-Module OpsToutatis -Force"
    Write-Host "Start-OpsToutatis"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
