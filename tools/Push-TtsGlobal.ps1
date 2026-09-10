[CmdletBinding()]
param(
    [string]$GlobalLuaPath,
    [string]$TtsHost = '127.0.0.1',
    [int]$TtsPort = 39999,
    [int]$EditorPort = 39998,
    [int]$RequestTimeoutSeconds = 120,
    [int]$ReloadTimeoutSeconds = 120,
    [int]$RequestRetryIntervalSeconds = 30,
    [int]$DrainSeconds = 2,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($GlobalLuaPath)) {
    $GlobalLuaPath = Join-Path $repoRoot 'tts\Global.lua'
}
$GlobalLuaPath = (Resolve-Path $GlobalLuaPath).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)

if ($RequestTimeoutSeconds -lt 1) {
    throw 'RequestTimeoutSeconds must be at least 1.'
}
if ($ReloadTimeoutSeconds -lt 1) {
    throw 'ReloadTimeoutSeconds must be at least 1.'
}
if ($RequestRetryIntervalSeconds -lt 1) {
    throw 'RequestRetryIntervalSeconds must be at least 1.'
}
if ($DrainSeconds -lt 0) {
    throw 'DrainSeconds cannot be negative.'
}

function Normalize-Text([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Normalize-TtsScriptForComparison([string]$Text) {
    # TTS/external-editor transport may normalize line endings and may add or
    # remove terminal newlines. Neither changes Lua semantics.
    $normalized = Normalize-Text $Text
    return $normalized.TrimEnd([char[]]"`n")
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

function Get-TtsComparableSha256([string]$Text) {
    return Get-TextSha256 (Normalize-TtsScriptForComparison $Text)
}

function Get-EmbeddedGeneratedSha([string]$Text) {
    $match = [System.Text.RegularExpressions.Regex]::Match(
        $Text,
        'BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256\s*=\s*"(?<sha>[0-9a-fA-F]{64})"')
    if (-not $match.Success) { return $null }
    return $match.Groups['sha'].Value.ToLowerInvariant()
}

function Get-FirstTextDifferenceIndex(
    [string]$Expected,
    [string]$Actual
) {
    $expectedText = if ($null -eq $Expected) { '' } else { $Expected }
    $actualText = if ($null -eq $Actual) { '' } else { $Actual }
    $minLength = [Math]::Min($expectedText.Length, $actualText.Length)

    for ($i = 0; $i -lt $minLength; $i++) {
        if ($expectedText[$i] -cne $actualText[$i]) {
            return $i
        }
    }

    if ($expectedText.Length -ne $actualText.Length) {
        return $minLength
    }

    return -1
}

function Format-OptionalValue([object]$Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return '<missing>'
    }
    return [string]$Value
}

function Get-TtsMessageId([object]$Message) {
    if ($null -eq $Message) { return -999 }
    if ($null -eq $Message.PSObject.Properties['messageID']) { return -999 }

    try {
        return [int]$Message.messageID
    }
    catch {
        return -999
    }
}

function Write-IgnoredTtsMessage([object]$Message, [string]$Context) {
    $receivedId = Get-TtsMessageId $Message

    if ($receivedId -eq 3) {
        $errorText = '<missing>'
        if ($null -ne $Message.PSObject.Properties['error']) {
            $errorText = [string]$Message.error
        }
        Write-Warning ("TTS Lua error while {0}: {1}" -f $Context, $errorText)
        return
    }

    Write-Verbose (
        "Ignoring asynchronous/stale TTS external-editor messageID={0} while {1}." -f
        $receivedId,
        $Context
    )
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
        try {
            $client.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send)
        }
        catch { }
    }
    catch {
        throw (
            "Could not send a message to TTS at ${TtsHost}:${TtsPort}. " +
            "Is Tabletop Simulator running with a game loaded? " +
            $_.Exception.Message
        )
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
    [datetime]$DeadlineUtc,
    [switch]$AllowTimeout
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
                    if ($null -ne $parsed) {
                        return $parsed
                    }
                    continue
                }

                if ($read -eq 0) {
                    break
                }

                if ($memory.Length -gt 0) {
                    $parsed = Try-ParseJsonBytes $memory.ToArray()
                    if ($null -ne $parsed) {
                        return $parsed
                    }
                }

                Start-Sleep -Milliseconds 25
            }

            if ($memory.Length -gt 0) {
                $parsed = Try-ParseJsonBytes $memory.ToArray()
                if ($null -ne $parsed) {
                    return $parsed
                }

                throw 'TTS connected to port 39998, but the response was not complete valid JSON.'
            }
        }
        finally {
            if ($null -ne $memory) { $memory.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
            $client.Dispose()
        }
    }

    if ($AllowTimeout) {
        return $null
    }

    throw "Timed out waiting for a TTS external-editor response on localhost:$EditorPort."
}

