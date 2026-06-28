$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\geodepo-api.ps1"
$t = Get-GeodepoToken
Write-Host "=== WORKSPACES ==="
(Invoke-GeodepoApi -Path "/api/workspaces/" -Token $t) | ForEach-Object { Write-Host "WS $($_.id): $($_.name)" }
Write-Host ""
Write-Host "=== DATABASE 7 TABLES ==="
$tables = Invoke-GeodepoApi -Path "/api/database/tables/database/7/" -Token $t
foreach ($table in $tables) {
    Write-Host "TABLE $($table.id): $($table.name)"
    $fields = Invoke-GeodepoApi -Path "/api/database/fields/table/$($table.id)/" -Token $t
    foreach ($f in $fields) { Write-Host "  - $($f.name)" }
}
Write-Host ""
Write-Host "JOBS:"
$jobs = Invoke-GeodepoApi -Path "/api/jobs/" -Token $t
@($jobs | Where-Object { $_.state -in @("pending","started") }) | ForEach-Object {
    Write-Host "  $($_.id) $($_.type) $($_.state) $($_.progress_percentage)%"
}