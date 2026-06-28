# Geoproje Baserow REST API yardimcilari
$ErrorActionPreference = "Stop"

function ConvertTo-PlainHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [hashtable]) { return $InputObject }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-PlainHashtable $_ })
    }
    $hash = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $hash[$prop.Name] = ConvertTo-PlainHashtable $prop.Value
    }
    return $hash
}

function Get-GeodepoConfig {
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if (-not $root) { $root = (Get-Location).Path }
    if (-not (Test-Path (Join-Path $root "deploy\geodepo"))) {
        $root = Split-Path $PSScriptRoot -Parent
    }

    $envFile = Join-Path $root ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*([^#=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim()
                if (-not [string]::IsNullOrEmpty($val) -and -not (Get-Item "Env:$key" -ErrorAction SilentlyContinue)) {
                    Set-Item -Path "Env:$key" -Value $val
                }
            }
        }
    }

    $baseUrl = $env:GEODEPO_BASEROW_URL
    if (-not $baseUrl) { $baseUrl = "http://localhost:8000" }
    $baseUrl = $baseUrl.TrimEnd("/")

    return [ordered]@{
        Root = $root
        BaseUrl = $baseUrl
        Email = $env:GEODEPO_BASEROW_EMAIL
        Password = $env:GEODEPO_BASEROW_PASSWORD
        Token = $env:GEODEPO_BASEROW_TOKEN
    }
}

