# Railway servislerini EmreErbek/geodepo reposundan kaynak koddan build edecek sekilde ayarlar.
$ErrorActionPreference = "Stop"

$token = (Get-Content "$env:USERPROFILE\.railway\config.json" -Raw | ConvertFrom-Json).user.accessToken
if (-not $token) { throw "Railway token bulunamadi. railway login calistirin." }

$envId = "2b783f63-147c-4ffd-a3b4-561dae688c02"
$repo = "EmreErbek/geodepo"
$branch = "main"

$services = @(
    @{
        Id = "dfaf061c-c264-49b2-8013-a844b9182e1b"
        Name = "Baserow Backend"
        Config = "/deploy/railway/backend.toml"
        Dockerfile = "Dockerfile.railway-backend"
        Start = $null
    },
    @{
        Id = "e1825ca7-e907-4cfa-8b7a-8c66be4af7f2"
        Name = "Baserow Frontend"
        Config = "/deploy/railway/frontend.toml"
        Dockerfile = "Dockerfile.railway-frontend"
        Start = $null
    },
    @{
        Id = "a7852707-f94e-4457-b703-621f58e72dcb"
        Name = "Celery Worker"
        Config = "/deploy/railway/celery-worker.toml"
        Dockerfile = "Dockerfile.railway-backend"
        Start = "celery-worker"
    },
    @{
        Id = "982ebb27-6e89-4c97-8585-55b54190a934"
        Name = "Celery Beat"
        Config = "/deploy/railway/celery-beat.toml"
        Dockerfile = "Dockerfile.railway-backend"
        Start = "/baserow/backend/docker/docker-entrypoint.sh celery-beat"
    }
)

function Invoke-RailwayGql {
    param([string]$Query, [hashtable]$Variables = @{})
    $payload = @{ query = $Query }
    if ($Variables.Count -gt 0) { $payload.variables = $Variables }
    $json = $payload | ConvertTo-Json -Depth 10 -Compress
    $tmp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    try {
        $resp = curl.exe -s -X POST "https://backboard.railway.com/graphql/v2" `
            -H "Authorization: Bearer $token" `
            -H "Content-Type: application/json" `
            --data-binary "@$tmp"
        return $resp | ConvertFrom-Json
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

foreach ($svc in $services) {
    Write-Host ""
    Write-Host "=== $($svc.Name) ===" -ForegroundColor Cyan

    $connect = Invoke-RailwayGql -Query 'mutation($id: String!, $input: ServiceConnectInput!) { serviceConnect(id: $id, input: $input) { id } }' -Variables @{
        id = $svc.Id
        input = @{ repo = $repo; branch = $branch }
    }
    if ($connect.errors) {
        throw "GitHub baglantisi basarisiz ($($svc.Name)): $($connect.errors[0].message)"
    }
    Write-Host "GitHub repo baglandi: $repo"

    $input = @{
        rootDirectory = "baserow"
        railwayConfigFile = $svc.Config
        dockerfilePath = $svc.Dockerfile
        builder = "DOCKERFILE"
        watchPatterns = @("backend/**", "web-frontend/**", "deploy/**", "Dockerfile.railway-backend", "Dockerfile.railway-frontend")
    }
    if ($svc.Start) { $input.startCommand = $svc.Start }

    $update = Invoke-RailwayGql -Query 'mutation($serviceId: String!, $environmentId: String!, $input: ServiceInstanceUpdateInput!) { serviceInstanceUpdate(serviceId: $serviceId, environmentId: $environmentId, input: $input) }' -Variables @{
        serviceId = $svc.Id
        environmentId = $envId
        input = $input
    }
    if ($update.errors) {
        throw "Ayar guncelleme basarisiz ($($svc.Name)): $($update.errors[0].message)"
    }
    Write-Host "Build ayarlari guncellendi."

    $deploy = Invoke-RailwayGql -Query 'mutation($serviceId: String!, $environmentId: String!) { serviceInstanceDeployV2(serviceId: $serviceId, environmentId: $environmentId) }' -Variables @{
        serviceId = $svc.Id
        environmentId = $envId
    }
    if ($deploy.errors) {
        Write-Host "Deploy tetiklenemedi: $($deploy.errors[0].message)" -ForegroundColor Yellow
    } else {
        Write-Host "Deploy tetiklendi: $($deploy.data.serviceInstanceDeployV2)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Tamam. Build loglari icin: railway logs -s 'Baserow Frontend'" -ForegroundColor Green