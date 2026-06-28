# GEO_DEPO Ana workspace'ini schema.json'a gore olusturur.
# Kullanim: .\scripts\seed-geodepo-workspace.ps1 [-Force]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
. "$PSScriptRoot\lib\geodepo-api.ps1"

$cfg = Get-GeodepoConfig
$schemaPath = Join-Path $cfg.Root "deploy\geodepo\schema.json"
$idMapPath = Join-Path $cfg.Root "deploy\geodepo\id-map.json"

if (-not (Test-Path $schemaPath)) {
    throw "Schema bulunamadi: $schemaPath"
}

$schema = Get-Content $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$token = Get-GeodepoToken

Write-Host "Baserow: $($cfg.BaseUrl)" -ForegroundColor Cyan
Write-Host "Workspace: $($schema.workspace.name)" -ForegroundColor Cyan

$workspace = Get-OrCreateWorkspace -Token $token -Name $schema.workspace.name
Write-Host "Workspace ID: $($workspace.id)"

$database = Get-OrCreateDatabase -Token $token -WorkspaceId $workspace.id -Name $schema.database.name
Write-Host "Database ID: $($database.id)"

$tableIds = @{}
$fieldIds = @{}
$viewIds = @{}

$sortedTables = $schema.tables | Sort-Object { $_.order }
foreach ($tableDef in $sortedTables) {
    $table = Get-OrCreateTable -Token $token -DatabaseId $database.id -Name $tableDef.name
    $tableIds[$tableDef.name] = $table.id
    Write-Host "Tablo: $($tableDef.name) (ID $($table.id))" -ForegroundColor Green

    if ($tableDef.primary_field) {
        Rename-PrimaryTableField -Token $token -TableId $table.id -PrimaryName $tableDef.primary_field
    }

    $existingFields = Invoke-GeodepoApi -Path "/api/database/fields/table/$($table.id)/" -Token $token
    $existingByName = @{}
    foreach ($f in $existingFields) { $existingByName[$f.name] = $f.id }

    $tableFieldIds = @{}
    $nonLinkFields = @($tableDef.fields | Where-Object { $_.type -ne "link_row" -and $_.type -ne "formula" })
    $linkFields = @($tableDef.fields | Where-Object { $_.type -eq "link_row" })
    $formulaFields = @($tableDef.fields | Where-Object { $_.type -eq "formula" })

    foreach ($fieldDef in $nonLinkFields) {
        if ($existingByName.ContainsKey($fieldDef.name)) {
            $tableFieldIds[$fieldDef.name] = $existingByName[$fieldDef.name]
            continue
        }
        if ($fieldDef.name -eq $tableDef.primary_field) { continue }

        $fieldHash = ConvertTo-PlainHashtable $fieldDef
        $created = New-GeodepoField -Token $token -TableId $table.id -FieldDef $fieldHash -TableIds $tableIds
        $tableFieldIds[$fieldDef.name] = $created.id
        Write-Host "  Alan: $($fieldDef.name)" -ForegroundColor DarkGray
    }

    foreach ($fieldDef in $linkFields) {
        if ($existingByName.ContainsKey($fieldDef.name)) {
            $tableFieldIds[$fieldDef.name] = $existingByName[$fieldDef.name]
            continue
        }
        $fieldHash = ConvertTo-PlainHashtable $fieldDef
        $created = New-GeodepoField -Token $token -TableId $table.id -FieldDef $fieldHash -TableIds $tableIds
        $tableFieldIds[$fieldDef.name] = $created.id
        Write-Host "  Link: $($fieldDef.name) -> $($fieldDef.link_table)" -ForegroundColor DarkGray
    }

    foreach ($fieldDef in $formulaFields) {
        if ($existingByName.ContainsKey($fieldDef.name)) {
            $tableFieldIds[$fieldDef.name] = $existingByName[$fieldDef.name]
            continue
        }
        $fieldHash = ConvertTo-PlainHashtable $fieldDef
        $created = New-GeodepoField -Token $token -TableId $table.id -FieldDef $fieldHash -TableIds $tableIds
        $tableFieldIds[$fieldDef.name] = $created.id
        Write-Host "  Formula: $($fieldDef.name)" -ForegroundColor DarkGray
    }

    $fieldIds[$tableDef.name] = $tableFieldIds

    if ($tableDef.views) {
        $existingViews = Invoke-GeodepoApi -Path "/api/database/views/table/$($table.id)/" -Token $token
        $existingViewNames = @($existingViews | ForEach-Object { $_.name })

        $tableViewIds = @{}
        foreach ($viewDef in $tableDef.views) {
            if ($existingViewNames -contains $viewDef.name) {
                $ev = $existingViews | Where-Object { $_.name -eq $viewDef.name } | Select-Object -First 1
                $tableViewIds[$viewDef.name] = $ev.id
                continue
            }
            $viewHash = ConvertTo-PlainHashtable $viewDef
            $view = New-GeodepoView -Token $token -TableId $table.id -ViewDef $viewHash -FieldIds $tableFieldIds
            $tableViewIds[$viewDef.name] = $view.id
            Write-Host "  View: $($viewDef.name)" -ForegroundColor DarkGray
        }
        $viewIds[$tableDef.name] = $tableViewIds
    }
}

$idMap = [ordered]@{
    workspace_id = $workspace.id
    database_id = $database.id
    tables = $tableIds
    fields = $fieldIds
    views = $viewIds
    seeded_at = (Get-Date).ToString("o")
}

Save-IdMap -Path $idMapPath -Map $idMap
Write-Host ""
Write-Host "Seed tamamlandi. ID map: $idMapPath" -ForegroundColor Green