# Forensic Claw - one-shot start (PowerShell port of start.sh).
# Runs on Windows PowerShell 5.1+, Windows PS Core (pwsh), and Linux/macOS pwsh.
# Pass-through args go to `docker compose up`. Common ones:
#   .\start.ps1                  # plain start (prompts for a model on first run)
#   .\start.ps1 -SelectModel     # (re)choose the model: cloud or local
#   .\start.ps1 -Model local     # switch to the local model (Ollama), non-interactive
#   .\start.ps1 -Model cloud     # run the cloud onboard wizard
#   .\start.ps1 --build          # rebuild image first (after Dockerfile change)
#   .\start.ps1 --force-recreate # recreate containers (after .env change)

[CmdletBinding(PositionalBinding = $false)]
param(
    # Force the model picker even if one is already configured.
    [switch]$SelectModel,
    # Pick a model non-interactively: 'cloud' (onboard wizard) or 'local' (Ollama).
    # 'gemma' is accepted as a deprecated alias for 'local'.
    [ValidateSet('cloud', 'local', 'gemma')] [string]$Model,
    # Everything else is passed straight through to `docker compose up`.
    [Parameter(ValueFromRemainingArguments = $true)] $ComposeArgs
)

$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

if ($null -eq $ComposeArgs) { $ComposeArgs = @() }

if (-not (Test-Path -LiteralPath '.env')) {
    Write-Output "==> .env missing - copying from .env.example"
    Copy-Item -LiteralPath '.env.example' -Destination '.env'
    Write-Output "    edit .env to add your API key + OPENCLAW_CASES_HOST_PATH, then re-run .\start.ps1"
    exit 1
}

& (Join-Path $PSScriptRoot 'scripts/setup-workspace.ps1')
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }

# ---------------------------------------------------------------------------
# Model selection. Auto-prompts on first run (no model configured yet); stays
# silent once a model is set. Force it anytime with -SelectModel / -Model.
# ---------------------------------------------------------------------------
$configDir = './config'
$cfgLine = Get-Content -LiteralPath '.env' |
    Where-Object { $_ -match '^OPENCLAW_CONFIG_DIR=' } | Select-Object -First 1
if ($cfgLine) {
    # Strip the key, any trailing inline comment (` # ...`, like docker compose
    # does), and surrounding whitespace.
    $v = (($cfgLine -replace '^OPENCLAW_CONFIG_DIR=', '') -replace '\s+#.*$', '').Trim()
    if (-not [string]::IsNullOrWhiteSpace($v)) { $configDir = $v }
}
$openclawPath = Join-Path $configDir 'openclaw.json'

$primary = $null
if (Test-Path -LiteralPath $openclawPath) {
    try { $primary = (Get-Content -Raw -LiteralPath $openclawPath | ConvertFrom-Json).agents.defaults.model.primary }
    catch { $primary = $null }
}

$selector = Join-Path $PSScriptRoot 'scripts/select-model.ps1'
$modelChanged = $false
if ($SelectModel -or $Model) {
    if ($Model) { & $selector -Choice $Model } else { & $selector }
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
    $modelChanged = $true
} elseif (-not $primary) {
    if (-not [Environment]::UserInteractive) {
        Write-Output "==> no model configured and this isn't an interactive session."
        Write-Output "    run:  .\start.ps1 -Model local   (or -Model cloud)"
        exit 1
    }
    Write-Output ""
    Write-Output "==> no model configured yet"
    & $selector
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
    $modelChanged = $true
} else {
    # The local Ollama provider is re-registered on every `docker compose up` by
    # the init-config step, so nothing to re-apply here - just report.
    Write-Output "==> model: $primary  (use .\start.ps1 -SelectModel to change)"
}

# A config change only takes effect on a fresh container, so recreate.
if ($modelChanged -and ($ComposeArgs -notcontains '--force-recreate')) {
    $ComposeArgs += '--force-recreate'
}

$port = '18789'
$portLine = Get-Content -LiteralPath '.env' |
    Where-Object { $_ -match '^OPENCLAW_GATEWAY_PORT=' } |
    Select-Object -First 1
if ($portLine) {
    $envPort = (($portLine -replace '^OPENCLAW_GATEWAY_PORT=', '') -replace '\s+#.*$', '').Trim()
    if (-not [string]::IsNullOrWhiteSpace($envPort)) { $port = $envPort }
}

Write-Output ""
Write-Output "==> docker compose up -d openclaw-gateway $($ComposeArgs -join ' ')"
docker compose up -d openclaw-gateway @ComposeArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output ""
Write-Output "==> waiting for gateway healthcheck"
for ($i = 1; $i -le 12; $i++) {
    $containerId = docker compose ps -q openclaw-gateway 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($containerId)) {
        $s = docker inspect $containerId --format '{{.State.Health.Status}}' 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($s)) { $s = 'missing' }
    } else {
        $s = 'missing'
    }
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
