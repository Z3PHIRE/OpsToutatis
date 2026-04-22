# Contributing to OpsToutatis

## Requirements
- PowerShell 5.1 for Windows compatibility checks.
- PowerShell 7.4+ for cross-platform validation.
- Pester 5.x for tests.

## Development workflow
1. Create a feature branch from `main`.
2. Implement changes in `src/Public` and `src/Private`.
3. Add or update tests under `tests/`.
4. Run local validation:
   - `Import-Module ./OpsToutatis.psd1 -Force`
   - `Invoke-Pester -Path ./tests`
5. Open a pull request with a clear summary and test evidence.

## Coding conventions
- Public functions must use `Verb-OpsName` naming.
- Keep code portable across PowerShell 5.1 and 7.4+.
- Avoid non-portable syntax (ternary, null-coalescing operator, platform shortcuts).
- Keep user-facing text in French.
- Keep source code, comments, and raw logs in English.
