$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\geodepo-api.ps1"
$t = Get-GeodepoToken
Write-Host "Bekleyen isler kontrol ediliyor..."
$jobs = Invoke-GeodepoApi -Path "/api/jobs/" -Token $t
$running = @($jobs | Where-Object { $_.state -in @("pending", "started") })
Write-Host "Calisan is: $($running.Count)"
foreach ($job in $running) {
    Write-Host "  Job $($job.id) $($job.type) $($job.state) $($job.progress_percentage)%"
    $done = Wait-GeodepoJob -Token $t -JobId $job.id -MaxWaitSec 3600
    Write-Host "  -> $($done.state)" -ForegroundColor Green
}
Write-Host "Tum isler tamamlandi."