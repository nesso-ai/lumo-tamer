#!/usr/bin/env pwsh
# Build the Go login binary. Use system Go if available and >=1.24,
# otherwise download a project-local Go 1.24 into `tools/go` and use it.
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Determine project root (two levels up from customized/auth)
$projectRoot = Resolve-Path (Join-Path $scriptDir "..\..")

function Parse-GoVersion($s) {
    if ($null -eq $s) { return $null }
    if ($s -match 'go([0-9]+(\.[0-9]+){0,2})') { return $matches[1] }
    if ($s -match '([0-9]+(\.[0-9]+){0,2})') { return $matches[1] }
    return $null
}

function Version-GE($a, $b) {
    # compare semantic-ish versions (major.minor.patch optional)
    $pa = $a.Split('.') | ForEach-Object {[int]$_}
    $pb = $b.Split('.') | ForEach-Object {[int]$_}
    for ($i=0; $i -lt [Math]::Max($pa.Length,$pb.Length); $i++) {
        $va = if ($i -lt $pa.Length) { $pa[$i] } else { 0 }
        $vb = if ($i -lt $pb.Length) { $pb[$i] } else { 0 }
        if ($va -gt $vb) { return $true }
        if ($va -lt $vb) { return $false }
    }
    return $true
}

$minVersion = '1.24.0'

# Detect system 'go'
$sysGoCmd = Get-Command go -ErrorAction SilentlyContinue
$useGoPath = $null
if ($sysGoCmd) {
    try {
        $verOut = & go version 2>$null
        $ver = Parse-GoVersion $verOut
        if ($ver -and (Version-GE $ver $minVersion)) {
            Write-Output "Using system Go: $ver ($($sysGoCmd.Source))"
            $useGoPath = "go"
        } else {
            Write-Output "System Go version $ver is < $minVersion; will use project-local Go"
        }
    } catch {
        Write-Output "System go found but version check failed: $_"
    }
}

if (-not $useGoPath) {
    # Use the Go installation under customized/tools/go
    $goDir = Join-Path $projectRoot 'customized\tools\go'
    $goExe = Join-Path $goDir 'bin\go.exe'
    if (-not (Test-Path $goExe)) {
        Write-Output "Project-local Go not found; downloading Go $($minVersion) into $goDir"
        $verLabel = '1.24.0'
        $zip = "go$verLabel.windows-amd64.zip"
        $url = "https://go.dev/dl/$zip"
        $tmp = Join-Path $env:TEMP $zip
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        try {
            Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
            $customizedTools = Join-Path $projectRoot 'customized\tools'
            if (-not (Test-Path $customizedTools)) { New-Item -ItemType Directory -Path $customizedTools | Out-Null }
            Expand-Archive $tmp -DestinationPath $customizedTools -Force
            Remove-Item $tmp -Force
        } catch {
            Write-Error "Failed to download or extract Go: $_"
            exit 1
        }
        if (-not (Test-Path $goExe)) { Write-Error "Downloaded Go but $goExe not found"; exit 1 }
        Write-Output "Downloaded Go to $goDir"
    }
    $Env:GOROOT = (Resolve-Path $goDir).Path
    $Env:PATH = "$Env:GOROOT\bin;$Env:PATH"
    $useGoPath = (Resolve-Path $goExe).Path
    Write-Output "Using project-local Go at $useGoPath"
}

# Run build using chosen go binary. Use that binary to query GOEXE so it's consistent.
Push-Location (Join-Path $projectRoot 'src\auth\login\go')
try {
    if ($useGoPath -eq 'go') {
        & go build -o ..\..\..\..\dist\proton-auth$((go env GOEXE))
    } else {
        $goexe = $useGoPath
        $goexeEnvExt = & $goexe env GOEXE
        & $goexe build -o ..\..\..\..\dist\proton-auth$goexeEnvExt
    }
    $rc = $LASTEXITCODE
} catch {
    Write-Error "go build failed: $_"
    $rc = 1
}
Pop-Location
exit $rc