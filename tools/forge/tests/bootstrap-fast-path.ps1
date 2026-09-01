$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\ForgeBuildCache.ps1'
. $module
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('forge-bootstrap-fast-path-' + [guid]::NewGuid())
try {
    $source = Join-Path $root 'forge-headless\src\Example.java'
    $patch = Join-Path $root 'bridge-headless.patch'
    $jar = Join-Path $root 'forge-headless\target\forge-headless-test.jar'
    $stampPath = Join-Path $root 'forge-headless\target\forge-headless-bridge-build.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $source -Parent), (Split-Path $jar -Parent) | Out-Null
    [System.IO.File]::WriteAllText($source, 'patched-source')
    [System.IO.File]::WriteAllText($patch, 'patch-A')
    [System.IO.File]::WriteAllText($jar, 'jar-A')
    & git init --quiet $root
    & git -C $root config user.email fixture@example.invalid
    & git -C $root config user.name fixture
    & git -C $root add forge-headless/src/Example.java bridge-headless.patch
    & git -C $root commit --quiet -m fixture
    $commit = (& git -C $root rev-parse HEAD).Trim()
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    $jarHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $jar).Hash
    [ordered]@{
        schemaVersion = 3
        upstreamForgeCommit = $commit
        upstreamForgeRef = 'fixture'
        bridgePatchSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash
        patchApplication = 'clean-upstream-plus-current-bridge-patch'
        patchedSourceSha256 = [ordered]@{ 'forge-headless/src/Example.java' = $sourceHash }
        jarFileName = Split-Path $jar -Leaf
        jarSha256 = $jarHash
    } | ConvertTo-Json | Set-Content -LiteralPath $stampPath -Encoding UTF8

    if (-not (Test-ForgeBuildFastPath $root $commit 'fixture' $patch)) {
        throw 'Valid schema-v3 stamp was rejected by the fast path.'
    }
    [System.IO.File]::AppendAllText($patch, '-B')
    if (Test-ForgeBuildFastPath $root $commit 'fixture' $patch) {
        throw 'Patch change incorrectly passed the fast path.'
    }
    [System.IO.File]::WriteAllText($patch, 'patch-A')
    [System.IO.File]::AppendAllText($source, '-changed')
    if (Test-ForgeBuildFastPath $root $commit 'fixture' $patch) {
        throw 'Patched source change incorrectly passed the fast path.'
    }
    [System.IO.File]::WriteAllText($source, 'patched-source')
    [System.IO.File]::AppendAllText($jar, '-changed')
    if (Test-ForgeBuildFastPath $root $commit 'fixture' $patch) {
        throw 'JAR change incorrectly passed the fast path.'
    }

    [System.IO.File]::WriteAllText($jar, 'jar-A')
    $before = (Get-Item -LiteralPath $source).LastWriteTimeUtc
    Start-Sleep -Milliseconds 1100
    $rewritten = Set-ForgeExpectedSourceIfChanged $source ([System.Text.Encoding]::UTF8.GetBytes('patched-source')) $sourceHash
    $after = (Get-Item -LiteralPath $source).LastWriteTimeUtc
    if ($rewritten -or $before -ne $after) {
        throw 'Identical patched source was rewritten or its timestamp changed.'
    }
    Write-Output 'bootstrap fast-path fixture: PASS (content validation and timestamp preservation)'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