function Invoke-GeodepoApi {
    param(
        [string]$Method = "GET",
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = $null,
        [string]$BaseUrl = $null
    )

    if (-not $BaseUrl) {
        $cfg = Get-GeodepoConfig
        $BaseUrl = $cfg.BaseUrl
    }

    $url = "$BaseUrl$Path"
    $headers = @{ "Accept" = "application/json" }
    if ($Token) { $headers["Authorization"] = "JWT $Token" }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $bodyBytes = $null
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 20 -Compress
        $bodyBytes = $utf8NoBom.GetBytes($json)
    }

    try {
        if ($null -ne $bodyBytes) {
            $resp = Invoke-WebRequest -Uri $url -Method $Method -Headers $headers `
                -ContentType "application/json; charset=utf-8" -Body $bodyBytes -UseBasicParsing -TimeoutSec 600
            if ([string]::IsNullOrWhiteSpace($resp.Content)) { return $null }
            return $resp.Content | ConvertFrom-Json
        }
        $resp = Invoke-WebRequest -Uri $url -Method $Method -Headers $headers -UseBasicParsing -TimeoutSec 600
        if ([string]::IsNullOrWhiteSpace($resp.Content)) { return $null }
        return $resp.Content | ConvertFrom-Json
    } catch {
        $detail = $null
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream(), $utf8NoBom)
            $detail = $reader.ReadToEnd()
            $reader.Close()
        }
        if (-not $detail) { $detail = $_.ErrorDetails.Message }
        if ($detail) {
            throw "API $Method $Path failed: $detail"
        }
        throw
    }
}

function Get-GeodepoToken {
    $cfg = Get-GeodepoConfig
    if ($cfg.Token) { return $cfg.Token }
    if (-not $cfg.Email -or -not $cfg.Password) {
        throw "GEODEPO_BASEROW_TOKEN veya GEODEPO_BASEROW_EMAIL/PASSWORD gerekli (.env)"
    }
    $resp = Invoke-GeodepoApi -Method POST -Path "/api/user/token-auth/" -Body @{
        username = $cfg.Email
        password = $cfg.Password
    } -BaseUrl $cfg.BaseUrl
    return $resp.token
}

function Get-OrCreateWorkspace {
    param([string]$Token, [string]$Name)

    $workspaces = Invoke-GeodepoApi -Path "/api/workspaces/" -Token $Token
    $existing = $workspaces | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($existing) { return $existing }

    return Invoke-GeodepoApi -Method POST -Path "/api/workspaces/" -Token $Token -Body @{ name = $Name }
}

function Get-OrCreateDatabase {
    param([string]$Token, [int]$WorkspaceId, [string]$Name)

    $apps = Invoke-GeodepoApi -Path "/api/applications/workspace/$WorkspaceId/" -Token $Token
    $existing = $apps | Where-Object { $_.name -eq $Name -and $_.type -eq "database" } | Select-Object -First 1
    if ($existing) { return $existing }

    return Invoke-GeodepoApi -Method POST -Path "/api/applications/workspace/$WorkspaceId/" -Token $Token -Body @{
        name = $Name
        type = "database"
    }
}

function Get-OrCreateTable {
    param([string]$Token, [int]$DatabaseId, [string]$Name)

    $tables = Invoke-GeodepoApi -Path "/api/database/tables/database/$DatabaseId/" -Token $Token
    $existing = $tables | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($existing) { return $existing }

    return Invoke-GeodepoApi -Method POST -Path "/api/database/tables/database/$DatabaseId/" -Token $Token -Body @{
        name = $Name
    }
}

function Rename-PrimaryTableField {
    param([string]$Token, [int]$TableId, [string]$PrimaryName)

    $fields = Invoke-GeodepoApi -Path "/api/database/fields/table/$TableId/" -Token $Token
    $primary = $fields | Where-Object { $_.primary -eq $true } | Select-Object -First 1
    if (-not $primary) { return }
    if ($primary.name -eq $PrimaryName) { return }

    Invoke-GeodepoApi -Method PATCH -Path "/api/database/fields/$($primary.id)/" -Token $Token -Body @{
        name = $PrimaryName
    } | Out-Null
}

function Wait-GeodepoJob {
    param([string]$Token, [int]$JobId, [int]$MaxWaitSec = 1800)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $MaxWaitSec) {
        $job = Invoke-GeodepoApi -Path "/api/jobs/$JobId/" -Token $Token
        if ($job.state -eq "finished") { return $job }
        if ($job.state -eq "failed") { throw "Job $JobId failed: $($job.human_readable_error)" }
        Write-Host "    Job $JobId -> $($job.state) ($([int]$job.progress_percentage)%)" -ForegroundColor DarkYellow
        Start-Sleep -Seconds 5
    }
    throw "Job $JobId timeout after ${MaxWaitSec}s"
}

function New-TableAsync {
    param([string]$Token, [int]$DatabaseId, [string]$Name, [string[]]$FieldNames)
    $body = @{ name = $Name }
    if ($FieldNames -and $FieldNames.Count -gt 0) {
        $body.data = ,(@($FieldNames))
        $body.first_row_header = $true
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $json = $body | ConvertTo-Json -Depth 10 -Compress
    $bytes = $utf8NoBom.GetBytes($json)
    $baseUrl = (Get-GeodepoConfig).BaseUrl.TrimEnd('/')
    $url = "$baseUrl/api/database/tables/database/$DatabaseId/async/"
    $resp = Invoke-WebRequest -Uri $url -Method POST `
        -Headers @{ Authorization = "JWT $Token"; Accept = "application/json" } `
        -ContentType "application/json; charset=utf-8" -Body $bytes -UseBasicParsing -TimeoutSec 120
    $job = $resp.Content | ConvertFrom-Json
    Write-Host "  Async job: $($job.id)" -ForegroundColor DarkYellow
    $done = Wait-GeodepoJob -Token $Token -JobId $job.id
    if ($done.table_id) {
        return @{ id = $done.table_id; name = $Name }
    }
    $tables = Invoke-GeodepoApi -Path "/api/database/tables/database/$DatabaseId/" -Token $Token
    return $tables | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Invoke-GeodepoApiWithRetry {
    param(
        [string]$Method = "GET",
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = $null,
        [int]$MaxAttempts = 3
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            return Invoke-GeodepoApi -Method $Method -Path $Path -Body $Body -Token $Token
        } catch {
            if ($i -eq $MaxAttempts -or $_.Exception.Message -notmatch '500|502|503|504') { throw }
            Start-Sleep -Seconds (2 * $i)
        }
    }
}

function New-GeodepoField {
    param([string]$Token, [int]$TableId, [hashtable]$FieldDef, [hashtable]$TableIds)

    $body = [ordered]@{
        name = $FieldDef.name
        type = $FieldDef.type
    }

    if ($FieldDef.select_options) {
        $body.select_options = @($FieldDef.select_options)
    }
    if ($FieldDef.type -eq "link_row") {
        $linkName = $FieldDef.link_table
        if (-not $TableIds.ContainsKey($linkName)) {
            throw "link_table bulunamadi: $linkName"
        }
        $body.link_row_table_id = [int]$TableIds[$linkName]
        if ($FieldDef.link_row_multiple) { $body.link_row_multiple = $true }
    }
    if ($FieldDef.type -eq "date") {
        if ($FieldDef.date_format) { $body.date_format = $FieldDef.date_format }
        if ($null -ne $FieldDef.date_include_time) { $body.date_include_time = $FieldDef.date_include_time }
    }
    if ($FieldDef.type -eq "number") {
        if ($null -ne $FieldDef.number_decimal_places) { $body.number_decimal_places = $FieldDef.number_decimal_places }
        if ($null -ne $FieldDef.number_negative) { $body.number_negative = $FieldDef.number_negative }
    }
    if ($FieldDef.type -eq "formula") {
        $body.formula = $FieldDef.formula
        if ($FieldDef.formula_type) { $body.formula_type = $FieldDef.formula_type }
    }

    Write-Host "    API: alan olusturuluyor $($FieldDef.name) ($($FieldDef.type))..." -ForegroundColor DarkCyan
    return Invoke-GeodepoApiWithRetry -Method POST -Path "/api/database/fields/table/$TableId/" -Token $Token -Body $body
}

function New-GeodepoView {
    param([string]$Token, [int]$TableId, [hashtable]$ViewDef, [hashtable]$FieldIds)

    $body = [ordered]@{
        name = $ViewDef.name
        type = $ViewDef.type
    }
    if ($ViewDef.type -eq "kanban" -and $ViewDef.kanban_field) {
        $body.single_select_field = [int]$FieldIds[$ViewDef.kanban_field]
    }

    $view = Invoke-GeodepoApi -Method POST -Path "/api/database/views/table/$TableId/" -Token $Token -Body $body

    if ($ViewDef.filters) {
        foreach ($filter in $ViewDef.filters) {
            $fieldId = [int]$FieldIds[$filter.field]
            Invoke-GeodepoApi -Method POST -Path "/api/database/views/$($view.id)/filters/" -Token $Token -Body @{
                field = $fieldId
                type = $filter.type
                value = $filter.value
            } | Out-Null
        }
    }

    return $view
}

function Save-IdMap {
    param([string]$Path, [hashtable]$Map)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Map | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}