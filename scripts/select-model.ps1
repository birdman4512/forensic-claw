# Forensic Claw - unified model selector (PowerShell).
#
# OpenClaw's built-in `onboard` wizard only knows the two CLOUD providers
# (Anthropic / OpenAI) and has no option for a local model. This wrapper adds
# that choice: pick a cloud provider (it just delegates to `onboard`) or the
# LOCAL Gemma 4 12B provider served by Ollama (it writes ./config/ directly).
#
# Usage:
#   .\scripts\select-model.ps1                 # interactive menu
#   .\scripts\select-model.ps1 -Choice cloud   # run the onboard wizard
#   .\scripts\select-model.ps1 -Choice gemma   # configure local Gemma 4 12B
#   .\scripts\select-model.ps1 -Choice gemma -Model 'gemma4:27b' -ModelName 'Gemma 4 27B'
#
# After choosing Gemma, make sure Ollama is installed and serving the model
# (see docs/run-with-gemma-4-12b.md), then restart the gateway:
#   docker compose up -d --force-recreate openclaw-gateway

param(
    [ValidateSet('cloud', 'gemma')] [string]$Choice,
    [string]$Model = 'gemma4:12b',
    [string]$ModelName = 'Gemma 4 12B (local)',
    [string]$OllamaUrl = 'http://host.docker.internal:11434/v1',
    [int]$ContextWindow = 128000,
    [int]$MaxTokens = 8192,
    # Override config dir (defaults to OPENCLAW_CONFIG_DIR in .env, else ./config).
    [string]$ConfigDir,
    # Skip the install-Ollama / pull-model / bind-host automation (config only).
    [switch]$SkipOllamaSetup
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

# ---------------------------------------------------------------------------
# Resolve the config directory (mirrors docker-compose's OPENCLAW_CONFIG_DIR).
# ---------------------------------------------------------------------------
if (-not $ConfigDir) {
    $ConfigDir = './config'
    if (Test-Path -LiteralPath '.env') {
        $line = Get-Content -LiteralPath '.env' |
            Where-Object { $_ -match '^OPENCLAW_CONFIG_DIR=' } | Select-Object -First 1
        if ($line) {
            $v = ($line -replace '^OPENCLAW_CONFIG_DIR=', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($v)) { $ConfigDir = $v }
        }
    }
}

# ---------------------------------------------------------------------------
# Interactive menu when -Choice wasn't supplied.
# ---------------------------------------------------------------------------
if (-not $Choice) {
    Write-Output "Select the model Forensic Claw should use:"
    Write-Output "  [1] Cloud provider (Anthropic / OpenAI)  - runs the onboard wizard"
    Write-Output "  [2] Local Gemma 4 12B via Ollama         - offline, no API key"
    $sel = Read-Host "Enter 1 or 2"
    switch ($sel.Trim()) {
        '1' { $Choice = 'cloud' }
        '2' { $Choice = 'gemma' }
        default { Write-Output "Invalid choice '$sel' - aborting."; exit 1 }
    }
}

# ---------------------------------------------------------------------------
# Cloud path: hand off to the upstream wizard unchanged.
# ---------------------------------------------------------------------------
if ($Choice -eq 'cloud') {
    Write-Output "==> launching OpenClaw onboard wizard (cloud providers)"
    docker compose run --rm openclaw-cli onboard
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Gemma path: write the provider + active-model selection into ./config/.
# ---------------------------------------------------------------------------
$providerId = 'ollama'
$ref = "$providerId/$Model"
$modelsPath = Join-Path $ConfigDir 'agents/main/agent/models.json'
$openclawPath = Join-Path $ConfigDir 'openclaw.json'

function Write-JsonNoBom {
    param($Object, [string]$Path)
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { $Path }
            else { Join-Path (Get-Location).ProviderPath $Path }
    $full = [System.IO.Path]::GetFullPath($full)
    if (Test-Path -LiteralPath $full) {
        Copy-Item -LiteralPath $full -Destination "$full.bak" -Force
    }
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $json = $Object | ConvertTo-Json -Depth 40
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($full, $json, $enc)
}

function New-GatewayToken {
    # Reuse the token already in .env if present so config + env stay in sync;
    # otherwise generate a fresh 64-hex-char one (matches setup-workspace).
    if (Test-Path -LiteralPath '.env') {
        $tl = Get-Content -LiteralPath '.env' |
            Where-Object { $_ -match '^OPENCLAW_GATEWAY_TOKEN=' } | Select-Object -First 1
        if ($tl) {
            $t = ($tl -replace '^OPENCLAW_GATEWAY_TOKEN=', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($t) -and $t -notmatch '(^|\s)#') { return $t }
        }
    }
    $b = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return (-join ($b | ForEach-Object { '{0:x2}' -f $_ }))
}

# models.json - load existing or start a fresh provider map (config/ is
# gitignored, so a brand-new clone has none yet).
Write-Output "==> adding '$providerId' provider ($Model) to $modelsPath"
if (Test-Path -LiteralPath $modelsPath) {
    $m = Get-Content -Raw -LiteralPath $modelsPath | ConvertFrom-Json
} else {
    Write-Output "    (no models.json yet - creating one)"
    $m = [pscustomobject]@{ providers = [pscustomobject]@{} }
}
if (-not ($m.PSObject.Properties.Name -contains 'providers')) {
    $m | Add-Member -NotePropertyName 'providers' -NotePropertyValue ([pscustomobject]@{}) -Force
}
$ollama = [ordered]@{
    baseUrl = $OllamaUrl
    apiKey  = 'ollama'
    auth    = 'api_key'
    api     = 'openai-completions'
    models  = @(
        [ordered]@{
            id            = $Model
            name          = $ModelName
            api           = 'openai-completions'
            input         = @('text', 'image')
            cost          = [ordered]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
            contextWindow = $ContextWindow
            maxTokens     = $MaxTokens
        }
    )
}
$m.providers | Add-Member -NotePropertyName $providerId -NotePropertyValue $ollama -Force
Write-JsonNoBom $m $modelsPath

Write-Output "==> setting active model to '$ref' in $openclawPath"
if (Test-Path -LiteralPath $openclawPath) {
    $o = Get-Content -Raw -LiteralPath $openclawPath | ConvertFrom-Json
} else {
    Write-Output "    (no openclaw.json yet - writing a minimal baseline)"
    $o = [pscustomobject]@{
        agents  = [pscustomobject]@{ defaults = [pscustomobject]@{
            workspace = '/home/node/.openclaw/workspace'
            models    = [pscustomobject]@{}
            model     = [pscustomobject]@{}
        } }
        gateway = [pscustomobject]@{
            mode      = 'local'
            auth      = [pscustomobject]@{ mode = 'token'; token = (New-GatewayToken) }
            port      = 18789
            bind      = 'loopback'
            controlUi = [pscustomobject]@{ allowInsecureAuth = $true }
        }
        tools   = [pscustomobject]@{ profile = 'coding' }
    }
}
if (-not $o.agents.defaults.model) {
    $o.agents.defaults | Add-Member -NotePropertyName 'model' -NotePropertyValue ([pscustomobject]@{}) -Force
}
# Add-Member -Force adds-or-overwrites, so this works whether the property
# already exists (existing config) or not (freshly scaffolded baseline).
$o.agents.defaults | Add-Member -NotePropertyName 'models' -NotePropertyValue ([pscustomobject]@{ $ref = [pscustomobject]@{} }) -Force
$o.agents.defaults.model | Add-Member -NotePropertyName 'primary' -NotePropertyValue $ref -Force
Write-JsonNoBom $o $openclawPath

Write-Output ""
Write-Output "Configured Forensic Claw to use $ModelName ($ref)."
Write-Output "Backups written alongside each file as *.bak."

# ---------------------------------------------------------------------------
# Best-effort Ollama setup: install (Windows/winget), bind to all interfaces
# so the container can reach it, and pull the model. Failures here warn but
# don't undo the config above. Skip with -SkipOllamaSetup.
# ---------------------------------------------------------------------------
function Resolve-Ollama {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
            'C:\Program Files\Ollama\ollama.exe')) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

if ($SkipOllamaSetup) {
    Write-Output ""
    Write-Output "Skipped Ollama setup (-SkipOllamaSetup). Remember to:"
    Write-Output "  ollama pull $Model;  set OLLAMA_HOST=0.0.0.0:11434;  restart Ollama"
}
else {
    $isWindows = ($env:OS -eq 'Windows_NT')
    $ollama = Resolve-Ollama

    # 1. Install if missing (Windows via winget).
    if (-not $ollama) {
        if ($isWindows -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Output ""
            Write-Output "==> Ollama not found - installing via winget"
            winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements
            $ollama = Resolve-Ollama
        }
        if (-not $ollama) {
            Write-Output ""
            Write-Output "!! Ollama isn't installed and couldn't be auto-installed here."
            Write-Output "   Install it from https://ollama.com/download, then re-run:"
            Write-Output "     .\scripts\select-model.ps1 -Choice gemma"
            return
        }
    }

    # 2. Bind to all interfaces so the gateway container can reach it.
    $needBind = ($env:OLLAMA_HOST -notmatch '0\.0\.0\.0')
    if ($needBind) {
        Write-Output "==> setting OLLAMA_HOST=0.0.0.0:11434 (so the container can reach Ollama)"
        if ($isWindows) { setx OLLAMA_HOST "0.0.0.0:11434" | Out-Null }
        $env:OLLAMA_HOST = '0.0.0.0:11434'
        Write-Output "   (a running Ollama must be restarted to pick up the new bind address)"
    }

    # 3. Pull the model.
    Write-Output "==> pulling $Model (first run downloads several GB)"
    & $ollama pull $Model
    if ($LASTEXITCODE -ne 0) {
        Write-Output "!! 'ollama pull $Model' failed - check the model tag and that Ollama is running."
    }
}

Write-Output ""
Write-Output "Done. Start (or restart) the gateway to load the model:"
Write-Output "  docker compose up -d --force-recreate openclaw-gateway"
Write-Output "  (or just re-run .\start.ps1)"
