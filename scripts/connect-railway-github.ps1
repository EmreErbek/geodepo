# Railway GitHub App'e geodepo reposunu ekledikten sonra calistirin.
# 1) https://github.com/settings/installations adresine gidin
# 2) "Railway App" -> Configure -> Repository access -> geodepo secin -> Save
# 3) Bu scripti calistirin

$ErrorActionPreference = "Stop"
$token = (Get-Content "$env:USERPROFILE\.railway\config.json" -Raw | ConvertFrom-Json).user.accessToken
$repo = "EmreErbek/geodepo"
$branch = "main"

$services = @(
    "dfaf061c-c264-49b2-8013-a844b9182e1b",
    "e1825ca7-e907-4cfa-8b7a-8c66be4af7f2",
    "a7852707-f94e-4457-b703-621f58e72dcb",
    "982ebb27-6e89-4c97-8585-55b54190a934"
)

function Invoke-RailwayGql($Query, $Variables) {
    $payload = @{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10 -Compress
    $tmp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmp, $payload, [System.Text.UTF8Encoding]::new($false))
    try {
        ($resp = curl.exe -s -X POST "https://backboard.railway.com/graphql/v2" -H "Authorization: Bearer $token" -H "Content-Type: application/json" --data-binary "@$tmp") | Out-Null
        return $resp | ConvertFrom-Json
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

foreach ($id in $services) {
    $r = Invoke-RailwayGql 'mutation($id: String!, $input: ServiceConnectInput!) { serviceConnect(id: $id, input: $input) { id } }' @{
        id = $id; input = @{ repo = $repo; branch = $branch }
    }
    if ($r.errors) { throw "service $id : $($r.errors[0].message)" }
    Write-Host "[OK] GitHub baglandi: $id" -ForegroundColor Green
}

& (Join-Path $PSScriptRoot "apply-railway-build-settings.ps1")

$envId = "2b783f63-147c-4ffd-a3b4-561dae688c02"
foreach ($id in $services) {
    $d = Invoke-RailwayGql 'mutation($serviceId: String!, $environmentId: String!) { serviceInstanceDeployV2(serviceId: $serviceId, environmentId: $environmentId) }' @{
        serviceId = $id; environmentId = $envId
    }
    if ($d.errors) { Write-Host "Deploy uyari $id : $($d.errors[0].message)" -ForegroundColor Yellow }
    else { Write-Host "Deploy tetiklendi: $id" -ForegroundColor Green }
}