$ErrorActionPreference = 'Stop'
$base = 'https://baserow-backend-production-4412.up.railway.app'

Write-Host "=== Login ==="
$tok = (Invoke-RestMethod -Uri "$base/api/user/token-auth/" -Method POST `
    -Body (@{ email = 'emre2372@yahoo.com'; password = 'asd123asd' } | ConvertTo-Json) `
    -ContentType 'application/json' -TimeoutSec 90).token
$h = @{ Authorization = "JWT $tok" }
$hJson = @{ Authorization = "JWT $tok"; 'Content-Type' = 'application/json' }

Write-Host "=== Health ==="
$health = Invoke-RestMethod -Uri "$base/api/_health/full/" -Headers $h -TimeoutSec 90
Write-Host "export_q=$($health.celery_export_queue_size)"

Write-Host "=== Republish ==="
$pub = Invoke-RestMethod -Uri "$base/api/automation/workflows/4/publish/async/" -Method POST -Headers $hJson -Body '{}' -TimeoutSec 90
Write-Host "publish job $($pub.id)"
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 3
    $job = Invoke-RestMethod -Uri "$base/api/jobs/$($pub.id)/" -Headers $h -TimeoutSec 90
    Write-Host "poll $i state=$($job.state)"
    if ($job.state -in @('finished', 'failed', 'cancelled')) { break }
}
if ($job.state -ne 'finished') { throw "Publish failed: $($job.state)" }

Write-Host "=== Cleanup empty rows ==="
$all = Invoke-RestMethod -Uri "$base/api/database/rows/table/29/?user_field_names=true&size=200" -Headers $h -TimeoutSec 90
foreach ($r in $all.results) {
    if (-not $r.'ClickUp Task ID' -and -not $r.'Görev Adı') {
        Invoke-RestMethod -Uri "$base/api/database/rows/table/29/$($r.id)/" -Method DELETE -Headers $hJson -TimeoutSec 90 | Out-Null
        Write-Host "deleted empty $($r.id)"
    }
}

Write-Host "=== E2E toggle Teklif #5 ==="
Invoke-RestMethod -Uri "$base/api/database/rows/table/27/5/?user_field_names=true" -Method PATCH `
    -Headers $hJson -Body (@{ 'Teklif Durumu' = 'Beklemede' } | ConvertTo-Json) -TimeoutSec 90 | Out-Null
Start-Sleep -Seconds 2
Invoke-RestMethod -Uri "$base/api/database/rows/table/27/5/?user_field_names=true" -Method PATCH `
    -Headers $hJson -Body (@{ 'Teklif Durumu' = 'Kabul Edildi' } | ConvertTo-Json) -TimeoutSec 90 | Out-Null

for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Seconds 3
    $after = Invoke-RestMethod -Uri "$base/api/database/rows/table/29/?user_field_names=true&size=200" -Headers $h -TimeoutSec 90
    $match = @($after.results | Where-Object { $_.'ClickUp Task ID' -eq 'teklif-5' })
    if ($match.Count -gt 0) {
        $r = $match[0]
        $kayit = if ($r.'Kayıt Türü'.value) { $r.'Kayıt Türü'.value } else { $r.'Kayıt Türü' }
        Write-Host "SUCCESS id=$($r.id) gorev=$($r.'Görev Adı') kayit=$kayit cu=$($r.'ClickUp Task ID')"
        exit 0
    }
    Write-Host "wait $($i + 1)/12"
}

$hist = Invoke-RestMethod -Uri "$base/api/automation/workflows/4/history/?limit=1" -Headers $h -TimeoutSec 90
$run = $hist.results[0]
Write-Host "FAIL nodes=$($run.node_histories.node -join ',')"
$action = $run.node_histories | Where-Object { $_.node_type -eq 'local_baserow_create_row' } | Select-Object -Last 1
if ($action) {
    Write-Host "action gorev=$($action.result.'Görev Adı') cu=$($action.result.'ClickUp Task ID')"
}
exit 1