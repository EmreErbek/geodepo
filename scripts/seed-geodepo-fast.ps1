# Hizli production seed: tablolari tek API cagrisiyla (first_row_header) olusturur.
# Tum alanlar text — import icin yeterli. Sonra UI'dan tipler iyilestirilebilir.
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
. "$PSScriptRoot\lib\geodepo-api.ps1"

$cfg = Get-GeodepoConfig
$idMapPath = Join-Path $cfg.Root "deploy\geodepo\id-map.json"
$token = Get-GeodepoToken

$workspaceName = "GEO_DEPO Ana"
$databaseName = "Operasyonlar"

$fastSchemaPath = Join-Path $cfg.Root "deploy\geodepo\schema-fast.json"
$tables = (Get-Content $fastSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json).tables

Write-Host "FAST SEED -> $($cfg.BaseUrl)" -ForegroundColor Cyan
$workspace = Get-OrCreateWorkspace -Token $token -Name $workspaceName
$database = Get-OrCreateDatabase -Token $token -WorkspaceId $workspace.id -Name $databaseName
Write-Host "Workspace $($workspace.id), Database $($database.id)"

$tableIds = @{}
$fieldIds = @{}

foreach ($t in $tables) {
    $existing = Invoke-GeodepoApi -Path "/api/database/tables/database/$($database.id)/" -Token $token |
        Where-Object { $_.name -eq $t.name } | Select-Object -First 1

    if ($existing) {
        $table = $existing
        Write-Host "Tablo mevcut: $($t.name) (ID $($table.id))" -ForegroundColor Yellow
    } else {
        Write-Host "Tablo olusturuluyor (async): $($t.name) ..." -ForegroundColor Green
        $table = New-TableAsync -Token $token -DatabaseId $database.id -Name $t.name -FieldNames $t.fields
        Write-Host "  -> ID $($table.id)" -ForegroundColor Green
    }

    $tableIds[$t.name] = $table.id
    $apiFields = Invoke-GeodepoApi -Path "/api/database/fields/table/$($table.id)/" -Token $token
    $map = @{}
    foreach ($f in $apiFields) { $map[$f.name] = $f.id }
    $fieldIds[$t.name] = $map
}

$idMap = [ordered]@{
    workspace_id = $workspace.id
    database_id = $database.id
    tables = $tableIds
    fields = $fieldIds
    mode = "fast-text"
    seeded_at = (Get-Date).ToString("o")
}

Save-IdMap -Path $idMapPath -Map $idMap
Write-Host ""
Write-Host "Fast seed tamamlandi: $idMapPath" -ForegroundColor Green