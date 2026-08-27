[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Ref = 'rrn-headless-rebased',
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$forgeDirectory = Join-Path $RepositoryRoot '.deps\forge'
$bridgePatch = Join-Path $PSScriptRoot 'bridge-headless.patch'

function Require-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing prerequisite '$name' on PATH. Install Java 17+ and Maven, then rerun this script."
    }
}

Require-Command git
Require-Command java
Require-Command mvn

function Get-NativeVersionLine([string]$commandLine, [string]$displayName) {
    $output = & cmd.exe /d /c "$commandLine 2>&1"
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$displayName version probe failed with exit code $exitCode.`n$($output -join [Environment]::NewLine)"
    }
    return $output | Select-Object -First 1
}

$javaVersion = Get-NativeVersionLine 'java -version' 'Java'
$mavenVersion = Get-NativeVersionLine 'mvn -version' 'Maven'
Write-Host "Java: $javaVersion"
Write-Host "Maven: $mavenVersion"

if (-not (Test-Path (Join-Path $forgeDirectory '.git'))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $forgeDirectory -Parent) | Out-Null
    & git clone --depth 1 --single-branch --branch $Ref https://github.com/rrnewton/forge.git $forgeDirectory
    if ($LASTEXITCODE -ne 0) { throw "Failed to clone Forge ref '$Ref'." }
}

Push-Location $forgeDirectory
try {
    & git fetch origin $Ref
    if ($LASTEXITCODE -ne 0) { throw "Failed to fetch Forge ref '$Ref'." }
    $currentCommit = (& git rev-parse HEAD).Trim()
    $requestedCommit = (& git rev-parse FETCH_HEAD).Trim()
    $hasLocalChanges = -not [string]::IsNullOrWhiteSpace((& git status --porcelain) -join '')
    if ($hasLocalChanges) {
        if ($currentCommit -ne $requestedCommit) {
            throw "Forge has local changes at $currentCommit but '$Ref' resolves to $requestedCommit. Refusing to switch commits."
        }
        Write-Host 'Forge checkout has local bridge changes; preserving them.'
    }
    else {
        & git checkout --detach FETCH_HEAD
        if ($LASTEXITCODE -ne 0) { throw "Failed to checkout Forge ref '$Ref'." }
    }
    $commit = (& git rev-parse HEAD).Trim()
    Write-Host "Forge ref $Ref resolved to $commit"

    if (-not (Test-Path -LiteralPath $bridgePatch)) {
        throw "Required Forge bridge patch is missing: $bridgePatch"
    }
    if ($hasLocalChanges) {
        # This checkout already contains the bridge implementation. Applying
        # the patch again is not an idempotent operation and produces normal
        # hunk failures, which PowerShell promotes to terminating errors under
        # ErrorActionPreference=Stop. Preserve the checked-out bridge sources;
        # the build stamp records their exact hashes below.
        Write-Host 'Skipping patch application because Forge has local bridge changes.'
    }
    else {
        & git apply --recount --check $bridgePatch
        if ($LASTEXITCODE -ne 0) { throw 'Forge bridge patch does not apply cleanly to the requested ref.' }
        & git apply --recount $bridgePatch
        if ($LASTEXITCODE -ne 0) { throw 'Failed to apply the Forge bridge patch.' }
        Write-Host 'Applied Forge bridge patch.'
    }

    if ($Build) {
        & mvn -pl forge-headless -am package -DskipTests
        if ($LASTEXITCODE -ne 0) { throw 'Forge headless build failed.' }
        $jar = Get-ChildItem 'forge-headless\target\forge-headless-*-SNAPSHOT-jar-with-dependencies.jar' |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $jar) { throw 'Forge headless build completed without the assembled JAR.' }
        $patchedSources = [ordered]@{}
        foreach ($line in (Get-Content -LiteralPath $bridgePatch)) {
            if ($line -match '^\+\+\+ b/(.+)$') {
                $relative = $Matches[1]
                $source = Join-Path $forgeDirectory $relative
                if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                    throw "Patched Forge source is missing after build: $relative"
                }
                $patchedSources[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
            }
        }
        $stamp = [ordered]@{
            schemaVersion = 2
            upstreamForgeCommit = $commit
            bridgePatchSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $bridgePatch).Hash
            patchedSourceSha256 = $patchedSources
            jarFileName = $jar.Name
            jarSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $jar.FullName).Hash
            builtAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        $stampPath = Join-Path $jar.DirectoryName 'forge-headless-bridge-build.json'
        $stamp | ConvertTo-Json | Set-Content -LiteralPath $stampPath -Encoding UTF8
        Write-Host "Built headless JAR: $($jar.FullName)"
        Write-Host "Wrote build stamp: $stampPath"
    }
}
finally {
    Pop-Location
}
