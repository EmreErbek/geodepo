# ClickUp listelerinden Geoproje tablolarina veri aktarir.
# Kullanim:
#   $env:CLICKUP_API_TOKEN = "pk_..."
#   .\scripts\import-clickup.ps1 -ListIds @("53031172") [-DryRun]
param(
    [string[]]$ListIds = @("53031172"),
    [switch]$DryRun,
    [int]$PageSize = 100
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\geodepo-api.ps1"

$clickupToken = $env:CLICKUP_API_TOKEN
if (-not $clickupToken) { throw "CLICKUP_API_TOKEN gerekli" }

$cfg = Get-GeodepoConfig
$fieldMapFile = Join-Path $cfg.Root "deploy\geodepo\clickup-field-map.json"
$idMapPath = Join-Path $cfg.Root "deploy\geodepo\id-map.json"
$logPath = Join-Path $cfg.Root "deploy\geodepo\clickup-import-log.json"

if (-not (Test-Path $idMapPath)) {
    throw "Once seed calistirin: .\scripts\seed-geodepo-workspace.ps1"
}

$idMap = Get-Content $idMapPath -Raw | ConvertFrom-Json
$fieldMaps = Get-Content $fieldMapFile -Raw | ConvertFrom-Json
$baserowToken = Get-GeodepoToken

function Invoke-ClickUp {
    param([string]$Path)
    $resp = curl.exe -s -H "Authorization: $clickupToken" "https://api.clickup.com/api/v2/$Path"
    if (-not $resp) { throw "ClickUp bos yanit: $Path" }
    return $resp | ConvertFrom-Json
}

function Resolve-ListMapping {
    param([string]$ListId)
    $entry = $fieldMaps.lists.$ListId
    if (-not $entry) { throw "Liste mapping yok: $ListId" }
    if ($entry.inherits) {
        $parent = $fieldMaps.lists.($entry.inherits)
        $merged = $parent | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        foreach ($prop in $entry.PSObject.Properties) {
            if ($prop.Name -ne "inherits") {
                $merged | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
            }
        }
        return $merged
    }
    return $entry
}

function Get-ClickUpCustomFieldValue {
    param($CustomField)
    if ($null -eq $CustomField.value) { return $null }
    switch ($CustomField.type) {
        "drop_down" {
            if ($CustomField.type_config.options) {
                $opt = $CustomField.type_config.options | Where-Object { $_.orderindex -eq $CustomField.value } | Select-Object -First 1
                if ($opt) { return $opt.name }
            }
            return $CustomField.value
        }
        "labels" {
            if ($CustomField.value -is [array]) {
                return @($CustomField.value | ForEach-Object {
                    $opt = $CustomField.type_config.options | Where-Object { $_.id -eq $_ } | Select-Object -First 1
                    if ($opt) { $opt.label } else { $_ }
                })
            }
            return $CustomField.value
        }
        "date" {
            if ($CustomField.value -match '^\d+$') {
                return ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$CustomField.value)).ToString("yyyy-MM-dd")
            }
            return $CustomField.value
        }
        "currency" { return [decimal]$CustomField.value }
        "number" { return [decimal]$CustomField.value }
        "checkbox" { return [bool]$CustomField.value }
        default { return $CustomField.value }
    }
}

function Get-OrCreateCustomer {
    param([string]$Name, [hashtable]$Cache)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $key = $Name.Trim().ToLower()
    if ($Cache.ContainsKey($key)) { return $Cache[$key] }

    $tableId = [int]$idMap.tables."Müşteriler"
    $fields = $idMap.fields."Müşteriler"

    $search = Invoke-GeodepoApi -Path "/api/database/rows/table/$tableId/?user_field_names=true&size=1&search=$([uri]::EscapeDataString($Name))" -Token $baserowToken
    if ($search.results -and $search.results.Count -gt 0) {
        $rowId = $search.results[0].id
        $Cache[$key] = $rowId
        return $rowId
    }

    if ($DryRun) {
        Write-Host "[DRY] Musteri olusturulacak: $Name" -ForegroundColor Yellow
        return -1
    }

    $created = Invoke-GeodepoApi -Method POST -Path "/api/database/rows/table/$tableId/?user_field_names=true" -Token $baserowToken -Body @{
        "Firma Adı" = $Name
    }
    $Cache[$key] = $created.id
    return $created.id
}

function Test-ExistingClickUpRow {
    param([int]$TableId, [string]$ClickUpTaskId)
    if ([string]::IsNullOrWhiteSpace($ClickUpTaskId)) { return $false }
    $resp = Invoke-GeodepoApi -Path "/api/database/rows/table/$TableId/?user_field_names=true&size=1&search=$ClickUpTaskId" -Token $baserowToken
    foreach ($row in $resp.results) {
        if ($row."ClickUp Task ID" -eq $ClickUpTaskId) { return $true }
    }
    return $false
}

