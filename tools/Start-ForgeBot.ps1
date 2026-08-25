[CmdletBinding()]
param(
    [string]$HumanDeck,
    [string]$AiDeck,
    [int]$Seed = 8675309
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$forgeRoot = Join-Path $repoRoot '.deps\forge'
$jarDirectory = Join-Path $forgeRoot 'forge-headless\target'
$workingDirectory = $forgeRoot
$assetsDirectory = Join-Path $forgeRoot 'forge-gui'
$jar = Get-ChildItem -Path $jarDirectory -Filter 'forge-headless-*-jar-with-dependencies.jar' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

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
$jarTool = Get-Command jar -ErrorAction SilentlyContinue
if ($null -eq $jarTool) {
    throw 'The Java JDK jar tool was not found on PATH. Install a Java 17+ JDK (not only a JRE) and rerun tools\forge\bootstrap.ps1 -Build.'
}

$javaVersion = (& cmd.exe /d /c 'java -version 2>&1')
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

if ([string]::IsNullOrWhiteSpace($HumanDeck)) { $HumanDeck = Join-Path $forgeRoot 'forge-headless\test_decks\monored.dck' }
if ([string]::IsNullOrWhiteSpace($AiDeck)) { $AiDeck = Join-Path $forgeRoot 'forge-headless\test_decks\monored.dck' }
$HumanDeck = (Resolve-Path $HumanDeck).Path
$AiDeck = (Resolve-Path $AiDeck).Path

$forgeArguments = "-Dforge.assets.dir=`"$assetsDirectory`" -jar `"$($jar.FullName)`" tui `"$HumanDeck`" `"$AiDeck`" --p1 tui --p2 ai --numeric-choices --seed $Seed"
Write-Host 'Starting ForgeBot at http://127.0.0.1:43110'
Write-Host 'Health endpoint: http://127.0.0.1:43110/health'
Write-Host "Forge JAR: $($jar.FullName)"
Write-Host "Java: $($java.Source)"

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