function Receive-TtsJsonMessageSlice(
    [System.Net.Sockets.TcpListener]$Listener,
    [datetime]$OverallDeadlineUtc,
    [int]$SliceMilliseconds = 500
) {
    # The slice controls only how long we wait for a NEW callback connection.
    # Once TTS connects, its scriptStates payload can be large and may require
    # substantially longer than the polling slice to arrive in full.
    $waitDeadline = [datetime]::UtcNow.AddMilliseconds($SliceMilliseconds)
    if ($waitDeadline -gt $OverallDeadlineUtc) {
        $waitDeadline = $OverallDeadlineUtc
    }

    while ([datetime]::UtcNow -lt $waitDeadline) {
        if ($Listener.Pending()) {
            # Hand the accepted message the full operation deadline.
            return Receive-TtsJsonMessage $Listener $OverallDeadlineUtc -AllowTimeout
        }
        Start-Sleep -Milliseconds 25
    }

    return $null
}

function Get-GlobalScriptState([object]$Message) {
    $states = @($Message.scriptStates)
    $matches = @($states | Where-Object { [string]$_.guid -eq '-1' })

    if ($matches.Count -eq 0) {
        $matches = @($states | Where-Object { [string]$_.name -eq 'Global' })
    }

    if ($matches.Count -ne 1) {
        throw (
            "Expected exactly one Global script state from the running TTS game, " +
            "found $($matches.Count)."
        )
    }

    return $matches[0]
}

function Request-TtsScriptsWithRetry(
    [System.Net.Sockets.TcpListener]$Listener,
    [int]$TimeoutSeconds,
    [int]$RetryIntervalSeconds
) {
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextRequestUtc = [datetime]::MinValue
    $attempt = 0

    while ([datetime]::UtcNow -lt $deadline) {
        if ([datetime]::UtcNow -ge $nextRequestUtc) {
            $attempt++

            if ($attempt -eq 1) {
                Write-Host 'Requesting scripts from the currently loaded TTS game...'
            }
            else {
                Write-Host (
                    "No script callback yet; retrying request on the same listener " +
                    "(attempt $attempt)..."
                )
            }

            Send-TtsMessage ([ordered]@{ messageID = 0 })
            $nextRequestUtc = [datetime]::UtcNow.AddSeconds($RetryIntervalSeconds)
        }

        $message = Receive-TtsJsonMessageSlice $Listener $deadline
        if ($null -eq $message) {
            continue
        }

        $receivedId = Get-TtsMessageId $message
        if ($receivedId -eq 1) {
            # A normal Get Lua Scripts response, or an automatic game-load script
            # callback, is sufficient to establish the current Global state.
            try {
                $null = Get-GlobalScriptState $message
                Write-Verbose "Accepted TTS script callback after request attempt $attempt."
                return $message
            }
            catch {
                Write-Warning (
                    "Received TTS messageID=1 without a usable Global script state; " +
                    "continuing to wait. $($_.Exception.Message)"
                )
                continue
            }
        }

        Write-IgnoredTtsMessage $message 'waiting for the current script state'
    }

    throw (
        "Timed out after $TimeoutSeconds seconds waiting for TTS to return script state " +
        "on localhost:$EditorPort. Sent $attempt messageID=0 request(s) while keeping " +
        "the same listener alive."
    )
}

