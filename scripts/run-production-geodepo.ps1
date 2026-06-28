# Production'da seed + import calistirir.
# Gerekli env (.env veya ortam degiskeni):
#   GEODEPO_BASEROW_URL=https://baserow-backend-production-4412.up.railway.app
#   GEODEPO_BASEROW_TOKEN=...  (veya EMAIL/PASSWORD)
#   CLICKUP_API_TOKEN=pk_...
param(
    [string[]]$ListIds = @("53031172", "53031171", "53031170"),
    [switch]$SeedOnly,
    [switch]$ImportOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$backendUrl = "https://baserow-backend-production-4412.up.railway.app"
if (-not $env:GEODEPO_BASEROW_URL) {
    $env:GEODEPO_BASEROW_URL = $backendUrl
}
if (-not $env:GEODEPO_BASEROW_EMAIL) {
    $env:GEODEPO_BASEROW_EMAIL = "emreerbek@geoproje.com.tr"
}

Write-Host "Production backend: $env:GEODEPO_BASEROW_URL" -ForegroundColor Cyan

if (-not $ImportOnly) {
    Write-Host ""
    Write-Host "=== SEED ===" -ForegroundColor Green
    & "$PSScriptRoot\seed-geodepo-workspace.ps1"
}

if (-not $SeedOnly) {
    Write-Host ""
    Write-Host "=== IMPORT ===" -ForegroundColor Green
    $importArgs = @{ ListIds = $ListIds }
    if ($DryRun) { $importArgs.DryRun = $true }
    & "$PSScriptRoot\import-clickup.ps1 @importArgs"

    Write-Host ""
    Write-Host "=== VALIDATE ===" -ForegroundColor Green
    foreach ($listId in $ListIds) {
        & "$PSScriptRoot\validate-import.ps1" -ListId $listId
    }
}

Write-Host ""
Write-Host "Production islem tamam." -ForegroundColor Green