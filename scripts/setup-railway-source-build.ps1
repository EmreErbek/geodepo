# Railway servislerini hazir Docker imaji yerine geo_depo reposundan build edecek sekilde ayarlar.
# On kosul: railway login && railway link (GEO_DEPO projesine)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Require-Railway {
    if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
        $bin = Join-Path $env:USERPROFILE ".railway\bin\railway.exe"
        if (Test-Path $bin) { $env:Path = "$(Split-Path $bin);$env:Path" }
        else { throw "Railway CLI bulunamadi." }
    }
    railway whoami | Out-Null
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

Require-Railway
Set-Location $RepoRoot

if (-not (Test-Path (Join-Path $RepoRoot "baserow\backend\Dockerfile"))) {
    & (Join-Path $PSScriptRoot "setup-baserow-source.ps1")
}

$frontendUrl = Read-Host "Frontend public URL (ornek: https://baserow-frontend-production-xxxx.up.railway.app)"
$backendUrl = Read-Host "Backend public URL (ornek: https://baserow-backend-production-xxxx.up.railway.app)"
foreach ($url in @($frontendUrl, $backendUrl)) {
    if ($url -notmatch "^https?://") {
        throw "URL https:// ile baslamali"
    }
}

$frontendHost = ([uri]$frontendUrl).Host
$backendHost = ([uri]$backendUrl).Host

$serviceMap = [ordered]@{
    "Baserow Backend"  = @{ Config = "/deploy/railway/backend.toml" }
    "Baserow Frontend" = @{ Config = "/deploy/railway/frontend.toml" }
    "Celery Worker"    = @{ Config = "/deploy/railway/celery-worker.toml" }
    "Celery Beat"      = @{ Config = "/deploy/railway/celery-beat.toml" }
}

$backendName = Resolve-ServiceName @("Baserow Backend", "baserow-backend", "Backend")
$frontendName = Resolve-ServiceName @("Baserow Frontend", "baserow-frontend", "Frontend")
$workerName = Resolve-ServiceName @("Celery Worker", "celery-worker")
$beatName = Resolve-ServiceName @("Celery Beat", "celery-beat")

if (-not $backendName -or -not $frontendName) {
    railway status
    throw "Backend veya Frontend servisi bulunamadi."
}

# Mevcut SECRET_KEY'i koru; yoksa uret
$existingSecret = railway variables --service $backendName --json 2>$null | ConvertFrom-Json
$secretKey = $existingSecret.SECRET_KEY
if (-not $secretKey) {
    $secretKey = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 50 | ForEach-Object { [char]$_ })
    Write-Host "Yeni SECRET_KEY uretildi." -ForegroundColor Yellow
}

$backendVars = @{
    SECRET_KEY = $secretKey
    DATABASE_URL = '${{Postgres.DATABASE_URL}}'
    REDIS_URL = '${{Redis.REDIS_URL}}'
    PUBLIC_BACKEND_URL = $backendUrl
    PUBLIC_WEB_FRONTEND_URL = $frontendUrl
    BASEROW_EXTRA_ALLOWED_HOSTS = "$frontendHost,$backendHost,healthcheck.railway.app,baserow-backend.railway.internal"
    PRIVATE_BACKEND_URL = 'http://baserow-backend.railway.internal:8080'
    BASEROW_BACKEND_PORT = '8080'
    BASEROW_AMOUNT_OF_GUNICORN_WORKERS = '2'
    BASEROW_TRIGGER_SYNC_TEMPLATES_AFTER_MIGRATION = 'false'
    BASEROW_ENABLE_SECURE_PROXY_SSL_HEADER = 'true'
    BASEROW_OSS_ONLY = 'true'
}

$frontendVars = @{
    PUBLIC_WEB_FRONTEND_URL = $frontendUrl
    PUBLIC_BACKEND_URL = $backendUrl
    PRIVATE_BACKEND_URL = 'http://baserow-backend.railway.internal:8080'
    BASEROW_DISABLE_PUBLIC_URL_CHECK = 'true'
    BASEROW_OSS_ONLY = 'true'
}

$workerVars = @{
    SECRET_KEY = $secretKey
    DATABASE_URL = '${{Postgres.DATABASE_URL}}'
    REDIS_URL = '${{Redis.REDIS_URL}}'
    PUBLIC_BACKEND_URL = $backendUrl
    PUBLIC_WEB_FRONTEND_URL = $frontendUrl
    BASEROW_BACKEND_PORT = '8080'
    BASEROW_TRIGGER_SYNC_TEMPLATES_AFTER_MIGRATION = 'false'
}

function Set-ServiceVars {
    param([string]$Service, [hashtable]$Vars)
    foreach ($entry in $Vars.GetEnumerator()) {
        Write-Host "[$Service] $($entry.Key)" -ForegroundColor DarkGray
        railway variable set "$($entry.Key)=$($entry.Value)" --service $Service | Out-Null
    }
}

Write-Host "Ortam degiskenleri yaziliyor..." -ForegroundColor Cyan
Set-ServiceVars -Service $backendName -Vars $backendVars
Set-ServiceVars -Service $frontendName -Vars $frontendVars
if ($workerName) { Set-ServiceVars -Service $workerName -Vars $workerVars }
if ($beatName) { Set-ServiceVars -Service $beatName -Vars $workerVars }

Write-Host ""
Write-Host "=== Railway Dashboard'da her Baserow servisi icin ===" -ForegroundColor Green
Write-Host ""
Write-Host "Settings > Source:"
Write-Host "  - Docker Image yerine GitHub reposunu baglayin (geo_depo)"
Write-Host "  - Branch: main"
Write-Host ""
Write-Host "Settings > Build:"
Write-Host "  - Builder: Dockerfile (config dosyasi bunu ayarlar)"
Write-Host "  - Root Directory: baserow"
Write-Host "  - Config dosyasi (absolute path):"
Write-Host "      Baserow Backend  -> /deploy/railway/backend.toml"
Write-Host "      Baserow Frontend -> /deploy/railway/frontend.toml"
Write-Host "      Celery Worker    -> /deploy/railway/celery-worker.toml"
Write-Host "      Celery Beat      -> /deploy/railway/celery-beat.toml"
Write-Host ""
Write-Host "Settings > Deploy:"
Write-Host "  - Backend volume: /baserow/media (mevcut volume'u koruyun)"
Write-Host "  - Celery Worker volume: /baserow/media"
Write-Host ""
Write-Host "GitHub'a push oncesi:"
Write-Host "  git add . && git commit && git push"
Write-Host ""
Write-Host "Ilk source build 15-30 dk surebilir. Deploy sonrasi:"
Write-Host "  railway logs -s '$frontendName'"
Write-Host "  $frontendUrl"