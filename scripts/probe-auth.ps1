$ErrorActionPreference = "Stop"
$email = $env:GEODEPO_BASEROW_EMAIL
$password = $env:GEODEPO_BASEROW_PASSWORD
if (-not $email -or -not $password) { throw "Set GEODEPO_BASEROW_EMAIL and GEODEPO_BASEROW_PASSWORD" }
$tmp = [System.IO.Path]::GetTempFileName()
$body = (@{ username = $email; password = $password } | ConvertTo-Json -Compress)
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding $false))
$auth = curl.exe -s --max-time 30 -w "`nHTTP=%{http_code}" -X POST "$env:GEODEPO_BASEROW_URL/api/user/token-auth/" -H "Content-Type: application/json" --data-binary "@$tmp"
Remove-Item $tmp
Write-Host $auth
if ($auth -notmatch 'HTTP=200') { exit 1 }
$token = (($auth -split "`n" | Select-Object -First 1) | ConvertFrom-Json).token
$tables = curl.exe -s --max-time 30 -H "Authorization: JWT $token" "$env:GEODEPO_BASEROW_URL/api/database/tables/database/7/"
Write-Host "TABLES:"
Write-Host $tables