# Baserow Dockerfile'larindan Railway uyumlu surumler uretir (sadece cache mount kaldirilir).
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Convert-RailwayDockerfile {
    param([string]$Source, [string]$Destination)
    $result = New-Object System.Collections.Generic.List[string]
    $lines = Get-Content $Source

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^\s+--mount=type=cache') {
            continue
        }

        if ($line -match '^RUN --mount=type=cache') {
            $next = $i + 1
            while ($next -lt $lines.Count -and $lines[$next] -match '^\s+--mount=type=cache') {
                $next++
            }
            if ($next -lt $lines.Count -and $lines[$next] -match '^\s+--mount=type=bind') {
                $result.Add('RUN ' + $lines[$next].TrimStart())
                $i = $next
            } else {
                if ($next -lt $lines.Count) {
                    $result.Add('RUN ' + $lines[$next].TrimStart())
                    $i = $next
                }
            }
            continue
        }

        $result.Add($line)
    }

    [System.IO.File]::WriteAllText($Destination, ($result -join "`n") + "`n")
}

Convert-RailwayDockerfile `
    (Join-Path $RepoRoot "baserow\backend\Dockerfile") `
    (Join-Path $RepoRoot "baserow\Dockerfile.railway-backend")

Convert-RailwayDockerfile `
    (Join-Path $RepoRoot "baserow\web-frontend\Dockerfile") `
    (Join-Path $RepoRoot "baserow\Dockerfile.railway-frontend")

Write-Host "Uretildi: baserow/Dockerfile.railway-backend" -ForegroundColor Green
Write-Host "Uretildi: baserow/Dockerfile.railway-frontend" -ForegroundColor Green