function Wait-TtsReloadedGlobal(
    [System.Net.Sockets.TcpListener]$Listener,
    [int]$TimeoutSeconds,
    [string]$ExpectedGeneratedSha,
    [string]$ExpectedContentSha
) {
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $staleScriptCallbacks = 0
    $matchingIdentityButDifferentContent = $null

    while ([datetime]::UtcNow -lt $deadline) {
        $message = Receive-TtsJsonMessageSlice $Listener $deadline
        if ($null -eq $message) {
            continue
        }

        $receivedId = Get-TtsMessageId $message
        if ($receivedId -ne 1) {
            Write-IgnoredTtsMessage $message 'waiting for the Save & Play reload'
            continue
        }

        try {
            $global = Get-GlobalScriptState $message
        }
        catch {
            Write-Warning (
                "Received TTS messageID=1 without a usable Global script state while " +
                "waiting for reload; continuing. $($_.Exception.Message)"
            )
            continue
        }

        $script = [string]$global.script
        $generatedSha = Get-EmbeddedGeneratedSha $script
        $contentSha = Get-TtsComparableSha256 $script

        if (
            $generatedSha -eq $ExpectedGeneratedSha -and
            $contentSha -eq $ExpectedContentSha
        ) {
            return $message
        }

        if ($generatedSha -eq $ExpectedGeneratedSha) {
            # Retries of messageID=0 can produce a late pre-push script callback.
            # If the generated identity matches but the full content does not, retain
            # it as a possible real reload mismatch, but keep waiting for an exact
            # post-push callback until the reload deadline expires.
            $matchingIdentityButDifferentContent = $message
            Write-Verbose (
                "Received messageID=1 with the target generated SHA but different " +
                "content; retaining it as a mismatch candidate while waiting for " +
                "a possible later exact reload callback."
            )
            continue
        }

        $staleScriptCallbacks++
        Write-Verbose (
            "Ignoring stale messageID=1 while waiting for reload. " +
            "generatedSha=$(Format-OptionalValue $generatedSha)"
        )
    }

    if ($null -ne $matchingIdentityButDifferentContent) {
        Write-Verbose (
            "Reload deadline expired after receiving a target-identity callback with " +
            "different content; returning that callback for detailed mismatch diagnostics."
        )
        return $matchingIdentityButDifferentContent
    }

    throw (
        "Timed out after $TimeoutSeconds seconds waiting for the Save & Play reload " +
        "callback on localhost:$EditorPort. Ignored $staleScriptCallbacks stale " +
        "messageID=1 callback(s)."
    )
}

