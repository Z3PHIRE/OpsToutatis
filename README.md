# OpsToutatis

OpsToutatis is a cross-platform PowerShell module for infrastructure orchestration.

## One-liner installation

### Windows (PowerShell)
```powershell
$tag = 'v0.1.0'; iex (irm "https://raw.githubusercontent.com/Z3PHIRE/OpsToutatis/$tag/scripts/install.ps1")
```

### Linux (bash)
```bash
tag='v0.1.0'; curl -fsSL "https://raw.githubusercontent.com/Z3PHIRE/OpsToutatis/${tag}/scripts/install.sh" | bash
```

Replace `v0.1.0` with the latest released tag.

## Manual module import

```powershell
Import-Module ./OpsToutatis.psd1 -Force
```

## Project layout

```text
/OpsToutatis.psd1
/OpsToutatis.psm1
/src/
  /Public/
  /Private/
  /Roles/
  /UI/
  /Transport/
/tests/
/scripts/
/docs/
/.github/workflows/ci.yml
```

## Development checks

```powershell
Import-Module ./OpsToutatis.psd1 -Force
Invoke-Pester -Path ./tests
```
