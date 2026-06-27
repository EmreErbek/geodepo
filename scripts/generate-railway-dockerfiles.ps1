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

function Add-FrontendSymlinkFixes {
    param([string]$DockerfilePath)

    $symlinkFix = @(
        ''
        '# Windows git checkout stores symlinks as plain text files'
        'RUN rm -f /baserow/web-frontend/i18n/locales && ln -s ../locales /baserow/web-frontend/i18n/locales'
    ) -join "`n"

    $content = Get-Content $DockerfilePath -Raw
    $patterns = @(
        '(COPY --chown=\$UID:\$GID \./web-frontend /baserow/web-frontend/\r?\n)',
        '(COPY --chown=\$UID:\$GID web-frontend /baserow/web-frontend\r?\n)'
    )

    foreach ($pattern in $patterns) {
        $content = [regex]::Replace(
            $content,
            "($pattern)(?!\r?\n\r?\n# Windows git checkout stores symlinks)",
            "`$1$symlinkFix`n",
            1
        )
    }

    [System.IO.File]::WriteAllText($DockerfilePath, $content)
}

Add-FrontendSymlinkFixes (Join-Path $RepoRoot "baserow\Dockerfile.railway-frontend")

function Remove-PremiumEnterpriseFromDockerfile {
    param([string]$DockerfilePath, [switch]$IsFrontend)

    $lines = Get-Content $DockerfilePath
    $result = New-Object System.Collections.Generic.List[string]
    $skipping = $false

    foreach ($line in $lines) {
        if ($skipping) {
            if ($line -notmatch '\\\s*$') { $skipping = $false }
            if ($skipping) { continue }
        }

        if ($line -match 'PYTHONPATH=.*(premium|enterprise)') {
            $suffix = if ($line -match '\\\s*$') { ' \' } else { '' }
            if ($line -match 'tests') {
                $line = "    PYTHONPATH=`"/baserow/backend/src:/baserow/backend/tests`"$suffix"
            } else {
                $line = "    PYTHONPATH=`"/baserow/backend/src`"$suffix"
            }
            $result.Add($line)
            continue
        }

        if ($line -match '(?i)(COPY|RUN ln -s|RUN mkdir|rm -rf|--from=builder-prod /baserow/premium|/baserow/enterprise)') {
            if ($line -match '(?i)premium|enterprise') {
                if ($line -match '\\\s*$') { $skipping = $true }
                continue
            }
        }

        if ($line -match '(?i)premium|enterprise') { continue }

        $fixed = $line
        $fixed = $fixed -replace 'RUN mkdir -p /baserow/web-frontend /baserow/premium/web-frontend /baserow/enterprise/web-frontend', 'RUN mkdir -p /baserow/web-frontend'
        $fixed = $fixed -replace 'RUN mkdir -p /baserow/backend/docker /baserow/premium/ /baserow/enterprise/ /baserow/media', 'RUN mkdir -p /baserow/backend/docker /baserow/media'
        $fixed = $fixed -replace 'RUN mkdir -p /baserow/backend/reports /baserow/premium/backend /baserow/enterprise/backend /baserow/media', 'RUN mkdir -p /baserow/backend/reports /baserow/media'
        $result.Add($fixed)
    }

    $content = ($result -join "`n") + "`n"
    if ($IsFrontend -and $content -notmatch 'ENV BASEROW_OSS_ONLY=true') {
        $content = $content -replace '(RUN yarn run build)', "ENV BASEROW_OSS_ONLY=true`n`$1"
    }
    if (-not $IsFrontend -and $content -notmatch 'DJANGO_SETTINGS_MODULE=''baserow.config.settings.base''') {
        $content = $content -replace '(PATH="/baserow/venv/bin:\$PATH" \\\r?\n)(\r?\n# Runtime dependencies only)', "`$1    PYTHONPATH=`"/baserow/backend/src`" \`n    DJANGO_SETTINGS_MODULE='baserow.config.settings.base' \`n    BASEROW_OSS_ONLY=true`n`$2"
    }

    [System.IO.File]::WriteAllText($DockerfilePath, $content)
}

Remove-PremiumEnterpriseFromDockerfile (Join-Path $RepoRoot "baserow\Dockerfile.railway-backend")
Remove-PremiumEnterpriseFromDockerfile (Join-Path $RepoRoot "baserow\Dockerfile.railway-frontend") -IsFrontend

Write-Host "Uretildi: baserow/Dockerfile.railway-backend" -ForegroundColor Green
Write-Host "Uretildi: baserow/Dockerfile.railway-frontend" -ForegroundColor Green