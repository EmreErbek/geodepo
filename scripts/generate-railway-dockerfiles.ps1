# Baserow Dockerfile'larindan Railway uyumlu surumler uretir.
# Railway Metal builder BuildKit mount'lari desteklemez (cache + bind).
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Get-UnixParentPath {
    param([string]$Path)
    $idx = $Path.LastIndexOf('/')
    if ($idx -le 0) { return $Path }
    return $Path.Substring(0, $idx)
}

function Get-RunBlockEndIndex {
    param([string[]]$Lines, [int]$StartIndex)
    $end = $StartIndex
    while ($end -lt $Lines.Count -and $Lines[$end] -match '\\\s*$') {
        $end++
    }
    return $end
}

function Convert-RunBlockForRailway {
    param([string[]]$RunLines)

    $fullBlock = $RunLines -join "`n"
    $bindPattern = '--mount=type=bind,source=([^,]+),target=([^\s\\]+)'
    $bindMatches = [regex]::Matches($fullBlock, $bindPattern)

    $copyLines = New-Object System.Collections.Generic.List[string]
    if ($bindMatches.Count -gt 0) {
        $byDestDir = [ordered]@{}
        foreach ($m in $bindMatches) {
            $source = $m.Groups[1].Value
            $target = $m.Groups[2].Value
            $destDir = Get-UnixParentPath -Path $target
            if (-not $byDestDir.Contains($destDir)) {
                $byDestDir[$destDir] = [System.Collections.Generic.List[string]]::new()
            }
            if (-not $byDestDir[$destDir].Contains($source)) {
                [void]$byDestDir[$destDir].Add($source)
            }
        }
        foreach ($destDir in $byDestDir.Keys) {
            $sources = ($byDestDir[$destDir] -join ' ')
            $copyLines.Add("COPY --chown=`$UID:`$GID $sources $destDir/")
        }
    }

    $cmdLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $RunLines) {
        if ($line -match '^\s*--mount=') { continue }

        $stripped = [regex]::Replace(
            $line,
            '(^RUN\s+)(?:--mount=type=(?:cache|bind)[^\s\\]+\s*)+',
            'RUN '
        )
        $stripped = $stripped.TrimEnd()
        if ($stripped -match '^RUN\s*\\?\s*$') { continue }
        if ($stripped) {
            [void]$cmdLines.Add($stripped)
        }
    }

    if ($cmdLines.Count -eq 0) {
        throw "RUN blogu komut satiri icermiyor: $fullBlock"
    }

    if ($cmdLines[0] -notmatch '^RUN\s') {
        $cmdLines[0] = 'RUN ' + $cmdLines[0].TrimStart()
    }

    return $copyLines, ($cmdLines -join "`n")
}

function Convert-RailwayDockerfile {
    param([string]$Source, [string]$Destination)

    $result = New-Object System.Collections.Generic.List[string]
    $lines = Get-Content $Source

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^\s+--mount=type=cache') {
            continue
        }

        if ($line -match '^RUN\s+--mount=') {
            $end = Get-RunBlockEndIndex -Lines $lines -StartIndex $i
            $runLines = $lines[$i..$end]
            $copyLines, $cleanRun = Convert-RunBlockForRailway -RunLines $runLines
            foreach ($copyLine in $copyLines) {
                $result.Add($copyLine)
            }
            $result.Add($cleanRun)
            $i = $end
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