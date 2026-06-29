# GEO DEPO Dashboard kokpit onarimi: integration + widget data source rebuild
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\geodepo-api.ps1"

$cfg = Get-GeodepoConfig
$token = Get-GeodepoToken
$dashboardId = 14

$idMap = Get-Content (Join-Path $cfg.Root 'deploy\geodepo\focus-lists-id-map.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$devamRecordType = [int]$idMap.fields.'Devam Eden İşler'.'Kayıt Türü'

Write-Host "=== Dashboard integration ===" -ForegroundColor Cyan
$ints = Invoke-GeodepoApi -Path "/api/application/$dashboardId/integrations/" -Token $token
if (-not $ints -or @($ints).Count -eq 0) {
    $int = Invoke-GeodepoApi -Method POST -Path "/api/application/$dashboardId/integrations/" -Token $token -Body @{
        type = 'local_baserow'
        name = 'Local Baserow'
    }
    Write-Host "Integration olusturuldu: $($int.id)"
} else {
    Write-Host "Mevcut integration: $($ints[0].id)"
}

$widgetsCfg = @(
    @{ title = 'Açık Teklifler'; table = [int]$idMap.tables.Teklif; field = [int]$idMap.fields.Teklif.'Teklif Adı'; filters = @() },
    @{ title = 'Devam Eden Projeler'; table = [int]$idMap.tables.'Devam Eden İşler'; field = [int]$idMap.fields.'Devam Eden İşler'.'Görev Adı'; filters = @() },
    @{ title = 'Ödeme Kayıtları'; table = [int]$idMap.tables.'Ödeme Takibi'; field = [int]$idMap.fields.'Ödeme Takibi'.'Kayıt Adı'; filters = @() }
)

$existing = Invoke-GeodepoApi -Path "/api/dashboard/$dashboardId/widgets/" -Token $token
$dataSources = @{}
foreach ($ds in @(Invoke-GeodepoApi -Path "/api/dashboard/$dashboardId/data-sources/" -Token $token)) {
    $dataSources[[string]$ds.id] = $ds
}

foreach ($wcfg in $widgetsCfg) {
    $widget = @($existing | Where-Object { $_.title -eq $wcfg.title } | Select-Object -First 1)
    if ($widget) {
        $ds = $dataSources[[string]$widget.data_source_id]
        if (-not $ds -or -not $ds.integration_id) {
            Write-Host "Widget yeniden olusturuluyor (integration eksik): $($wcfg.title)" -ForegroundColor Yellow
            Invoke-GeodepoApi -Method DELETE -Path "/api/dashboard/widgets/$($widget.id)/" -Token $token | Out-Null
            $widget = $null
        }
    }
    if (-not $widget) {
        $widget = Invoke-GeodepoApi -Method POST -Path "/api/dashboard/$dashboardId/widgets/" -Token $token -Body @{
            title = $wcfg.title
            description = ''
            type = 'summary'
        }
        Write-Host "Widget olusturuldu: $($wcfg.title) #$($widget.id)"
    } else {
        Write-Host "Mevcut widget: $($wcfg.title) #$($widget.id)"
    }

    $body = @{
        table_id = $wcfg.table
        field_id = $wcfg.field
        aggregation_type = 'count'
        filters = $wcfg.filters
        filter_type = 'AND'
    }
    Invoke-GeodepoApi -Method PATCH -Path "/api/dashboard/data-sources/$($widget.data_source_id)/" -Token $token -Body $body | Out-Null

    $dispatch = Invoke-GeodepoApi -Method POST -Path "/api/dashboard/data-sources/$($widget.data_source_id)/dispatch/" -Token $token -Body @{}
    $val = if ($dispatch.data) { $dispatch.data.value } else { $dispatch }
    Write-Host "Dispatch OK: $($wcfg.title) -> $val" -ForegroundColor Green
}

Write-Host "Dashboard onarimi tamam." -ForegroundColor Green