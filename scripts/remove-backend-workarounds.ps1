# Backend gecici workaround env'lerini kaldirir (worker deploy basarili olduktan sonra calistirin).
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
railway service "Baserow Backend" | Out-Null

Write-Host "Celery Worker deploy basarili ve export kuyrugu dinleniyor mu kontrol edin." -ForegroundColor Yellow
Write-Host "Sonra su degiskenler kaldirilacak: CELERY_TASK_ALWAYS_EAGER, BASEROW_SYNC_AUTOMATION_PUBLISH" -ForegroundColor Yellow

foreach ($name in @("CELERY_TASK_ALWAYS_EAGER", "BASEROW_SYNC_AUTOMATION_PUBLISH")) {
    Write-Host "Kaldiriliyor: $name"
    railway variable delete $name 2>&1 | Out-Null
}

Write-Host "Tamam. Backend yeniden deploy olacak; ardindan scripts\test-automation-e2e.ps1 ile dogrulayin." -ForegroundColor Green