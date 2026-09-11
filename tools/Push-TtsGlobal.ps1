[CmdletBinding()]
param(
    [string]$GlobalLuaPath,
    [string]$BridgeUrl = 'http://127.0.0.1:43110',
    [int]$HttpTimeoutSeconds = 180,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

try {
    [System.Net.Http.HttpClient] | Out-Null
}
catch {
    Add-Type -AssemblyName 'System.Net.Http'
}

if ($HttpTimeoutSeconds -lt 1) {
    throw 'HttpTimeoutSeconds must be at least 1.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($GlobalLuaPath)) {
    $GlobalLuaPath = Join-Path $repoRoot 'tts\Global.lua'
}
$GlobalLuaPath = (Resolve-Path $GlobalLuaPath).Path

$utf8 = [System.Text.UTF8Encoding]::new($false)

function Get-NormalizedText([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-CanonicalTtsScriptForComparison([string]$Text) {
    return (Get-NormalizedText $Text).TrimEnd([char[]]"`n")
}

function Get-TtsComparableSha256([string]$Text) {
    $canonical = Get-CanonicalTtsScriptForComparison $Text
    $bytes = $utf8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-EmbeddedGeneratedSha([string]$Text) {
    $match = [System.Text.RegularExpressions.Regex]::Match(
        $Text,
        'BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256\s*=\s*"(?<sha>[0-9a-fA-F]{64})"')
    if (-not $match.Success) { return $null }
    return $match.Groups['sha'].Value.ToLowerInvariant()
}

function Get-HttpErrorDetail([System.Exception]$Exception) {
    if ($null -eq $Exception) { return '<no exception details>' }

    $response = $Exception.Response
    if ($null -eq $response) {
        return $Exception.Message
    }

    try {
        $stream = $response.GetResponseStream()
        if ($null -eq $stream) {
            return $Exception.Message
        }

        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        try {
            $body = $reader.ReadToEnd()
            if ([string]::IsNullOrWhiteSpace($body)) {
                return $Exception.Message
            }
            return $body
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
    catch {
        return $Exception.Message
    }
}

$localGlobal = [System.IO.File]::ReadAllText($GlobalLuaPath, $utf8)
$localGeneratedSha = Get-EmbeddedGeneratedSha $localGlobal
if ([string]::IsNullOrWhiteSpace($localGeneratedSha)) {
    throw (
        "Local generated Global.lua does not contain " +
        "BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256: $GlobalLuaPath"
    )
}

$localCanonical = Get-CanonicalTtsScriptForComparison $localGlobal
$localContentSha = Get-TtsComparableSha256 $localGlobal

Write-Host "Bridge URL: $BridgeUrl"
Write-Host "Local generated SHA: $localGeneratedSha"
Write-Host "Local content SHA:   $localContentSha"
Write-Host "Local canonical len: $($localCanonical.Length)"

if (-not $Force) {
    Write-Warning (
        'Save & Play reloads the currently loaded save. Unsaved physical table ' +
        'changes since the last TTS save/load may be discarded.'
    )

    $confirmation = Read-Host 'Type PUSH to replace only Global.lua and invoke Save & Play'
    if ($confirmation -cne 'PUSH') {
        Write-Host 'Cancelled.'
        exit 2
    }
}

$statusUri = "$BridgeUrl/api/v1/tts-editor/status"
$pushUri = "$BridgeUrl/api/v1/tts-editor/push-global"

try {
    Write-Host 'Checking bridge TTS editor status...'
    $status = Invoke-RestMethod -Method Get -Uri $statusUri -TimeoutSec $HttpTimeoutSeconds
}
catch {
    $detail = Get-HttpErrorDetail $_.Exception
    throw (
        "Bridge status request failed at $statusUri. " +
        "Ensure Start-ForgeBot is running. Details: $detail"
    )
}

Write-Host "Bridge listener active: $($status.listenerActive)"
Write-Host "Bridge callback endpoint: $($status.listenHost):$($status.listenPort)"
Write-Host "Bridge TTS command endpoint: $($status.ttsHost):$($status.ttsPort)"

if (-not $status.listenerActive) {
    throw (
        "Bridge is running but TTS external-editor listener is unavailable. " +
        "Check bridge logs and port ownership on $($status.listenHost):$($status.listenPort)."
    )
}

$payload = [ordered]@{
    globalLua = $localGlobal
    expectedGeneratedGlobalLuaSha256 = $localGeneratedSha
}

try {
    Write-Host 'Pushing Global.lua via bridge /api/v1/tts-editor/push-global...'
    $payloadJson = ($payload | ConvertTo-Json -Depth 8 -Compress)
    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.Timeout = [System.TimeSpan]::FromSeconds([double]$HttpTimeoutSeconds)
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post,
            $pushUri)
        $request.Content = [System.Net.Http.StringContent]::new(
            $payloadJson,
            [System.Text.UTF8Encoding]::new($false),
            'application/json')

        $response = $httpClient.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseContentRead).GetAwaiter().GetResult()
        $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $($response.StatusCode) $($response.ReasonPhrase): $responseBody"
        }

        $result = $responseBody | ConvertFrom-Json
    }
    finally {
        if ($null -ne $httpClient) { $httpClient.Dispose() }
        if ($null -ne $request) { $request.Dispose() }
    }
}
catch {
    $detail = Get-HttpErrorDetail $_.Exception
    throw (
        "Bridge push-global request failed. " +
        "Details: $detail"
    )
}

Write-Host "Observed callback sequence: $($result.observedCallbackSequence)"
Write-Host "Verified generated SHA:    $($result.verifiedGeneratedGlobalLuaSha256)"
Write-Host "Verified content SHA:      $($result.canonicalContentSha256)"
Write-Host "Verified canonical len:    $($result.canonicalLength)"
Write-Host 'PASS: running TTS Global matches local generated Global.lua after Save & Play.'
