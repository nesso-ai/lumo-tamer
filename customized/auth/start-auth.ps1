<#
PowerShell start script for lumo-tamer (authentication helper)
Runs from tools folder; switches to repo root, installs, builds, starts Chrome for CDP,
and reads back the vault encryption key from the OS keychain after authentication.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Read the vault encryption key from the Windows Credential Manager.
# Uses tools/read-vault-key.mjs (keytar, same library lumo-tamer uses).
# Returns the Base64 string, or empty string if not found/error.
function Read-VaultKey {
    $node = Get-Command -Name 'node' -ErrorAction SilentlyContinue
    if (-not $node) { return '' }
    $toolPath = Join-Path -Path $PSScriptRoot -ChildPath 'read-vault-key.mjs'
    try {
        $out = (& node $toolPath 2>$null | Out-String).Trim()
        # Only accept Base64-like output (discards the not-found message)
        if ($out -match '^[A-Za-z0-9+/]+={0,2}$') { return $out }
        return ''
    }
    catch {
        return ''
    }
}

# Convert the binary vault (sessions/vault.enc) into a Base64 text file
# (sessions/vault.key) so it can be transported via clipboard / copy-paste.
# Returns the path to the created text file, or $null on failure.
function Convert-VaultToText {
    $vaultPath = Join-Path -Path (Get-Location).Path -ChildPath 'sessions\vault.enc'
    if (-not (Test-Path -Path $vaultPath)) {
        Write-Warning "Vault file not found: $vaultPath"
        return $null
    }
    $textPath = Join-Path -Path (Get-Location).Path -ChildPath 'sessions\vault.key'
    try {
        $bytes = [IO.File]::ReadAllBytes($vaultPath)
        $base64 = [Convert]::ToBase64String($bytes)
        Set-Content -Path $textPath -Value $base64 -NoNewline -Encoding ascii
        return $textPath
    }
    catch {
        Write-Warning "Could not convert vault to text: $($_.Exception.Message)"
        return $null
    }
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    # Ensure we run from the repository root (two levels up from customized/auth)
    $repoRoot = Join-Path -Path $scriptDir -ChildPath '..\\..'
    Push-Location -Path $repoRoot

    Write-Host '=== lumo-tamer: Install dependencies ==='
    & npm install
    if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }

    Write-Host '=== lumo-tamer: Build (JS) ==='
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw 'npm run build failed' }

    Write-Host '=== lumo-tamer: Build login (Go) ==='
    $buildLogin = Join-Path -Path $scriptDir -ChildPath 'build-login.ps1'
    if (Test-Path -Path $buildLogin) {
        Write-Host "Running $buildLogin"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $buildLogin
        if ($LASTEXITCODE -ne 0) { throw 'build-login.ps1 failed' }
    }
    else {
        Write-Warning "build-login.ps1 not found at $buildLogin — skipping Go build"
    }

    Write-Host '=== lumo-tamer: Copy default config to dist ==='
    if (-not (Test-Path -Path dist)) { New-Item -ItemType Directory -Path dist | Out-Null }
    Copy-Item -Path "$repoRoot\config.defaults.yaml" -Destination "$repoRoot\config.defaults.yaml.bak" -Force
    Copy-Item -Path "$repoRoot\customized\auth\config.defaults.yaml" -Destination "$repoRoot\config.defaults.yaml" -Force

    Write-Host '=== lumo-tamer: Link CLI globally ==='
    & npm link
    if ($LASTEXITCODE -ne 0) { Write-Warning 'npm link returned non-zero exit code, continuing' }

    Write-Host ''
    Write-Host 'Done: build and setup complete.'

    Write-Host ''
    Write-Host '=== Encryption key ==='
    Write-Host 'lumo-tamer creates the vault key automatically on first use'
    Write-Host '(`tamer auth browser`) and stores it in the OS keychain'
    Write-Host '(Windows: Credential Manager, service "lumo-tamer", account "vault-key").'
    Write-Host 'This script will read the key back out afterwards, so you can'
    Write-Host 'recreate it on the Linux server (sessions/lumo-vault-key).'

    $key = ''

    Write-Host 'Starting Chrome (remote debugging)...'
    $chromeCandidates = @(
        'C:\Program Files\Google\Chrome\Application\chrome.exe',
        'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
    )
    $chromePath = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $chromePath) {
        Write-Warning 'Chrome not found in standard locations. Please start it manually with the required flags.'
    }
    else {
        # Use a temporary Chrome profile under customized/.profile so it can be removed later
        $userDataDir = Join-Path -Path $repoRoot -ChildPath 'customized/.profile'
        New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
        $userDataDir = Resolve-Path -Path $userDataDir | Select-Object -ExpandProperty Path
        $flags = @(
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=9222",
            "--remote-debugging-allowed-origins=*",
            "--disable-dev-shm-usage",
            "--user-data-dir=`"$userDataDir`""
        )
        $argString = $flags -join ' '
        $chromeProc = $null
        $chromeProc = Start-Process -FilePath $chromePath -ArgumentList $argString -WindowStyle Normal -PassThru
        Write-Host 'Wait for Chrome to start, then run: tamer auth browser'
        $confirm = Read-Host -Prompt 'After running "tamer auth browser" and verifying sessions/vault.enc exists, press Enter to read your vault key (or type N to skip)'

        if ($confirm -ne 'N' -and $confirm -ne 'n') {
            $key = Read-VaultKey
            if ($key) {
                Write-Host ''
                Write-Host '=========================================================================='
                Write-Host 'YOUR VAULT ENCRYPTION KEY (Base64, from Credential Manager):'
                Write-Host $key
                Write-Host ''
                Write-Host 'Create the key file on the Linux server with exactly this value:'
                Write-Host "  printf '%s' '<KEY ABOVE>' > sessions/lumo-vault-key"
                Write-Host '  chmod 600 sessions/lumo-vault-key'
                Write-Host 'Then set auth.vault.keyFilePath in config.yaml to that path.'
                Write-Host '=========================================================================='
            }
            else {
                Write-Warning 'Could not read the vault key from the Credential Manager.'
                Write-Warning 'Make sure you ran "tamer auth browser" successfully (it creates the key automatically).'
            }
        }
        else {
            Write-Host 'Skipped reading the vault key.'
        }
    }

    Write-Host ''
    Write-Host '=== Vault transport file ==='
    $vaultTextPath = Convert-VaultToText
    if ($vaultTextPath) {
        Write-Host "Base64 vault written to: $vaultTextPath"
        Write-Host 'Copy its contents to the Linux server and decode with:'
        Write-Host "  base64 -d sessions/vault.key > sessions/vault.enc"
    }

    Write-Host ''
    Write-Host '=== Copy artifacts to customized/app/sessions ==='
    $serverDir = Join-Path -Path (Get-Location).Path -ChildPath 'customized\\app\\sessions'
    if (-not (Test-Path -Path $serverDir)) { New-Item -ItemType Directory -Path $serverDir -Force | Out-Null }

    if ($key) {
        $keyOutPath = Join-Path -Path $serverDir -ChildPath 'lumo-vault-key'
        Set-Content -Path $keyOutPath -Value $key -NoNewline -Encoding ascii
        Write-Host "Vault key written to: $keyOutPath"
    }
    else {
        Write-Warning 'No vault key available, skipping lumo-vault-key.'
    }

    if ($vaultTextPath) {
        $vaultOutPath = Join-Path -Path $serverDir -ChildPath 'vault.key'
        Copy-Item -Path $vaultTextPath -Destination $vaultOutPath -Force
        Write-Host "Base64 vault copied to: $vaultOutPath"
    }

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    exit 1
}
finally {
    # Try to stop the Chrome process we started (if still running) and remove the temporary profile
    try {
        if ($chromeProc -and -not $chromeProc.HasExited) {
            Stop-Process -Id $chromeProc.Id -ErrorAction SilentlyContinue
        }
    } catch {
        # ignore
    }

    if ($userDataDir -and (Test-Path -Path $userDataDir)) {
        try {
            Remove-Item -Path $userDataDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed temporary Chrome profile: $userDataDir"
        }
        catch {
            Write-Warning "Could not remove Chrome profile: $($_.Exception.Message)"
        }
    }

    & npm unlink -g lumo-tamer
    if ($LASTEXITCODE -ne 0) { Write-Warning 'npm unlink returned non-zero exit code, continuing' }

    if (Get-Location) { Pop-Location }
}

exit 0
