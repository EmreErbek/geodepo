# Railway build ayarlarini GraphQL ile gunceller.
$ErrorActionPreference = "Stop"

$token = (Get-Content "$env:USERPROFILE\.railway\config.json" -Raw | ConvertFrom-Json).user.accessToken
$envId = "2b783f63-147c-4ffd-a3b4-561dae688c02"

$services = @(
    @{ Id = "dfaf061c-c264-49b2-8013-a844b9182e1b"; Name = "Baserow Backend"; Config = "/deploy/railway/backend.toml"; Dockerfile = "Dockerfile.railway-backend" },
    @{ Id = "e1825ca7-e907-4cfa-8b7a-8c66be4af7f2"; Name = "Baserow Frontend"; Config = "/deploy/railway/frontend.toml"; Dockerfile = "Dockerfile.railway-frontend" },
    @{ Id = "a7852707-f94e-4457-b703-621f58e72dcb"; Name = "Celery Worker"; Config = "/deploy/railway/celery-worker.toml"; Dockerfile = "Dockerfile.railway-backend"; Start = "celery-worker"; ClearHealthcheck = $true },
    @{ Id = "982ebb27-6e89-4c97-8585-55b54190a934"; Name = "Celery Beat"; Config = "/deploy/railway/celery-beat.toml"; Dockerfile = "Dockerfile.railway-backend"; Start = "celery-beat" }
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

foreach ($svc in $services) {
    $input = @{
        rootDirectory = "baserow"
        railwayConfigFile = $svc.Config
        dockerfilePath = $svc.Dockerfile
    }
    if ($svc.Start) { $input.startCommand = $svc.Start }
    if ($svc.Healthcheck) { $input.healthcheckPath = $svc.Healthcheck }
    if ($svc.HealthcheckTimeout) { $input.healthcheckTimeout = $svc.HealthcheckTimeout }
    if ($svc.ClearHealthcheck) { $input.healthcheckPath = $null; $input.healthcheckTimeout = $null }

    $r = Invoke-RailwayGql 'mutation($serviceId: String!, $environmentId: String!, $input: ServiceInstanceUpdateInput!) { serviceInstanceUpdate(serviceId: $serviceId, environmentId: $environmentId, input: $input) }' @{
        serviceId = $svc.Id
        environmentId = $envId
        input = $input
    }
    if ($r.errors) { throw "$($svc.Name): $($r.errors[0].message)" }
    Write-Host "[OK] $($svc.Name) -> root=baserow, config=$($svc.Config)" -ForegroundColor Green
}