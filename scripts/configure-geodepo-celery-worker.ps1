# GEO DEPO Celery Worker: export kuyrugunu dinlemesi icin Railway degiskenleri.
# Publish/import gibi async job'lar "export" kuyruguna gider; worker bunu dinlemezse pending kalir.
# Kullanim: powershell -ExecutionPolicy Bypass -File scripts/configure-geodepo-celery-worker.ps1

$ErrorActionPreference = "Stop"

function Require-Railway {
    if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
        $bin = Join-Path $env:USERPROFILE ".railway\bin\railway.exe"
        if (Test-Path $bin) { $env:Path = "$(Split-Path $bin);$env:Path" }
        else { throw "Railway CLI bulunamadi." }
    }
    railway whoami | Out-Null
}

Require-Railway
railway service "Celery Worker" | Out-Null

$vars = @{
    BASEROW_RUN_MINIMAL = "true"
    BASEROW_AMOUNT_OF_WORKERS = "1"
}

foreach ($entry in $vars.GetEnumerator()) {
    Write-Host "Celery Worker: $($entry.Key)=$($entry.Value)"
    railway variable set "$($entry.Key)=$($entry.Value)" | Out-Null
}

Write-Host ""
Write-Host "Tamam. Worker yeniden deploy olunca export kuyrugunu da dinler (combined mode)."
Write-Host "Beklenen log: 'Starting combined celery and export worker...'"
Write-Host ""
Write-Host "Deploy failed goruyorsaniz Railway UI > Celery Worker > Settings:" -ForegroundColor Yellow
Write-Host "  - Healthcheck Path: Disabled (celery servisinde HTTP yok)" -ForegroundColor Yellow
Write-Host "  - Config File: deploy/railway/celery-worker.toml" -ForegroundColor Yellow
Write-Host "  - startCommand: celery-worker" -ForegroundColor Yellow
Write-Host "  - Root Directory: baserow" -ForegroundColor Yellow