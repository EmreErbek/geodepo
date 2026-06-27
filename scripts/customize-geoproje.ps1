# Geoproje fork: premium/enterprise kaldir, Baserow markasini Geoproje yap.
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$BaserowDir = Join-Path $RepoRoot "baserow"

function Remove-PremiumEnterpriseDirs {
    foreach ($dir in @("premium", "enterprise")) {
        $path = Join-Path $BaserowDir $dir
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path
            Write-Host "Silindi: baserow/$dir" -ForegroundColor Yellow
        }
    }
}

function Update-BackendPackaging {
    $pyproject = Join-Path $BaserowDir "backend\pyproject.toml"
    $content = Get-Content $pyproject -Raw
    $content = $content -replace 'known-first-party = \["baserow", "baserow_premium", "baserow_enterprise"\]', 'known-first-party = ["baserow"]'
    $content = $content -replace '(?ms)\[tool\.uv\.workspace\]\r?\nmembers = \[[^\]]*\]\r?\n\r?\n', ''
    $content = $content -replace '(?ms)pythonpath = \[\r?\n    "tests",\r?\n    "\.\./premium/backend/tests",\r?\n    "\.\./enterprise/backend/tests",\r?\n\]', 'pythonpath = ["tests"]'
    [System.IO.File]::WriteAllText($pyproject, $content)

    $lock = Join-Path $BaserowDir "backend\uv.lock"
    $lockContent = Get-Content $lock -Raw
    $lockContent = $lockContent -replace '(?ms)\[manifest\]\r?\nmembers = \[\r?\n    "baserow",\r?\n    "baserow-enterprise",\r?\n    "baserow-premium",\r?\n\]', "[manifest]`nmembers = [`n    `"baserow`",`n]"
    $lockContent = $lockContent -replace '(?ms)\[\[package\]\]\r?\nname = "baserow-enterprise"[^\[]*', ''
    $lockContent = $lockContent -replace '(?ms)\[\[package\]\]\r?\nname = "baserow-premium"[^\[]*', ''
    [System.IO.File]::WriteAllText($lock, $lockContent)
    Write-Host "Guncellendi: backend/pyproject.toml, backend/uv.lock" -ForegroundColor Green
}

function Update-OssOnlyDefaults {
    $basePy = Join-Path $BaserowDir "backend\src\baserow\config\settings\base.py"
    $content = Get-Content $basePy -Raw
    $ossBlock = @'

# Geoproje fork: premium/enterprise repodan kaldirildi
BASEROW_OSS_ONLY = True
BASEROW_BUILT_IN_PLUGINS = []
'@
    if ($content -match 'BASEROW_OSS_ONLY = bool') {
        $content = $content -replace '(?ms)BASEROW_OSS_ONLY = bool\(os\.getenv\("BASEROW_OSS_ONLY", ""\)\)\r?\nif BASEROW_OSS_ONLY:\r?\n    BASEROW_BUILT_IN_PLUGINS = \[\]\r?\nelse:\r?\n    BASEROW_BUILT_IN_PLUGINS = \["baserow_premium", "baserow_enterprise"\]\r?\n', $ossBlock
    } elseif ($content -notmatch 'BASEROW_BUILT_IN_PLUGINS') {
        $content = $content -replace '(BASEROW_BACKEND_PLUGIN_NAMES = \[d\.name for d in BASEROW_PLUGIN_FOLDERS\]\r?\n)', "`$1$ossBlock`n"
    }
    [System.IO.File]::WriteAllText($basePy, $content)

    $nuxtBase = Join-Path $BaserowDir "web-frontend\config\nuxt.config.base.ts"
    $nuxt = Get-Content $nuxtBase -Raw
    $nuxt = $nuxt -replace 'if \(!process\.env\.BASEROW_OSS_ONLY\) \{\r?\n    baseModules\.push\(\r?\n      premiumBase \+ ''/modules/baserow_premium/module\.js'',\r?\n      enterpriseBase \+ ''/modules/baserow_enterprise/module\.js''\r?\n    \)\r?\n  \}', '// Geoproje fork: premium/enterprise modulleri yuklenmez'
    [System.IO.File]::WriteAllText($nuxtBase, $nuxt)
    Write-Host "Guncellendi: OSS-only varsayilanlari" -ForegroundColor Green
}

