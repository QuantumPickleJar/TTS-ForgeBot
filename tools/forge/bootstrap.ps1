[CmdletBinding()]
param(
    # Resolve paths after parameter binding.  Some Windows PowerShell hosts
    # leave $PSScriptRoot empty while evaluating parameter defaults, which
    # made an otherwise valid rebuild fail before prerequisites were checked.
    [string]$RepositoryRoot = '',
    [string]$Ref = 'rrn-headless-rebased',
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
    $scriptDirectory = $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path (Join-Path $scriptDirectory '..\..')).Path
}
$forgeDirectory = Join-Path $RepositoryRoot '.deps\forge'
$bridgePatch = Join-Path $scriptDirectory 'bridge-headless.patch'

function Require-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing prerequisite '$name' on PATH. Install Java 17+ and Maven, then rerun this script."
    }
}

Require-Command git
Require-Command java
if ($Build) { Require-Command mvn }

function Get-NativeVersionLine([string]$commandLine, [string]$displayName) {
    $output = & cmd.exe /d /c "$commandLine 2>&1"
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$displayName version probe failed with exit code $exitCode.`n$($output -join [Environment]::NewLine)"
    }
    return $output | Select-Object -First 1
}

function Get-ForgePatchPaths([string]$patchPath) {
    return @(Select-String -LiteralPath $patchPath -Pattern '^\+\+\+ b/(.+)$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
}

function Get-ForgeExpectedSources([string]$forgePath, [string]$upstreamCommit, [string]$patchPath) {
    $worktree = Join-Path ([System.IO.Path]::GetTempPath()) ('forge-patch-check-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    try {
        $null = & git -C $forgePath worktree add --detach $worktree $upstreamCommit
        if ($LASTEXITCODE -ne 0) { throw "Failed to create clean Forge verification worktree." }
        $null = & git -C $worktree apply --recount --check $patchPath
        if ($LASTEXITCODE -ne 0) { throw "Current bridge patch does not apply to upstream Forge commit $upstreamCommit." }
        $null = & git -C $worktree apply --recount $patchPath
        if ($LASTEXITCODE -ne 0) { throw 'Failed to apply the current Forge bridge patch in the clean verification worktree.' }

        $expected = [ordered]@{}
        foreach ($relative in (Get-ForgePatchPaths $patchPath)) {
            $source = Join-Path $worktree $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Current bridge patch did not produce expected source: $relative"
            }
            $expected[$relative] = [ordered]@{
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
                bytes = [System.IO.File]::ReadAllBytes($source)
            }
        }
        return $expected
    }
    finally {
        & git -C $forgePath worktree remove --force $worktree 2>$null
        if (Test-Path -LiteralPath $worktree) {
            Remove-Item -LiteralPath $worktree -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$javaVersion = Get-NativeVersionLine 'java -version' 'Java'
Write-Host "Java: $javaVersion"
if ($Build) {
    $mavenVersion = Get-NativeVersionLine 'mvn -version' 'Maven'
    Write-Host "Maven: $mavenVersion"
}

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
    # Never treat a dirty checkout as proof that the current patch is present.
    # Reconstruct the expected patch result from a clean upstream worktree and
    # replace only patch-touched files. An existing build stamp may identify
    # old bridge-generated edits; it is not itself accepted as correspondence
    # evidence.
    $expectedSources = Get-ForgeExpectedSources $forgeDirectory $commit $bridgePatch
    $previousStamp = $null
    $previousStampPath = Get-ChildItem 'forge-headless\target\forge-headless-bridge-build.json' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($previousStampPath) {
        try { $previousStamp = Get-Content -Raw -LiteralPath $previousStampPath | ConvertFrom-Json } catch { $previousStamp = $null }
    }
    foreach ($relative in $expectedSources.Keys) {
        $target = Join-Path $forgeDirectory $relative
        $expectedHash = $expectedSources[$relative].sha256
        $currentHash = if (Test-Path -LiteralPath $target -PathType Leaf) { (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash } else { $null }
        $currentIsBase = $false
        if ($currentHash -ne $null) {
            & git diff --quiet $commit -- $relative
            $currentIsBase = $LASTEXITCODE -eq 0
        }
        if ($currentHash -ne $expectedHash -and -not $currentIsBase) {
            $previousHash = if ($previousStamp -and $previousStamp.patchedSourceSha256) {
                $property = $previousStamp.patchedSourceSha256.PSObject.Properties[$relative]
                if ($property) { $property.Value } else { $null }
            } else { $null }
            if ($currentHash -ne $previousHash) {
                throw "Forge patch-touched file has unrelated local edits; refusing to overwrite: $relative"
            }
        }
    }
    foreach ($relative in $expectedSources.Keys) {
        $target = Join-Path $forgeDirectory $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        [System.IO.File]::WriteAllBytes($target, [byte[]]$expectedSources[$relative].bytes)
    }
    Write-Host 'Reconstructed patch-touched Forge sources from clean upstream plus the current bridge patch.'

    if ($Build) {
        & mvn -pl forge-headless -am package -DskipTests
        if ($LASTEXITCODE -ne 0) { throw 'Forge headless build failed.' }
        $jar = Get-ChildItem 'forge-headless\target\forge-headless-*-SNAPSHOT-jar-with-dependencies.jar' |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $jar) { throw 'Forge headless build completed without the assembled JAR.' }
        $patchedSources = [ordered]@{}
        foreach ($relative in $expectedSources.Keys) {
            $source = Join-Path $forgeDirectory $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Patched Forge source is missing after build: $relative"
            }
            $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
            if ($actualHash -ne $expectedSources[$relative].sha256) {
                throw "Patched Forge source differs from clean upstream plus current bridge patch: $relative"
            }
            $patchedSources[$relative] = $actualHash
        }
        $stamp = [ordered]@{
            schemaVersion = 3
            upstreamForgeCommit = $commit
            upstreamForgeRef = $Ref
            bridgePatchSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $bridgePatch).Hash
            patchApplication = 'clean-upstream-plus-current-bridge-patch'
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
