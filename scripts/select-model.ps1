# Forensic Claw - unified model selector (PowerShell).
#
# Forensic Claw can run on a CLOUD model (Anthropic / OpenAI via OpenClaw's
# `onboard` wizard) or a LOCAL model served by Ollama on the host. This wrapper
# offers both:
#   - cloud: delegates to `onboard`.
#   - local: records the model in .env (the docker-compose `init-config` step
#            registers the Ollama provider on every start), sets it as the
#            active model, then installs Ollama + pulls the model on the host.
#
# Usage:
#   .\scripts\select-model.ps1                 # interactive menu
#   .\scripts\select-model.ps1 -Choice cloud   # run the onboard wizard
#   .\scripts\select-model.ps1 -Choice local   # configure the local model (Ollama)
#   .\scripts\select-model.ps1 -Choice local -Model 'qwen2.5-coder:14b' -ModelName 'Qwen2.5 Coder 14B'
#
# The local model MUST support tool-calling (the agent needs tools) - Gemma 2/3/4
# do NOT. Good choices: qwen3:14b (default), qwen2.5-coder:14b, llama3.1:8b.
# See docs/run-with-local-model.md for hardware notes (a discrete GPU is strongly
# recommended; 12-14B models are unusably slow on integrated-GPU / CPU-only).

param(
    # 'gemma' is accepted as a deprecated alias for 'local'.
    [ValidateSet('cloud', 'local', 'gemma')] [string]$Choice,
    [string]$Model = 'qwen3:14b',
    [string]$ModelName = 'Qwen3 14B (local)',
    # Override config dir (defaults to OPENCLAW_CONFIG_DIR in .env, else ./config).
    [string]$ConfigDir,
    # Skip the install-Ollama / pull-model / bind-host automation (config only).
    [switch]$SkipOllamaSetup
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

function Get-EnvValue {
    # Read KEY from .env, stripping any trailing inline comment.
    param([string]$Key)
    if (-not (Test-Path -LiteralPath '.env')) { return $null }
    $line = Get-Content -LiteralPath '.env' |
        Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return $null }
    return (($line -replace "^$([regex]::Escape($Key))=", '') -replace '\s+#.*$', '').Trim()
}

function Set-EnvValue {
    # Replace or append KEY=Value in .env (UTF-8, no BOM, LF line endings).
    param([string]$Key, [string]$Value)
    $lines = if (Test-Path -LiteralPath '.env') { @(Get-Content -LiteralPath '.env') } else { @() }
    $pattern = "^$([regex]::Escape($Key))="
    $found = $false
    $out = foreach ($l in $lines) { if ($l -match $pattern) { $found = $true; "$Key=$Value" } else { $l } }
    if (-not $found) { $out = @($out) + "$Key=$Value" }
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path (Get-Location).ProviderPath '.env'), (($out -join "`n") + "`n"), $enc)
}

# ---------------------------------------------------------------------------
# Resolve the config directory (mirrors docker-compose's OPENCLAW_CONFIG_DIR).
# ---------------------------------------------------------------------------
if (-not $ConfigDir) {
    $ConfigDir = Get-EnvValue 'OPENCLAW_CONFIG_DIR'
    if ([string]::IsNullOrWhiteSpace($ConfigDir)) { $ConfigDir = './config' }
}

# ---------------------------------------------------------------------------
# Interactive menu when -Choice wasn't supplied.
# ---------------------------------------------------------------------------
if (-not $Choice) {
    Write-Output "Select the model Forensic Claw should use:"
    Write-Output "  [1] Cloud provider (Anthropic / OpenAI)  - runs the onboard wizard"
    Write-Output "  [2] Local model via Ollama ($Model)      - offline, no API key, needs a good GPU"
    $sel = Read-Host "Enter 1 or 2"
    switch ($sel.Trim()) {
        '1' { $Choice = 'cloud' }
        '2' { $Choice = 'local' }
        default { Write-Output "Invalid choice '$sel' - aborting."; exit 1 }
    }
}
if ($Choice -eq 'gemma') { $Choice = 'local' }   # deprecated alias

# ---------------------------------------------------------------------------
# Cloud path: hand off to the upstream wizard unchanged.
# ---------------------------------------------------------------------------
if ($Choice -eq 'cloud') {
    Write-Output "==> launching OpenClaw onboard wizard (cloud providers)"
    docker compose run --rm openclaw-cli onboard
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Local path. The Ollama provider itself is registered by docker-compose's
# init-config step (reading OPENCLAW_LOCAL_MODEL); here we just record the
# choice and make it the active model.
# ---------------------------------------------------------------------------
$ref = "ollama/$Model"
$openclawPath = Join-Path $ConfigDir 'openclaw.json'

function Write-JsonNoBom {
    param($Object, [string]$Path)
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { $Path }
            else { Join-Path (Get-Location).ProviderPath $Path }
    $full = [System.IO.Path]::GetFullPath($full)
    if (Test-Path -LiteralPath $full) { Copy-Item -LiteralPath $full -Destination "$full.bak" -Force }
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($full, ($Object | ConvertTo-Json -Depth 40), $enc)
}

function New-GatewayToken {
    $t = Get-EnvValue 'OPENCLAW_GATEWAY_TOKEN'
    if (-not [string]::IsNullOrWhiteSpace($t)) { return $t }
    $b = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return (-join ($b | ForEach-Object { '{0:x2}' -f $_ }))
}

# 1. Record the model in .env so init-config registers the matching provider.
Write-Output "==> recording local model in .env (OPENCLAW_LOCAL_MODEL=$Model)"
Set-EnvValue 'OPENCLAW_LOCAL_MODEL' $Model
Set-EnvValue 'OPENCLAW_LOCAL_MODEL_NAME' $ModelName

# 2. Make it the active model in openclaw.json (scaffold a baseline if missing).
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
$o.agents.defaults | Add-Member -NotePropertyName 'models' -NotePropertyValue ([pscustomobject]@{ $ref = [pscustomobject]@{} }) -Force
$o.agents.defaults.model | Add-Member -NotePropertyName 'primary' -NotePropertyValue $ref -Force
Write-JsonNoBom $o $openclawPath

Write-Output ""
Write-Output "Configured Forensic Claw to use $ModelName ($ref)."

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
            Write-Output "     .\scripts\select-model.ps1 -Choice local"
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

    # 3. Pull the model. Ollama writes progress and warnings to stderr; with
    # $ErrorActionPreference='Stop' and a redirected/merged stream those lines
    # get wrapped as terminating NativeCommandErrors, which would abort the pull
    # on the first warning. Relax it just for this native call.
    Write-Output "==> pulling $Model (first run downloads several GB)"
    $eapBak = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $ollama pull $Model } finally { $ErrorActionPreference = $eapBak }
    if ($LASTEXITCODE -ne 0) {
        Write-Output "!! 'ollama pull $Model' failed - check the model tag and that Ollama is running."
        # Best-effort: don't let a failed pull abort the caller (start.ps1).
        $global:LASTEXITCODE = 0
    }
}

Write-Output ""
Write-Output "Done. Start (or restart) the gateway to load the model:"
Write-Output "  docker compose up -d --force-recreate openclaw-gateway"
Write-Output "  (or just re-run .\start.ps1)"