$customerCache = @{}
$log = [ordered]@{
    started_at = (Get-Date).ToString("o")
    lists = @()
    created = 0
    skipped = 0
    errors = @()
}

foreach ($listId in $ListIds) {
    $mapping = Resolve-ListMapping -ListId $listId
    $targetTable = $mapping.target_table
    $tableId = [int]$idMap.tables.$targetTable
    $tableFields = $idMap.fields.$targetTable

    Write-Host ""
    Write-Host "=== $($mapping.name) ($listId) -> $targetTable ===" -ForegroundColor Cyan

    $listMeta = Invoke-ClickUp -Path "list/$listId/field"
    $cfByName = @{}
    foreach ($f in $listMeta.fields) { $cfByName[$f.name] = $f }

    $page = 0
    $listLog = [ordered]@{ list_id = $listId; name = $mapping.name; imported = 0; skipped = 0; errors = @() }

    do {
        $tasksResp = Invoke-ClickUp -Path "list/$listId/task?archived=false&page=$page&limit=$PageSize&include_closed=true&subtasks=true"
        $tasks = @($tasksResp.tasks)
        if ($tasks.Count -eq 0) { break }

        $batch = @()
        foreach ($task in $tasks) {
            if (Test-ExistingClickUpRow -TableId $tableId -ClickUpTaskId $task.id) {
                $listLog.skipped++
                $log.skipped++
                continue
            }

            $row = [ordered]@{}

            if ($mapping.fields.name) { $row[$mapping.fields.name] = $task.name }
            if ($mapping.fields.description -and $task.description) {
                $row[$mapping.fields.description] = $task.description
            }

            if ($mapping.fields.status -and $task.status.status) {
                $statusKey = $task.status.status.ToLower()
                $mapped = $mapping.status_map.$statusKey
                if (-not $mapped) { $mapped = $task.status.status }
                $row[$mapping.fields.status] = $mapped
            }

            if ($mapping.fields.priority -and $task.priority) {
                $pKey = [string]$task.priority.id
                $mapped = $mapping.priority_map.$pKey
                if ($mapped) { $row[$mapping.fields.priority] = $mapped }
            }

            if ($mapping.clickup_list_field -and $mapping.clickup_list_value) {
                $row[$mapping.clickup_list_field] = $mapping.clickup_list_value
            }

            $row["ClickUp Task ID"] = $task.id

            foreach ($cf in $task.custom_fields) {
                $cfName = $cf.name
                if (-not $mapping.custom_fields.$cfName) { continue }
                $targetField = $mapping.custom_fields.$cfName
                $value = Get-ClickUpCustomFieldValue -CustomField $cf
                if ($null -eq $value) { continue }

                if ($targetField -eq "İşveren" -or $targetField -eq "Müşteri") {
                    $idMapMode = $idMap.mode
                    if ($idMapMode -eq "fast-text") {
                        $row[$targetField] = [string]$value
                    } else {
                        $customerId = Get-OrCreateCustomer -Name ([string]$value) -Cache $customerCache
                        if ($customerId) {
                            $row[$targetField] = @($customerId)
                        }
                    }
                } elseif ($targetField -eq "Etiketler" -and $value -is [array]) {
                    $row[$targetField] = $value
                } else {
                    $row[$targetField] = $value
                }
            }

            if ($DryRun) {
                Write-Host "[DRY] $($task.name)" -ForegroundColor Yellow
                $listLog.imported++
                continue
            }

            $batch += $row
        }

        if (-not $DryRun -and $batch.Count -gt 0) {
            try {
                $resp = Invoke-GeodepoApi -Method POST -Path "/api/database/rows/table/$tableId/batch/?user_field_names=true" -Token $baserowToken -Body @{
                    items = $batch
                }
                $count = @($resp.items).Count
                $listLog.imported += $count
                $log.created += $count
                Write-Host "  $($batch.Count) satir eklendi" -ForegroundColor Green
            } catch {
                $listLog.errors += $_.Exception.Message
                $log.errors += "Liste $listId : $($_.Exception.Message)"
                Write-Host "  HATA: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        $page++
    } while ($tasks.Count -eq $PageSize)

    $log.lists += $listLog
    Write-Host "Liste ozeti: $($listLog.imported) eklendi, $($listLog.skipped) atlandi" -ForegroundColor Cyan
}

$log.finished_at = (Get-Date).ToString("o")
$dir = Split-Path $logPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$log | ConvertTo-Json -Depth 10 | Set-Content -Path $logPath -Encoding UTF8
Write-Host ""
Write-Host "Import log: $logPath" -ForegroundColor Green