function Update-GeoprojeBranding {
    $head = Join-Path $BaserowDir "web-frontend\modules\core\head.js"
    $headContent = Get-Content $head -Raw
    $headContent = $headContent -replace "title: 'Baserow'", "title: 'Geoproje'"
    $headContent = $headContent -replace "titleTemplate: '%s \| Baserow'", "titleTemplate: '%s | Geoproje'"
    [System.IO.File]::WriteAllText($head, $headContent)

    $localeRoot = Join-Path $BaserowDir "web-frontend"
    Get-ChildItem -Path $localeRoot -Recurse -Filter "*.json" | Where-Object {
        $_.FullName -match '\\locales\\'
    } | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        if ($text -match 'Baserow') {
            $text = $text -replace 'Baserow', 'Geoproje'
            [System.IO.File]::WriteAllText($_.FullName, $text)
        }
    }

    $vuePatches = @{
        "web-frontend\modules\core\components\ExternalLinkBaserowLogo.vue" = @{
            'href="https://baserow.io"' = 'href="https://geoproje.com.tr"'
            'Baserow - open source no-code database tool and Airtable alternative' = 'Geoproje'
        }
        "web-frontend\modules\core\components\template\TemplateSidebar.vue" = @{
            'alt="Baserow logo"' = 'alt="Geoproje logo"'
        }
        "web-frontend\modules\core\components\notifications\BaserowVersionUpgradeNotification.vue" = @{
            '{{ `Baserow ${notification.data.version}` }}' = '{{ `Geoproje ${notification.data.version}` }}'
        }
        "web-frontend\modules\core\components\settings\McpEndpoint.vue" = @{
            '"Baserow MCP"' = '"Geoproje MCP"'
        }
        "web-frontend\modules\core\components\auth\PasswordLogin.vue" = @{
            'You visited Baserow at' = 'You visited Geoproje at'
            'mis-configured the Baserow' = 'mis-configured the Geoproje'
        }
    }

    foreach ($rel in $vuePatches.Keys) {
        $path = Join-Path $BaserowDir $rel
        if (-not (Test-Path $path)) { continue }
        $text = Get-Content $path -Raw
        foreach ($entry in $vuePatches[$rel].GetEnumerator()) {
            $text = $text -replace [regex]::Escape($entry.Key), $entry.Value
        }
        [System.IO.File]::WriteAllText($path, $text)
    }

    $logoSvg = @'
