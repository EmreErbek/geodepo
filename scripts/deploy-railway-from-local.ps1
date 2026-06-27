# GitHub app erisimi olmadan geo_depo reposundan Railway'e deploy eder.
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$r = Join-Path $env:USERPROFILE ".railway\bin\railway.exe"

$services = @("Baserow Backend", "Baserow Frontend", "Celery Worker", "Celery Beat")
Set-Location $RepoRoot

& (Join-Path $PSScriptRoot "apply-railway-build-settings.ps1")

foreach ($svc in $services) {
    Write-Host ""
    Write-Host "Deploy: $svc" -ForegroundColor Cyan
    & $r up . --service $svc --detach --yes
}

Write-Host ""
Write-Host "Deploylar baslatildi. Izlemek icin:" -ForegroundColor Green
Write-Host "  railway logs -s 'Baserow Frontend'"