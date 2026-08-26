[CmdletBinding()]
param(
    [int]$Seed = 8675309,
    [switch]$TraceBridgeState
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$forgeRoot = Join-Path $repoRoot '.deps\forge'
$jarDirectory = Join-Path $forgeRoot 'forge-headless\target'
$workingDirectory = $forgeRoot
$assetsDirectory = Join-Path $forgeRoot 'forge-gui'
$jar = Get-ChildItem -Path $jarDirectory -Filter 'forge-headless-*-jar-with-dependencies.jar' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$bridgePatch = Join-Path $repoRoot 'tools\forge\bridge-headless.patch'
$buildStampPath = Join-Path $jarDirectory 'forge-headless-bridge-build.json'

if ($null -eq $jar) {
    throw "Forge headless JAR was not found. Run .\tools\forge\bootstrap.ps1 -Build first."
}
if (-not (Test-Path (Join-Path $assetsDirectory 'res\languages\en-US.properties'))) {
    throw "Forge language assets were not found under $assetsDirectory. Run .\tools\forge\bootstrap.ps1 -Build first."
}

$java = Get-Command java -ErrorAction SilentlyContinue
if ($null -eq $java) {
    throw 'Java 17+ was not found on PATH. Install Java 17+ and rerun tools\forge\bootstrap.ps1 -Build.'
}
if (-not (Test-Path -LiteralPath $bridgePatch)) {
    throw "Forge bridge patch is missing: $bridgePatch"
}
if (-not (Test-Path -LiteralPath $buildStampPath)) {
    throw 'Forge JAR has no reproducible build stamp. Run .\tools\forge\bootstrap.ps1 -Build first.'
}
$buildStamp = Get-Content -Raw -LiteralPath $buildStampPath | ConvertFrom-Json
$currentForgeCommit = (& git -C $forgeRoot rev-parse HEAD).Trim()
$currentPatchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $bridgePatch).Hash
$currentJarHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $jar.FullName).Hash
if ($buildStamp.schemaVersion -ne 2 `
    -or $buildStamp.upstreamForgeCommit -ne $currentForgeCommit `
    -or $buildStamp.bridgePatchSha256 -ne $currentPatchHash `
    -or $buildStamp.jarFileName -ne $jar.Name `
    -or $buildStamp.jarSha256 -ne $currentJarHash `
    -or $null -eq $buildStamp.patchedSourceSha256) {
    throw 'Forge JAR build stamp does not match the current Forge checkout, bridge patch, or assembled JAR. Run .\tools\forge\bootstrap.ps1 -Build first.'
}
foreach ($sourceProperty in $buildStamp.patchedSourceSha256.PSObject.Properties) {
    $sourcePath = Join-Path $forgeRoot $sourceProperty.Name
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
        -or (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash -ne $sourceProperty.Value) {
        throw "Forge patched source differs from the stamped build: $($sourceProperty.Name). Run .\tools\forge\bootstrap.ps1 -Build first."
    }
}
$jarTool = Get-Command jar -ErrorAction SilentlyContinue
if ($null -eq $jarTool) {
    $jarBesideJava = Join-Path (Split-Path -Parent $java.Source) 'jar.exe'
    if (Test-Path -LiteralPath $jarBesideJava -PathType Leaf) {
        $jarTool = [PSCustomObject]@{ Source = $jarBesideJava }
    }
    else {
        $jdkJar = Get-ChildItem 'C:\Program Files\Microsoft\jdk-*\bin\jar.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($null -eq $jdkJar) {
            throw 'The Java JDK jar tool was not found. Install a Java 17+ JDK and rerun tools\forge\bootstrap.ps1 -Build.'
        }
        $jarTool = [PSCustomObject]@{ Source = $jdkJar.FullName }
        $java = [PSCustomObject]@{ Source = (Join-Path $jdkJar.DirectoryName 'java.exe') }
    }
}

$priorErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$javaVersion = (& $java.Source -version 2>&1)
$ErrorActionPreference = $priorErrorActionPreference
if ($LASTEXITCODE -ne 0) { throw "Java version probe failed with exit code $LASTEXITCODE.`n$($javaVersion -join [Environment]::NewLine)" }
if (($javaVersion | Select-Object -First 1) -notmatch '(?:17|18|19|20|21|22|23|24|25)') {
    throw "Forge requires Java 17+. Detected: $($javaVersion | Select-Object -First 1)"
}

$requiredClasses = @(
    'forge/headless/BridgeStateFeed.class',
    'forge/headless/PlayerControllerTUI.class'
)
$jarEntries = & $jarTool.Source tf $jar.FullName
if ($LASTEXITCODE -ne 0) { throw "Could not inspect Forge JAR: $($jar.FullName)" }
foreach ($required in $requiredClasses) {
    if ($jarEntries -notcontains $required) {
        throw "Forge JAR is missing patched class $required. Rebuild forge-headless before launching."
    }
}

$tuiSource = Join-Path $forgeRoot 'forge-headless\src\main\java\forge\headless\PlayerControllerTUI.java'
if ((Test-Path $tuiSource) -and ((Get-Item $tuiSource).LastWriteTimeUtc -gt $jar.LastWriteTimeUtc)) {
    throw 'Forge TUI source is newer than the assembled JAR. Rebuild forge-headless before launching.'
}
$bridgeStateFeedSource = Join-Path $forgeRoot 'forge-headless\src\main\java\forge\headless\BridgeStateFeed.java'
if ((Test-Path $bridgeStateFeedSource) -and ((Get-Item $bridgeStateFeedSource).LastWriteTimeUtc -gt $jar.LastWriteTimeUtc)) {
    throw 'BridgeStateFeed source is newer than the assembled JAR. Rebuild forge-headless before launching.'
}

$bridgeStateTraceOption = if ($TraceBridgeState) { '-Dforge.bridge.trace=true ' } else { '' }
$forgeArguments = "$($bridgeStateTraceOption)-Dforge.assets.dir=`"$assetsDirectory`" -jar `"$($jar.FullName)`" tui `"{humanDeck}`" `"{aiDeck}`" --p1 tui --p2 ai --numeric-choices --seed $Seed"
Write-Host 'Starting ForgeBot at http://127.0.0.1:43110'
Write-Host 'Health endpoint: http://127.0.0.1:43110/health'
Write-Host "Forge JAR: $($jar.FullName)"
Write-Host "Java: $($java.Source)"
Write-Host 'Decks: loaded from the two TTS library piles when NEW MATCH is pressed (Legacy assumption).'
if ($TraceBridgeState) { Write-Host 'BridgeStateFeed trace: enabled (public battlefield summaries only).' }

Push-Location $repoRoot
try {
    & dotnet run --project 'src\MtgTtsBridge\MtgTtsBridge.csproj' -- `
        --Bridge:Adapter ForgeTui `
        --Forge:WorkingDirectory $workingDirectory `
        --Forge:Executable $java.Source `
        --Forge:Arguments $forgeArguments
}
finally {
    Pop-Location
}
