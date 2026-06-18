# First-time workspace setup (PowerShell port of setup-workspace.sh).
# - Copies tracked *.template.md files in workspace/ to their live names
#   (only if the live file doesn't already exist - safe to re-run).
# - Seeds an EXAMPLE-001 case from cases/templates/ if missing.
# - Auto-generates OPENCLAW_GATEWAY_TOKEN in .env if blank or still set to
#   the placeholder.
# - Wires git hooks at .githooks/ via core.hooksPath.

$ErrorActionPreference = 'Stop'

Set-Location (Join-Path $PSScriptRoot '..')

Write-Output "==> seeding workspace template files"
$templates = Get-ChildItem -Path 'workspace' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*.template.md' }
foreach ($tpl in $templates) {
    $live = $tpl.FullName -replace '\.template\.md$', '.md'
    if (Test-Path -LiteralPath $live) {
        Write-Output "    skip: $live already exists"
    } else {
        Copy-Item -LiteralPath $tpl.FullName -Destination $live
        Write-Output "    seed: $live (from $($tpl.Name))"
    }
}

Write-Output "==> seeding cases/EXAMPLE-001 from cases/templates/ (if missing)"
if (-not (Test-Path -LiteralPath 'cases/EXAMPLE-001')) {
    New-Item -ItemType Directory -Force -Path `
        'cases/EXAMPLE-001/notes', `
        'cases/EXAMPLE-001/evidence', `
        'cases/EXAMPLE-001/findings', `
        'cases/EXAMPLE-001/outputs' | Out-Null
    foreach ($f in @('brief.md', 'status.json')) {
        $src = "cases/templates/$f"
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination "cases/EXAMPLE-001/$f"
        }
    }
    if (Test-Path -LiteralPath 'cases/templates/findings/findings.md') {
        Copy-Item -LiteralPath 'cases/templates/findings/findings.md' -Destination 'cases/EXAMPLE-001/findings/findings.md'
    } elseif (Test-Path -LiteralPath 'cases/templates/findings.md') {
        Copy-Item -LiteralPath 'cases/templates/findings.md' -Destination 'cases/EXAMPLE-001/findings/findings.md'
    }
    if (Test-Path -LiteralPath 'cases/templates/worklog.md') {
        Copy-Item -LiteralPath 'cases/templates/worklog.md' -Destination 'cases/EXAMPLE-001/notes/worklog.md'
    }
    Write-Output "    seeded cases/EXAMPLE-001/"
} else {
    Write-Output "    skip: cases/EXAMPLE-001/ already exists"
}

if (Test-Path -LiteralPath '.env') {
    Write-Output "==> ensuring OPENCLAW_GATEWAY_TOKEN is a real value"
    $envLines = @(Get-Content -LiteralPath '.env')
    $tokenLine = $envLines | Where-Object { $_ -match '^OPENCLAW_GATEWAY_TOKEN=' } | Select-Object -First 1
    $currentToken = if ($tokenLine) { $tokenLine -replace '^OPENCLAW_GATEWAY_TOKEN=', '' } else { '' }
    $needsRotation = ($null -eq $tokenLine) -or `
                     [string]::IsNullOrWhiteSpace($currentToken) -or `
                     ($currentToken -match '(^|\s)#')
    if ($needsRotation) {
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $newToken = -join ($bytes | ForEach-Object { '{0:x2}' -f $_ })
        if ($tokenLine) {
            $envLines = $envLines | ForEach-Object {
                if ($_ -match '^OPENCLAW_GATEWAY_TOKEN=') {
                    "OPENCLAW_GATEWAY_TOKEN=$newToken"
                } else {
                    $_
                }
            }
        } else {
            $envLines += "OPENCLAW_GATEWAY_TOKEN=$newToken"
        }
        # Write UTF-8 without BOM (docker compose parsers don't expect a BOM).
        $envPath = (Resolve-Path -LiteralPath '.env').ProviderPath
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllLines($envPath, $envLines, $utf8NoBom)
        Write-Output "    generated a fresh 64-hex-char token and wrote it to .env"
    } else {
        Write-Output "    skip: token already looks valid"
    }
} else {
    Write-Output "==> .env not present; skipping token check (run 'Copy-Item .env.example .env' first)"
}

if (Test-Path -LiteralPath '.git') {
    Write-Output "==> wiring tracked git hooks at .githooks/"
    git config core.hooksPath .githooks
    # Linux/macOS need the +x bit on hook scripts; Windows ignores file mode.
    if (Get-Command chmod -ErrorAction SilentlyContinue) {
        Get-ChildItem -Path '.githooks' -File -ErrorAction SilentlyContinue | ForEach-Object {
            chmod +x $_.FullName 2>$null
        }
    }
    Write-Output "    git hooks active (run 'git config --unset core.hooksPath' to disable)"
} else {
    Write-Output "==> skipping git hooks (no .git directory)"
}

Write-Output ""
Write-Output "workspace setup OK"
