function Test-ForgeBuildFastPath([string]$forgePath, [string]$upstreamCommit, [string]$ref, [string]$patchPath) {
    $stampPath = Join-Path $forgePath 'forge-headless\target\forge-headless-bridge-build.json'
    if (-not (Test-Path -LiteralPath $stampPath -PathType Leaf)) { return $false }
    try { $stamp = Get-Content -Raw -LiteralPath $stampPath | ConvertFrom-Json } catch { return $false }
    if ($stamp.schemaVersion -ne 3 `
        -or $stamp.upstreamForgeCommit -ne $upstreamCommit `
        -or $stamp.upstreamForgeRef -ne $ref `
        -or $stamp.bridgePatchSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash `
        -or $stamp.patchApplication -ne 'clean-upstream-plus-current-bridge-patch' `
        -or $null -eq $stamp.patchedSourceSha256 `
        -or [string]::IsNullOrWhiteSpace([string]$stamp.jarFileName) `
        -or [string]::IsNullOrWhiteSpace([string]$stamp.jarSha256)) {
        return $false
    }

    $sourceProperties = @($stamp.patchedSourceSha256.PSObject.Properties)
    if ($sourceProperties.Count -eq 0) { return $false }
    foreach ($sourceProperty in $sourceProperties) {
        $sourcePath = Join-Path $forgePath $sourceProperty.Name
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
            -or (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash -ne [string]$sourceProperty.Value) {
            return $false
        }
    }

    $jarPath = Join-Path $forgePath (Join-Path 'forge-headless\target' ([string]$stamp.jarFileName))
    if (-not (Test-Path -LiteralPath $jarPath -PathType Leaf) `
        -or (Get-FileHash -Algorithm SHA256 -LiteralPath $jarPath).Hash -ne [string]$stamp.jarSha256) {
        return $false
    }
    return $true
}

function Set-ForgeExpectedSourceIfChanged([string]$target, [byte[]]$expectedBytes, [string]$expectedHash) {
    $currentHash = if (Test-Path -LiteralPath $target -PathType Leaf) {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
    } else { $null }
    if ($currentHash -eq $expectedHash) { return $false }
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    [System.IO.File]::WriteAllBytes($target, $expectedBytes)
    return $true
}
