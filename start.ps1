# Forensic Claw - one-shot start (PowerShell port of start.sh).
# Runs on Windows PowerShell 5.1+, Windows PS Core (pwsh), and Linux/macOS pwsh.
# Pass-through args go to `docker compose up`. Common ones:
#   .\start.ps1                  # plain start
#   .\start.ps1 --build          # rebuild image first (after Dockerfile change)
#   .\start.ps1 --force-recreate # recreate containers (after .env change)

$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

if (-not (Test-Path -LiteralPath '.env')) {
    Write-Output "==> .env missing - copying from .env.example"
    Copy-Item -LiteralPath '.env.example' -Destination '.env'
    Write-Output "    edit .env to add your API key + OPENCLAW_CASES_HOST_PATH, then re-run .\start.ps1"
    exit 1
}

& (Join-Path $PSScriptRoot 'scripts/setup-workspace.ps1')
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }

Write-Output ""
Write-Output "==> docker compose up -d openclaw-gateway $($args -join ' ')"
docker compose up -d openclaw-gateway @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output ""
Write-Output "==> waiting for gateway healthcheck"
$port = if ($env:OPENCLAW_GATEWAY_PORT) { $env:OPENCLAW_GATEWAY_PORT } else { '18789' }
for ($i = 1; $i -le 12; $i++) {
    $s = docker inspect forensic-claw-openclaw-gateway-1 --format '{{.State.Health.Status}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($s)) { $s = 'missing' }
    Write-Output ("    t+{0}s: {1}" -f ($i * 5), $s)
    if ($s -eq 'healthy') {
        Write-Output ""
        Write-Output "Gateway up at http://localhost:$port"
        Write-Output "Need a launch URL with token? run:"
        Write-Output "    docker compose run --rm openclaw-cli dashboard --no-open"
        exit 0
    }
    if ($s -eq 'unhealthy') {
        Write-Output ""
        Write-Output "Gateway reported unhealthy - check logs:"
        Write-Output "    docker compose logs --tail 50 openclaw-gateway"
        exit 1
    }
    Start-Sleep -Seconds 5
}

Write-Output ""
Write-Output "Gateway didn't reach healthy within 60s - check logs:"
Write-Output "    docker compose logs --tail 50 openclaw-gateway"
exit 1
