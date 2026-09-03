[CmdletBinding()]
param(
    # Resolve paths after parameter binding.  Some Windows PowerShell hosts
    # leave $PSScriptRoot empty while evaluating parameter defaults, which
    # made an otherwise valid rebuild fail before prerequisites were checked.
    [string]$RepositoryRoot = '',
    [string]$Ref = 'rrn-headless-rebased',
    [switch]$Build,
    # Reconstruct and verify the clean upstream-plus-patch source even when
    # the schema-v3 content-addressed evidence is valid.
    [switch]$ForceVerify,
    # Bypass the fast path and invoke Maven. Combine with -ForceVerify for a
    # clean milestone/release-quality reconstruction and build.
    [switch]$ForceBuild
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
. (Join-Path $scriptDirectory 'ForgeBuildCache.ps1')

function Require-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing prerequisite '$name' on PATH. Install Java 17+ and Maven, then rerun this script."
    }
}

Require-Command git
Require-Command java
$doBuild = $Build -or $ForceBuild

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

function Get-ForgePatchResultBlobs([string]$patchPath) {
    $result = @{}
    $pendingBlob = $null
    foreach ($line in (Get-Content -LiteralPath $patchPath)) {
        $indexMatch = [regex]::Match($line, '^index [0-9a-f]{40}\.\.([0-9a-f]{40})(?: |$)')
        if ($indexMatch.Success) {
            $pendingBlob = $indexMatch.Groups[1].Value
            continue
        }
        $pathMatch = [regex]::Match($line, '^\+\+\+ b/(.+)$')
        if ($pathMatch.Success -and $null -ne $pendingBlob) {
            $result[$pathMatch.Groups[1].Value] = $pendingBlob
            $pendingBlob = $null
        }
    }
    return $result
}

function Get-NormalizedTextHash([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $normalizedBytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($normalizedBytes)) -Algorithm SHA256).Hash
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
            $rawBytes = [System.IO.File]::ReadAllBytes($source)
            $text = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
            $normalizedBytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
            $expected[$relative] = [ordered]@{
                sha256 = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($rawBytes)) -Algorithm SHA256).Hash
                normalizedSha256 = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($normalizedBytes)) -Algorithm SHA256).Hash
                bytes = $rawBytes
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

    if (-not $ForceVerify -and -not $ForceBuild `
        -and (Test-ForgeBuildFastPath $forgeDirectory $commit $Ref $bridgePatch)) {
        Write-Host 'Forge bridge build is current; skipping reconstruction and Maven.'
        exit 0
    }

    if ($doBuild) {
        Require-Command mvn
        $mavenVersion = Get-NativeVersionLine 'mvn -version' 'Maven'
        Write-Host "Maven: $mavenVersion"
    }

    # Never treat a dirty checkout as proof that the current patch is present.
    # Reconstruct the expected patch result from a clean upstream worktree and
    # replace only patch-touched files. An existing build stamp may identify
    # old bridge-generated edits; it is not itself accepted as correspondence
    # evidence.
    $expectedSources = Get-ForgeExpectedSources $forgeDirectory $commit $bridgePatch
    $patchResultBlobs = Get-ForgePatchResultBlobs $bridgePatch
    $previousStamp = $null
    $previousStampPath = Get-ChildItem 'forge-headless\target\forge-headless-bridge-build.json' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($previousStampPath) {
        try { $previousStamp = Get-Content -Raw -LiteralPath $previousStampPath | ConvertFrom-Json } catch { $previousStamp = $null }
    }
    foreach ($relative in $expectedSources.Keys) {
        $target = Join-Path $forgeDirectory $relative
        $expectedHash = $expectedSources[$relative].sha256
        $expectedNormalizedHash = $expectedSources[$relative].normalizedSha256
        $currentHash = if (Test-Path -LiteralPath $target -PathType Leaf) { (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash } else { $null }
        $currentNormalizedHash = if (Test-Path -LiteralPath $target -PathType Leaf) { Get-NormalizedTextHash $target } else { $null }
        $currentIsBase = $false
        if ($currentHash -ne $null) {
            & git diff --quiet $commit -- $relative
            $currentIsBase = $LASTEXITCODE -eq 0
        }
        if ($currentNormalizedHash -ne $expectedNormalizedHash -and -not $currentIsBase) {
            $previousHash = if ($previousStamp -and $previousStamp.patchedSourceSha256) {
                $property = $previousStamp.patchedSourceSha256.PSObject.Properties[$relative]
                if ($property) { $property.Value } else { $null }
            } else { $null }
            # Text files can legitimately differ in raw byte order on Windows
            # (CRLF vs LF) without representing a different Forge patch result.
            # Compare the normalized text content before treating a patch-touched
            # file as a foreign local edit.
            if ($currentHash -ne $previousHash -and $currentHash -ne $expectedHash) {
                throw "Forge patch-touched file has unrelated local edits; refusing to overwrite: $relative"
            }
        }
    }
    foreach ($relative in $expectedSources.Keys) {
        $target = Join-Path $forgeDirectory $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        $expected = [byte[]]$expectedSources[$relative].bytes
        Set-ForgeExpectedSourceIfChanged $target $expected $expectedSources[$relative].sha256 | Out-Null
    }
    Write-Host 'Reconstructed patch-touched Forge sources from clean upstream plus the current bridge patch.'

    if ($doBuild) {
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
exit 0
