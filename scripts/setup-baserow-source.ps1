# Baserow kaynak kodunu geo_depo projesine ekler veya gunceller.
# Kullanim: .\scripts\setup-baserow-source.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$BaserowDir = Join-Path $RepoRoot "baserow"
$Version = "2.2.2"
$Upstream = "https://github.com/baserow/baserow.git"

Set-Location $RepoRoot

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git bulunamadi."
}

if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
    git init
    Write-Host "Git deposu olusturuldu." -ForegroundColor Cyan
}

if (Test-Path $BaserowDir) {
    if (Test-Path (Join-Path $BaserowDir ".git")) {
        Write-Host "Mevcut baserow klasoru guncelleniyor..." -ForegroundColor Cyan
        Push-Location $BaserowDir
        git fetch --tags --depth 1 origin
        git checkout $Version
        Pop-Location
    } else {
        throw "baserow/ var ama git deposu degil. Klasoru silip tekrar calistirin."
    }
} else {
    Write-Host "Baserow $Version klonlaniyor..." -ForegroundColor Cyan
    git clone --depth 1 --branch $Version $Upstream $BaserowDir
}

# Railway uyumlulugu icin baserow kaynak kodu dogrudan repoda tutulur (submodule degil).
if (Test-Path (Join-Path $BaserowDir ".git")) {
    Remove-Item -Recurse -Force (Join-Path $BaserowDir ".git")
    Write-Host "baserow/.git kaldirildi (vendored kaynak modu)." -ForegroundColor DarkGray
}

$desc = git -C $BaserowDir describe --tags --always
Write-Host ""
Write-Host "Tamam. Baserow surumu: $desc" -ForegroundColor Green
Write-Host ""
Write-Host "Sonraki adimlar:"
Write-Host "  1) Kodu duzenleyin: baserow/ klasoru"
Write-Host "  2) Lokal dev:       .\scripts\start-local-dev.ps1"
Write-Host "  3) Railway:         .\scripts\setup-railway-source-build.ps1"