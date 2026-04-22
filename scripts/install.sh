#!/usr/bin/env bash
set -euo pipefail

# Allowed outbound network hosts:
# - api.github.com (release metadata)
# - github.com / objects.githubusercontent.com (release archive download)

repository="Z3PHIRE/OpsToutatis"
tag=""
force_reinstall="false"
confirm_keyword=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repository="${2:-}"
      shift 2
      ;;
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --force-reinstall)
      force_reinstall="true"
      shift
      ;;
    --confirm-keyword)
      confirm_keyword="${2:-}"
      shift 2
      ;;
    *)
      echo "Argument non reconnu : $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell (pwsh) est requis pour OpsToutatis. Installez pwsh 7.4+ puis relancez ce script." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl est requis pour télécharger la release GitHub." >&2
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "tar est requis pour extraire l'archive de release." >&2
  exit 1
fi

api_url="https://api.github.com/repos/${repository}/releases/latest"
if [[ -n "$tag" ]]; then
  api_url="https://api.github.com/repos/${repository}/releases/tags/${tag}"
fi

echo "Téléchargement des métadonnées de la release GitHub..."
release_json="$(curl -fsSL -H "Accept: application/vnd.github+json" -H "User-Agent: OpsToutatis-Installer" "$api_url")"

mapfile -t release_fields < <(
  printf '%s' "$release_json" | pwsh -NoLogo -NoProfile -Command '
    Set-StrictMode -Version Latest
    $json = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $json.tag_name
    $json.tarball_url
  '
)

tag_name="${release_fields[0]:-}"
tarball_url="${release_fields[1]:-}"

if [[ -z "$tag_name" || -z "$tarball_url" ]]; then
  echo "Impossible de déterminer le tag ou l'URL d'archive depuis la release GitHub." >&2
  exit 1
fi

temp_root="$(mktemp -d)"
archive_path="${temp_root}/OpsToutatis.tar.gz"
extract_path="${temp_root}/extracted"
install_path="${HOME}/.local/share/powershell/Modules/OpsToutatis"

cleanup() {
  rm -rf "${temp_root}"
}
trap cleanup EXIT

mkdir -p "$extract_path"

echo "Téléchargement de la release taguée ${tag_name}..."
curl -fL "$tarball_url" -o "$archive_path"

echo "Extraction de l'archive..."
tar -xzf "$archive_path" -C "$extract_path"

manifest_path="$(find "$extract_path" -type f -name 'OpsToutatis.psd1' | head -n 1)"
if [[ -z "$manifest_path" ]]; then
  echo "Le manifest OpsToutatis.psd1 est introuvable dans l'archive." >&2
  exit 1
fi

module_source_path="$(cd "$(dirname "$manifest_path")" && pwd)"

if [[ -e "$install_path" ]]; then
  if [[ "$force_reinstall" != "true" ]]; then
    echo "Une installation existe déjà dans ${install_path}. Relancez avec --force-reinstall --confirm-keyword REINSTALL." >&2
    exit 1
  fi

  if [[ "$confirm_keyword" != "REINSTALL" ]]; then
    echo "Confirmation explicite requise. Utilisez --confirm-keyword REINSTALL pour remplacer l'installation existante." >&2
    exit 1
  fi

  rm -rf "$install_path"
fi

mkdir -p "$install_path"
cp -R "${module_source_path}/." "$install_path/"

echo "Installation terminée dans : ${install_path}"
echo "Pour démarrer l'interface, ouvrez une nouvelle session et exécutez :"
echo "Import-Module OpsToutatis -Force"
echo "Start-OpsToutatis"
