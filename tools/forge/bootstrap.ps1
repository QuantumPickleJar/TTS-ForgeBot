[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Ref = 'rrn-headless-rebased',
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$forgeDirectory = Join-Path $RepositoryRoot '.deps\forge'

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
    & git checkout --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "Failed to checkout Forge ref '$Ref'." }
    $commit = (& git rev-parse HEAD).Trim()
    Write-Host "Forge ref $Ref resolved to $commit"

    if ($Build) {
        & mvn -pl forge-headless -am package -DskipTests
        if ($LASTEXITCODE -ne 0) { throw 'Forge headless build failed.' }
        $jar = Get-ChildItem 'forge-headless\target\forge-headless-*-SNAPSHOT-jar-with-dependencies.jar' |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $jar) { throw 'Forge headless build completed without the assembled JAR.' }
        Write-Host "Built headless JAR: $($jar.FullName)"
    }
}
finally {
    Pop-Location
}
