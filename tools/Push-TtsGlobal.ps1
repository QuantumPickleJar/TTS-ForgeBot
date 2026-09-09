[CmdletBinding()]
param(
    [string]$GlobalLuaPath,
    [string]$TtsHost = '127.0.0.1',
    [int]$TtsPort = 39999,
    [int]$EditorPort = 39998,
    [int]$RequestTimeoutSeconds = 15,
    [int]$ReloadTimeoutSeconds = 45,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($GlobalLuaPath)) {
    $GlobalLuaPath = Join-Path $repoRoot 'tts\Global.lua'
}
$GlobalLuaPath = (Resolve-Path $GlobalLuaPath).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Normalize-Text([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-TextSha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $utf8.GetBytes((Normalize-Text $Text))
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

function Send-TtsMessage([object]$Message) {
    $json = $Message | ConvertTo-Json -Depth 16 -Compress
    $bytes = $utf8.GetBytes($json)
    $client = [System.Net.Sockets.TcpClient]::new()
    $stream = $null
    try {
        $client.Connect($TtsHost, $TtsPort)
        $stream = $client.GetStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        try { $client.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send) } catch { }
    }
    catch {
        throw "Could not send a message to TTS at ${TtsHost}:${TtsPort}. Is Tabletop Simulator running with a game loaded? $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

function Try-ParseJsonBytes([byte[]]$Bytes) {
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $null }
    $text = $utf8.GetString($Bytes)
    try {
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Receive-TtsJsonMessage(
    [System.Net.Sockets.TcpListener]$Listener,
    [datetime]$DeadlineUtc
) {
    while ([datetime]::UtcNow -lt $DeadlineUtc) {
        if (-not $Listener.Pending()) {
            Start-Sleep -Milliseconds 25
            continue
        }

        $client = $Listener.AcceptTcpClient()
        $stream = $null
        $memory = $null
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 250
            $memory = [System.IO.MemoryStream]::new()
            $buffer = New-Object byte[] 65536

            while ([datetime]::UtcNow -lt $DeadlineUtc) {
                $read = -1
                try {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                }
                catch [System.IO.IOException] {
                    $read = -1
                }

                if ($read -gt 0) {
                    $memory.Write($buffer, 0, $read)
                    $parsed = Try-ParseJsonBytes $memory.ToArray()
                    if ($null -ne $parsed) { return $parsed }
                    continue
                }

                if ($read -eq 0) { break }

                if ($memory.Length -gt 0) {
                    $parsed = Try-ParseJsonBytes $memory.ToArray()
                    if ($null -ne $parsed) { return $parsed }
                }
                Start-Sleep -Milliseconds 25
            }

            if ($memory.Length -gt 0) {
                $parsed = Try-ParseJsonBytes $memory.ToArray()
                if ($null -ne $parsed) { return $parsed }
                throw 'TTS sent a response on port 39998, but it was not complete valid JSON.'
            }
        }
        finally {
            if ($null -ne $memory) { $memory.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
            $client.Dispose()
        }
    }

    throw 'Timed out waiting for a TTS external-editor response on localhost:39998.'
}

function Wait-TtsMessageId(
    [System.Net.Sockets.TcpListener]$Listener,
    [int]$MessageId,
    [int]$TimeoutSeconds
) {
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([datetime]::UtcNow -lt $deadline) {
        $message = Receive-TtsJsonMessage $Listener $deadline
        $receivedId = -999
        if ($null -ne $message.PSObject.Properties['messageID']) {
            $receivedId = [int]$message.messageID
        }
        if ($receivedId -eq $MessageId) { return $message }

        if ($receivedId -eq 3) {
            Write-Warning ("TTS Lua error while waiting for external-editor response: {0}" -f $message.error)
        }
        else {
            Write-Verbose "Ignoring asynchronous TTS external-editor messageID=$receivedId while waiting for messageID=$MessageId."
        }
    }

    throw "Timed out waiting for TTS messageID=$MessageId."
}

function Get-GlobalScriptState([object]$Message) {
    $states = @($Message.scriptStates)
    $matches = @($states | Where-Object { [string]$_.guid -eq '-1' })
    if ($matches.Count -eq 0) {
        $matches = @($states | Where-Object { [string]$_.name -eq 'Global' })
    }
    if ($matches.Count -ne 1) {
        throw "Expected exactly one Global script state from the running TTS game, found $($matches.Count)."
    }
    return $matches[0]
}

$localGlobal = [System.IO.File]::ReadAllText($GlobalLuaPath, $utf8)
$localGeneratedSha = Get-EmbeddedGeneratedSha $localGlobal
if ([string]::IsNullOrWhiteSpace($localGeneratedSha)) {
    throw "Local generated Global.lua does not contain BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256: $GlobalLuaPath"
}
$localContentSha = Get-TextSha256 $localGlobal

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $EditorPort)
try {
    try {
        $listener.Start()
    }
    catch {
        throw "Cannot listen on localhost:$EditorPort. Close Atom/the TTS Lua external-editor plugin or any other process using port $EditorPort, then retry. $($_.Exception.Message)"
    }

    Write-Host "TTS external-editor listener: localhost:$EditorPort"
    Write-Host "Requesting scripts from the currently loaded TTS game..."
    Send-TtsMessage ([ordered]@{ messageID = 0 })
    $currentMessage = Wait-TtsMessageId $listener 1 $RequestTimeoutSeconds
    $currentGlobal = Get-GlobalScriptState $currentMessage

    $currentScript = [string]$currentGlobal.script
    $currentGeneratedSha = Get-EmbeddedGeneratedSha $currentScript
    $currentContentSha = Get-TextSha256 $currentScript
    $currentUi = ''
    if ($null -ne $currentGlobal.PSObject.Properties['ui']) {
        $currentUi = [string]$currentGlobal.ui
    }

    Write-Host "Loaded Global detected: YES"
    Write-Host "Current generated SHA: $($currentGeneratedSha ?? '<missing>')"
    Write-Host "Local generated SHA:   $localGeneratedSha"
    Write-Host "Current content SHA:   $currentContentSha"
    Write-Host "Local content SHA:     $localContentSha"
    Write-Host "Current Global chars:  $($currentScript.Length)"
    Write-Host "Local Global chars:    $($localGlobal.Length)"

    if ($currentContentSha -eq $localContentSha) {
        Write-Host 'Running TTS Global already matches the repository-generated Global.lua. Nothing to push.'
        exit 0
    }

    if (-not $Force) {
        Write-Warning 'Save & Play reloads the currently loaded save. Unsaved physical table changes since the last TTS save/load may be discarded.'
        $confirmation = Read-Host 'Type PUSH to replace only Global.lua and invoke Save & Play'
        if ($confirmation -cne 'PUSH') {
            Write-Host 'Cancelled.'
            exit 2
        }
    }

    $replacementGlobal = [ordered]@{
        name = if ([string]::IsNullOrWhiteSpace([string]$currentGlobal.name)) { 'Global' } else { [string]$currentGlobal.name }
        guid = '-1'
        script = $localGlobal
        ui = $currentUi
    }
    $saveAndPlay = [ordered]@{
        messageID = 1
        scriptStates = @($replacementGlobal)
    }

    Write-Host 'Pushing Global.lua and requesting Save & Play...'
    Send-TtsMessage $saveAndPlay

    Write-Host 'Waiting for TTS to reload the current game...'
    $reloadedMessage = Wait-TtsMessageId $listener 1 $ReloadTimeoutSeconds
    $reloadedGlobal = Get-GlobalScriptState $reloadedMessage
    $reloadedScript = [string]$reloadedGlobal.script
    $reloadedGeneratedSha = Get-EmbeddedGeneratedSha $reloadedScript
    $reloadedContentSha = Get-TextSha256 $reloadedScript

    Write-Host "Reloaded generated SHA: $($reloadedGeneratedSha ?? '<missing>')"
    Write-Host "Reloaded content SHA:   $reloadedContentSha"

    if ($reloadedGeneratedSha -ne $localGeneratedSha) {
        throw "TTS reloaded, but Global's embedded generated SHA does not match the local generated file. expected=$localGeneratedSha actual=$reloadedGeneratedSha"
    }
    if ($reloadedContentSha -ne $localContentSha) {
        throw "TTS reloaded, but Global.lua content differs from the local generated file. expectedContentSha=$localContentSha actualContentSha=$reloadedContentSha"
    }

    Write-Host 'PASS: running TTS Global matches repository tts\Global.lua after Save & Play.'
}
finally {
    try { $listener.Stop() } catch { }
}
