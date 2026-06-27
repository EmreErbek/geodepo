# Dağıtık Baserow Railway ortam degiskeni scripti (eski hazir imaj kurulumu)
# Kaynak koddan build icin: scripts/setup-railway-source-build.ps1
# Ön koşul: railway login && railway link (geo_depo klasöründe)

$ErrorActionPreference = "Stop"

function Require-Railway {
    if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
        $bin = Join-Path $env:USERPROFILE ".railway\bin\railway.exe"
        if (Test-Path $bin) { $env:Path = "$(Split-Path $bin);$env:Path" }
        else { throw "Railway CLI bulunamadı. Önce CLI kurun." }
    }
    railway whoami | Out-Null
}

function New-SecretKey {
    -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 50 | ForEach-Object { [char]$_ })
}

function Set-ServiceVars {
    param(
        [string]$Service,
        [hashtable]$Vars
    )
    foreach ($entry in $Vars.GetEnumerator()) {
        Write-Host "[$Service] $($entry.Key)"
        railway variable set "$($entry.Key)=$($entry.Value)" --service $Service
    }
}

Require-Railway

$frontendUrl = Read-Host "Frontend public URL (örn: https://baserow-frontend-production-xxxx.up.railway.app)"
if ($frontendUrl -notmatch "^https?://") {
    throw "URL https:// ile başlamalı"
}

$frontendHost = ([uri]$frontendUrl).Host
$secretKey = New-SecretKey

Write-Host ""
Write-Host "SECRET_KEY üretildi. Servislere yazılıyor..." -ForegroundColor Cyan

$backendVars = @{
    SECRET_KEY = $secretKey
    DATABASE_URL = '${{Postgres.DATABASE_URL}}'
    REDIS_URL = '${{Redis.REDIS_URL}}'
    PUBLIC_BACKEND_URL = $frontendUrl
    PUBLIC_WEB_FRONTEND_URL = $frontendUrl
    BASEROW_EXTRA_ALLOWED_HOSTS = $frontendHost
    BASEROW_BACKEND_PORT = '8080'
    BASEROW_AMOUNT_OF_GUNICORN_WORKERS = '2'
    BASEROW_TRIGGER_SYNC_TEMPLATES_AFTER_MIGRATION = 'false'
    BASEROW_ENABLE_SECURE_PROXY_SSL_HEADER = 'true'
}

$frontendVars = @{
    PUBLIC_WEB_FRONTEND_URL = $frontendUrl
    PUBLIC_BACKEND_URL = $frontendUrl
    PRIVATE_BACKEND_URL = 'http://baserow-backend.railway.internal:8080'
    BASEROW_DISABLE_PUBLIC_URL_CHECK = 'true'
}

$workerVars = @{
    SECRET_KEY = $secretKey
    DATABASE_URL = '${{Postgres.DATABASE_URL}}'
    REDIS_URL = '${{Redis.REDIS_URL}}'
    PUBLIC_BACKEND_URL = $frontendUrl
    PUBLIC_WEB_FRONTEND_URL = $frontendUrl
    BASEROW_BACKEND_PORT = '8080'
    BASEROW_TRIGGER_SYNC_TEMPLATES_AFTER_MIGRATION = 'false'
}

# Servis adları şablonda farklı olabilir; railway status ile kontrol edin.
$services = @{
    Backend = @('Baserow Backend', 'baserow-backend', 'Backend')
    Frontend = @('Baserow Frontend', 'baserow-frontend', 'Frontend')
    Worker = @('Celery Worker', 'celery-worker', 'Celery Worker')
    Beat = @('Celery Beat', 'celery-beat', 'Celery Beat')
}

function Resolve-ServiceName {
    param([string[]]$Candidates)
    $json = railway status --json | ConvertFrom-Json
    $names = @($json.services.name)
    foreach ($c in $Candidates) {
        if ($names -contains $c) { return $c }
    }
    return $null
}

$backendName = Resolve-ServiceName $services.Backend
$frontendName = Resolve-ServiceName $services.Frontend
$workerName = Resolve-ServiceName $services.Worker
$beatName = Resolve-ServiceName $services.Beat

if (-not $backendName -or -not $frontendName) {
    Write-Host "Mevcut servisler:" -ForegroundColor Yellow
    railway status
    throw "Backend veya Frontend servis adı bulunamadı. scripts/configure-baserow-railway.ps1 içindeki adları güncelleyin."
}

Set-ServiceVars -Service $backendName -Vars $backendVars
Set-ServiceVars -Service $frontendName -Vars $frontendVars

if ($workerName) { Set-ServiceVars -Service $workerName -Vars $workerVars }
if ($beatName) { Set-ServiceVars -Service $beatName -Vars $workerVars }

Write-Host ""
Write-Host "Tamam. Kontrol listesi:" -ForegroundColor Green
Write-Host "1) Frontend servisinde public domain açık mı?"
Write-Host "2) Backend + Celery Worker'da /baserow/media volume var mı?"
Write-Host "3) railway logs -s '$frontendName' ile deploy loglarını izleyin"
Write-Host "4) $frontendUrl adresinden admin hesabı oluşturun"