function Drain-TtsMessages(
    [System.Net.Sockets.TcpListener]$Listener,
    [int]$Seconds,
    [string]$Reason
) {
    if ($Seconds -le 0) {
        return
    }

    $deadline = [datetime]::UtcNow.AddSeconds($Seconds)
    $drained = 0

    while ([datetime]::UtcNow -lt $deadline) {
        $message = Receive-TtsJsonMessageSlice $Listener $deadline 250
        if ($null -eq $message) {
            continue
        }

        $drained++
        Write-IgnoredTtsMessage $message $Reason
    }

    if ($drained -gt 0) {
        Write-Verbose "Drained $drained trailing TTS callback(s) before releasing port $EditorPort."
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

$localComparable = Normalize-TtsScriptForComparison $localGlobal
$localContentSha = Get-TtsComparableSha256 $localGlobal

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Loopback,
    $EditorPort
)

try {
    try {
        $listener.Start()
    }
    catch {
        throw (
            "Cannot listen on localhost:$EditorPort. Close Atom/the TTS Lua " +
            "external-editor plugin or any other process using port $EditorPort, " +
            "then retry. $($_.Exception.Message)"
        )
    }

    Write-Host "TTS external-editor listener: localhost:$EditorPort"
    Write-Host (
        "Request timeout: ${RequestTimeoutSeconds}s; " +
        "retry interval: ${RequestRetryIntervalSeconds}s; " +
        "reload timeout: ${ReloadTimeoutSeconds}s"
    )

    # Keep this same listener alive for the entire one-shot transaction.
    $currentMessage = Request-TtsScriptsWithRetry `
        $listener `
        $RequestTimeoutSeconds `
        $RequestRetryIntervalSeconds

    $currentGlobal = Get-GlobalScriptState $currentMessage
    $currentScript = [string]$currentGlobal.script
    $currentGeneratedSha = Get-EmbeddedGeneratedSha $currentScript
    $currentContentSha = Get-TtsComparableSha256 $currentScript

    $currentUi = ''
    if ($null -ne $currentGlobal.PSObject.Properties['ui']) {
        $currentUi = [string]$currentGlobal.ui
    }

    Write-Host 'Loaded Global detected: YES'
    Write-Host ("Current generated SHA: {0}" -f (Format-OptionalValue $currentGeneratedSha))
    Write-Host "Local generated SHA:   $localGeneratedSha"
    Write-Host "Current content SHA:   $currentContentSha"
    Write-Host "Local content SHA:     $localContentSha"
    Write-Host "Current Global chars:  $($currentScript.Length)"
    Write-Host "Local Global chars:    $($localGlobal.Length)"

    if ($currentContentSha -eq $localContentSha) {
        Write-Host (
            'Running TTS Global already matches the repository-generated Global.lua ' +
            'after TTS-safe normalization. Nothing to push.'
        )

        Drain-TtsMessages `
            $listener `
            $DrainSeconds `
            'settling after a no-op script check'

        exit 0
    }

    if (-not $Force) {
        Write-Warning (
            'Save & Play reloads the currently loaded save. Unsaved physical table ' +
            'changes since the last TTS save/load may be discarded.'
        )

        $confirmation = Read-Host 'Type PUSH to replace only Global.lua and invoke Save & Play'
        if ($confirmation -cne 'PUSH') {
            Write-Host 'Cancelled.'

            Drain-TtsMessages `
                $listener `
                $DrainSeconds `
                'settling after cancellation'

            exit 2
        }
    }

    $replacementName = [string]$currentGlobal.name
    if ([string]::IsNullOrWhiteSpace($replacementName)) {
        $replacementName = 'Global'
    }

    $replacementGlobal = [ordered]@{
        name   = $replacementName
        guid   = '-1'
        script = $localGlobal
        ui     = $currentUi
    }

    $saveAndPlay = [ordered]@{
        messageID    = 1
        scriptStates = @($replacementGlobal)
    }

    Write-Host 'Pushing Global.lua and requesting Save & Play...'
    Send-TtsMessage $saveAndPlay

    Write-Host 'Waiting for TTS to reload the current game on the same editor listener...'
    $reloadedMessage = Wait-TtsReloadedGlobal `
        $listener `
        $ReloadTimeoutSeconds `
        $localGeneratedSha `
        $localContentSha

    $reloadedGlobal = Get-GlobalScriptState $reloadedMessage
    $reloadedScript = [string]$reloadedGlobal.script
    $reloadedGeneratedSha = Get-EmbeddedGeneratedSha $reloadedScript
    $reloadedContentSha = Get-TtsComparableSha256 $reloadedScript

    Write-Host (
        "Reloaded generated SHA: {0}" -f
        (Format-OptionalValue $reloadedGeneratedSha)
    )
    Write-Host "Reloaded content SHA:   $reloadedContentSha"

    if ($reloadedGeneratedSha -ne $localGeneratedSha) {
        throw (
            "TTS reloaded, but Global's embedded generated SHA does not match the " +
            "local generated file. expected=$localGeneratedSha " +
            "actual=$(Format-OptionalValue $reloadedGeneratedSha)"
        )
    }

    if ($reloadedContentSha -ne $localContentSha) {
        $reloadedComparable = Normalize-TtsScriptForComparison $reloadedScript
        $firstDiffIndex = Get-FirstTextDifferenceIndex $localComparable $reloadedComparable

        throw (
            "TTS reloaded with the expected generated script identity, " +
            "but substantive Global.lua content differs from the local generated file. " +
            "expectedContentSha=$localContentSha " +
            "actualContentSha=$reloadedContentSha " +
            "expectedLength=$($localComparable.Length) " +
            "actualLength=$($reloadedComparable.Length) " +
            "firstDiffIndex=$firstDiffIndex"
        )
    }

    Write-Host 'PASS: running TTS Global matches repository tts\Global.lua after Save & Play.'

    # Keep the callback port alive briefly so late asynchronous messages from this
    # Save & Play transaction do not immediately encounter a vanished listener.
    Drain-TtsMessages `
        $listener `
        $DrainSeconds `
        'settling after successful Save & Play'
}
finally {
    try {
        $listener.Stop()
    }
    catch { }
}
