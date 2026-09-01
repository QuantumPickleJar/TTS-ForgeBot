$ErrorActionPreference = 'Stop'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('forge-bootstrap-fixture-' + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'src') | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'src/Example.java') -Value 'base'
    & git -C $root init --quiet
    & git -C $root config user.email fixture@example.invalid
    & git -C $root config user.name fixture
    & git -C $root add src/Example.java
    & git -C $root commit --quiet -m base
    $base = (& git -C $root rev-parse HEAD).Trim()

    $patchAPath = Join-Path $root 'patch-A.diff'
    $patchBPath = Join-Path $root 'patch-B.diff'
    Set-Content -LiteralPath (Join-Path $root 'src/Example.java') -Value 'patch-A'
    (& git -C $root diff --binary -- src/Example.java) | Out-File -LiteralPath $patchAPath -Encoding utf8
    Set-Content -LiteralPath (Join-Path $root 'src/Example.java') -Value 'base'
    Set-Content -LiteralPath (Join-Path $root 'src/Example.java') -Value 'patch-B'
    (& git -C $root diff --binary -- src/Example.java) | Out-File -LiteralPath $patchBPath -Encoding utf8
    Set-Content -LiteralPath (Join-Path $root 'src/Example.java') -Value 'base'
    & git -C $root apply $patchAPath
    $oldHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'src/Example.java')).Hash

    $expected = Join-Path $root 'expected'
    & git -C $root worktree add --quiet --detach $expected $base
    & git -C $expected apply $patchBPath
    $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $expected 'src/Example.java')).Hash

    if ($oldHash -eq $currentHash) {
        throw 'Fixture failed: patch A and patch B unexpectedly produced the same source hash.'
    }
    $stamp = [ordered]@{
        schemaVersion = 3
        patchApplication = 'clean-upstream-plus-current-bridge-patch'
        patchedSourceSha256 = [ordered]@{ 'src/Example.java' = $currentHash }
    }
    $stampedHash = $stamp.patchedSourceSha256.'src/Example.java'
    if ($oldHash -eq $stampedHash) {
        throw 'Regression: old patched source would pass a new patch stamp.'
    }
    Write-Output 'bootstrap reproducibility fixture: PASS (old patch source rejected by new expected hash)'
}
finally {
    if (Test-Path -LiteralPath $root) {
        & git -C $root worktree remove --force (Join-Path $root 'expected') 2>$null
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
