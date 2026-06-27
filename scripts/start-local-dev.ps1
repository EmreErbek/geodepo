# Baserow gelistirme ortamini kaynak koddan baslatir.
# Ilk calistirmada image build uzun surebilir (10-20 dk).

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

Set-Location $RepoRoot

if (-not (Test-Path (Join-Path $RepoRoot "baserow\backend"))) {
    & (Join-Path $PSScriptRoot "setup-baserow-source.ps1")
}

if (-not (Test-Path (Join-Path $RepoRoot ".env"))) {
    Write-Host ".env bulunamadi, .env.example kopyalaniyor..." -ForegroundColor Yellow
    Copy-Item (Join-Path $RepoRoot ".env.example") (Join-Path $RepoRoot ".env")
    Write-Host "Lutfen .env icindeki SECRET_KEY ve sifreleri duzenleyin." -ForegroundColor Yellow
}

Write-Host "Baserow dev ortami baslatiliyor..." -ForegroundColor Cyan
Write-Host "  Frontend: http://localhost:3000"
Write-Host "  Backend:  http://localhost:8000"
Write-Host ""

docker compose up --build