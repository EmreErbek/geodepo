# Import sonrasi satir sayisi ve ornek kayit dogrulama.
# Kullanim: .\scripts\validate-import.ps1 [-ListId 53031172]
param(
    [string]$ListId = "53031172"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\geodepo-api.ps1"

$clickupToken = $env:CLICKUP_API_TOKEN
if (-not $clickupToken) { throw "CLICKUP_API_TOKEN gerekli" }

$cfg = Get-GeodepoConfig
$idMapPath = Join-Path $cfg.Root "deploy\geodepo\id-map.json"
$fieldMapPath = Join-Path $cfg.Root "deploy\geodepo\clickup-field-map.json"

if (-not (Test-Path $idMapPath)) {
    throw "id-map.json yok. Once seed + import calistirin."
}

$idMap = Get-Content $idMapPath -Raw | ConvertFrom-Json
$fieldMaps = Get-Content $fieldMapPath -Raw | ConvertFrom-Json
$baserowToken = Get-GeodepoToken

$mapping = $fieldMaps.lists.$ListId
if ($mapping.inherits) {
    $mapping = $fieldMaps.lists.($mapping.inherits)
    foreach ($prop in $fieldMaps.lists.$ListId.PSObject.Properties) {
        if ($prop.Name -ne "inherits") {
            $mapping | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }
}

$targetTable = $mapping.target_table
$tableId = [int]$idMap.tables.$targetTable

$clickupList = curl.exe -s -H "Authorization: $clickupToken" "https://api.clickup.com/api/v2/list/$ListId" | ConvertFrom-Json
$clickupCount = [int]$clickupList.task_count

$baserowRows = Invoke-GeodepoApi -Path "/api/database/rows/table/$tableId/?user_field_names=true&size=200" -Token $baserowToken
$baserowCount = [int]$baserowRows.count

$withClickUpId = @($baserowRows.results | Where-Object { $_."ClickUp Task ID" })
$listFiltered = if ($mapping.clickup_list_value) {
    @($baserowRows.results | Where-Object { $_."ClickUp List" -eq $mapping.clickup_list_value })
} else {
    $baserowRows.results
}

Write-Host ""
Write-Host "=== Dogrulama: $($mapping.name) ===" -ForegroundColor Cyan
Write-Host "ClickUp task_count : $clickupCount"
Write-Host "Baserow toplam satir: $baserowCount"
Write-Host "ClickUp ID'li satir : $($withClickUpId.Count)"
if ($mapping.clickup_list_value) {
    Write-Host "Liste filtresi ($($mapping.clickup_list_value)): $($listFiltered.Count)"
}

$sample = $listFiltered | Select-Object -First 5
Write-Host ""
Write-Host "Ornek kayitlar:" -ForegroundColor Yellow
foreach ($row in $sample) {
    $nameField = if ($targetTable -eq "Projeler") { "Proje Adı" }
                 elseif ($targetTable -eq "Teklifler") { "Teklif Adı" }
                 elseif ($targetTable -eq "Tahsilatlar") { "Kayıt Adı" }
                 else { "name" }
    $label = $row.$nameField
    if (-not $label) { $label = "(isimsiz)" }
    Write-Host "  - $label [CU:$($row.'ClickUp Task ID')]"
}

$ok = $listFiltered.Count -ge [math]::Min($clickupCount, 1)
if ($listFiltered.Count -lt $clickupCount) {
    Write-Host ""
    Write-Host "UYARI: Baserow'da $($clickupCount - $listFiltered.Count) eksik kayit olabilir." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Dogrulama gecti." -ForegroundColor Green
exit 0