<svg xmlns="http://www.w3.org/2000/svg" width="176" height="29" viewBox="0 0 176 29">
  <defs>
    <clipPath id="clip-logo">
      <rect width="176" height="29"/>
    </clipPath>
  </defs>
  <g clip-path="url(#clip-logo)">
    <g transform="translate(0.016 0.1)">
      <path d="M1.559,0H16.526a1.559,1.559,0,0,1,1.559,1.559V5.611A1.559,1.559,0,0,1,16.526,7.17H1.559A1.559,1.559,0,0,1,0,5.611V1.559A1.559,1.559,0,0,1,1.559,0Z" transform="translate(18.169 28.835) rotate(180)" fill="#4d68c4"/>
      <path d="M1.559,0H27.441A1.559,1.559,0,0,1,29,1.559V5.611A1.559,1.559,0,0,1,27.441,7.17H1.559A1.559,1.559,0,0,1,0,5.611V1.559A1.559,1.559,0,0,1,1.559,0Z" transform="translate(29.084 18.002) rotate(180)" fill="#5190ef"/>
      <path d="M1.559,0H16.526a1.559,1.559,0,0,1,1.559,1.559V5.611A1.559,1.559,0,0,1,16.526,7.17H1.559A1.559,1.559,0,0,1,0,5.611V1.559A1.559,1.559,0,0,1,1.559,0Z" transform="translate(29.084 7.17) rotate(180)" fill="#2bc3f1"/>
      <path d="M1.559,0H5.611A1.559,1.559,0,0,1,7.17,1.559V5.611A1.559,1.559,0,0,1,5.611,7.17H1.559A1.559,1.559,0,0,1,0,5.611V1.559A1.559,1.559,0,0,1,1.559,0Z" transform="translate(29.084 28.835) rotate(180)" fill="#4d68c4"/>
      <path d="M1.559,0H5.611A1.559,1.559,0,0,1,7.17,1.559V5.611A1.559,1.559,0,0,1,5.611,7.17H1.559A1.559,1.559,0,0,1,0,5.611V1.559A1.559,1.559,0,0,1,1.559,0Z" transform="translate(0.084 0)" fill="#2bc3f1"/>
      <text x="38" y="21" font-family="Inter, system-ui, -apple-system, Segoe UI, Roboto, sans-serif" font-size="16.5" font-weight="600" fill="#202128">Geoproje</text>
    </g>
  </g>
</svg>
'@
    $logoWhiteSvg = $logoSvg -replace 'clip-logo', 'clip-logo_white' -replace 'fill="#202128">Geoproje', 'fill="#ffffff">Geoproje'
    foreach ($rel in @(
        "web-frontend\modules\core\static\img\logo.svg",
        "web-frontend\modules\core\server\public\img\logo.svg"
    )) {
        [System.IO.File]::WriteAllText((Join-Path $BaserowDir $rel), $logoSvg)
    }
    foreach ($rel in @(
        "web-frontend\modules\core\static\img\logo-white.svg",
        "web-frontend\modules\core\server\public\img\logo-white.svg"
    )) {
        [System.IO.File]::WriteAllText((Join-Path $BaserowDir $rel), $logoWhiteSvg)
    }

    Write-Host "Guncellendi: Geoproje markasi (locale + UI + logo)" -ForegroundColor Green
}

function Update-DeployConfigs {
    $patterns = @(
        "deploy\railway\backend.toml",
        "deploy\railway\frontend.toml",
        "deploy\railway\celery-worker.toml",
        "deploy\railway\celery-beat.toml"
    )
    foreach ($rel in $patterns) {
        $path = Join-Path $RepoRoot $rel
        if (-not (Test-Path $path)) { continue }
        $lines = Get-Content $path | Where-Object {
            $_ -notmatch 'premium/' -and $_ -notmatch 'enterprise/'
        }
        [System.IO.File]::WriteAllText($path, ($lines -join "`n") + "`n")
    }

    $applyScript = Join-Path $RepoRoot "scripts\apply-railway-source-config.ps1"
    if (Test-Path $applyScript) {
        $text = Get-Content $applyScript -Raw
        $text = $text -replace 'watchPatterns = @\("backend/\*\*", "premium/\*\*", "enterprise/\*\*", "web-frontend/\*\*", "deploy/\*\*"\)', 'watchPatterns = @("backend/**", "web-frontend/**", "deploy/**")'
        [System.IO.File]::WriteAllText($applyScript, $text)
    }
    Write-Host "Guncellendi: deploy/railway/*.toml" -ForegroundColor Green
}

Remove-PremiumEnterpriseDirs
Update-BackendPackaging
Update-OssOnlyDefaults
Update-GeoprojeBranding
Update-DeployConfigs

& (Join-Path $PSScriptRoot "generate-railway-dockerfiles.ps1")

Write-Host ""
Write-Host "Geoproje ozellestirmesi tamam." -ForegroundColor Green
Write-Host "Railway'de BASEROW_OSS_ONLY=true ayarini backend + frontend servislerine ekleyin." -ForegroundColor Cyan