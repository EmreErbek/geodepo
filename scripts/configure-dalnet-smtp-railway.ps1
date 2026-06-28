# Dalnet (mail.dalnet.com.tr) SMTP ayarlarini Baserow Railway servislerine yazar.
# E-posta gonderimi Celery Worker uzerinden calisir; Backend + Worker zorunlu.
#
# On kosul: railway login && railway link (baserow klasorunde)
# Ornek: powershell -ExecutionPolicy Bypass -File scripts/configure-dalnet-smtp-railway.ps1

$ErrorActionPreference = "Stop"

function Require-Railway {
    if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
        $bin = Join-Path $env:USERPROFILE ".railway\bin\railway.exe"
        if (Test-Path $bin) { $env:Path = "$(Split-Path $bin);$env:Path" }
        else { throw "Railway CLI bulunamadi. Once: railway login" }
    }
    railway whoami | Out-Null
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
Set-Location (Join-Path (Split-Path $PSScriptRoot -Parent) "baserow")

$defaultFrom = "noreply@geoproje.com.tr"
$fromEmail = Read-Host "Gonderen e-posta (FROM_EMAIL) [$defaultFrom]"
if ([string]::IsNullOrWhiteSpace($fromEmail)) { $fromEmail = $defaultFrom }

$smtpUser = Read-Host "SMTP kullanici (genelde tam e-posta) [$fromEmail]"
if ([string]::IsNullOrWhiteSpace($smtpUser)) { $smtpUser = $fromEmail }

$smtpPassword = Read-Host "SMTP sifre" -AsSecureString
$smtpPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($smtpPassword)
)

$useSsl = Read-Host "Port 465 + SSL kullanilsin mi? (E/H, varsayilan H=587+TLS) [H]"
$useSslEnabled = $useSsl -match '^[Ee]'

$smtpVars = @{
    EMAIL_SMTP = "true"
    EMAIL_SMTP_HOST = "mail.dalnet.com.tr"
    FROM_EMAIL = $fromEmail
    EMAIL_SMTP_USER = $smtpUser
    EMAIL_SMTP_PASSWORD = $smtpPasswordPlain
}

if ($useSslEnabled) {
    $smtpVars["EMAIL_SMTP_PORT"] = "465"
    $smtpVars["EMAIL_SMTP_USE_SSL"] = "true"
    $smtpVars["EMAIL_SMTP_USE_TLS"] = ""
} else {
    $smtpVars["EMAIL_SMTP_PORT"] = "587"
    $smtpVars["EMAIL_SMTP_USE_TLS"] = "true"
    $smtpVars["EMAIL_SMTP_USE_SSL"] = ""
}

$services = @("Baserow Backend", "Celery Worker", "Celery Beat")
foreach ($svc in $services) {
    try {
        Set-ServiceVars -Service $svc -Vars $smtpVars
    } catch {
        Write-Host "Atlandi veya hata: $svc - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "SMTP ayarlari yazildi. Servisler yeniden baslatilabilir." -ForegroundColor Green
Write-Host "Test: Workspace'ten bir davet gonderin, spam klasorunu de kontrol edin." -ForegroundColor Green