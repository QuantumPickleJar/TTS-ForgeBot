[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Lua', 'Bridge', 'Forge', 'All')]
    [string]$Scope = 'Auto'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-Required([string]$file, [string[]]$arguments) {
    Push-Location $repoRoot
    try {
        & $file @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$file $($arguments -join ' ') failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Get-ChangedPath([string]$statusLine) {
    if ($statusLine.Length -lt 4) { return $null }
    $path = $statusLine.Substring(3)
    if ($path.StartsWith('"') -and $path.EndsWith('"')) { $path = $path.Substring(1, $path.Length - 2) }
    return $path.Replace('\', '/')
}

$scopes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($Scope -eq 'All') {
    $scopes.Add('Lua') | Out-Null
    $scopes.Add('Bridge') | Out-Null
    $scopes.Add('Forge') | Out-Null
}
elseif ($Scope -ne 'Auto') {
    $scopes.Add($Scope) | Out-Null
}
else {
    $changed = @((& git -C $repoRoot status --porcelain=v1) | ForEach-Object { Get-ChangedPath $_ } | Where-Object { $_ })
    foreach ($path in $changed) {
        if ($path -like 'tts/src/*.lua' -or $path -eq 'tts/Global.xml' -or $path -eq 'tts/Global.lua') {
            $scopes.Add('Lua') | Out-Null
        }
        elseif ($path -like 'src/MtgTtsBridge/*' -or $path -like 'src/MtgTtsBridge.Contracts/*' -or $path -like 'src/MtgTtsBridge.Tests/*') {
            $scopes.Add('Bridge') | Out-Null
        }
        elseif ($path -eq 'tools/forge/bridge-headless.patch' -or $path -eq 'tools/forge/bootstrap.ps1') {
            $scopes.Add('Forge') | Out-Null
        }
        elseif ($path -eq 'tools/Start-ForgeBot.ps1' -or $path -like 'tools/forge/*') {
            $scopes.Add('Bridge') | Out-Null
        }
    }
}

if ($scopes.Count -eq 0) {
    Write-Host 'No build-relevant changes detected.'
    exit 0
}

Write-Host "Developer build scopes: $($scopes -join ', ')"
$needsDotnet = $scopes.Contains('Lua') -or $scopes.Contains('Bridge') -or $scopes.Contains('Forge')
if ($scopes.Contains('Lua')) {
    Invoke-Required 'dotnet' @('run', '--project', 'tools/MtgTtsBridge.TtsBundle', '--no-restore')
}
if ($scopes.Contains('Forge')) {
    Push-Location $repoRoot
    try {
        & (Join-Path $repoRoot 'tools/forge/bootstrap.ps1') -Build:$true
        if ($LASTEXITCODE -ne 0) { throw 'tools/forge/bootstrap.ps1 -Build failed.' }
    }
    finally {
        Pop-Location
    }
}
if ($needsDotnet) {
    Invoke-Required 'dotnet' @('build', 'src/MtgTtsBridge.Tests/MtgTtsBridge.Tests.csproj', '--no-restore')
}

if ($Scope -eq 'All' -or $scopes.Count -gt 1) {
    Invoke-Required 'dotnet' @('test', '--no-build', '--no-restore')
}
elseif ($scopes.Contains('Lua')) {
    Invoke-Required 'dotnet' @('test', 'src/MtgTtsBridge.Tests/MtgTtsBridge.Tests.csproj', '--no-build', '--no-restore', '--filter', 'FullyQualifiedName~Tts')
}
elseif ($scopes.Contains('Forge') -or $scopes.Contains('Bridge')) {
    Invoke-Required 'dotnet' @('test', 'src/MtgTtsBridge.Tests/MtgTtsBridge.Tests.csproj', '--no-build', '--no-restore', '--filter', 'FullyQualifiedName~Forge|FullyQualifiedName~Bridge|FullyQualifiedName~Diagnostics')
}
