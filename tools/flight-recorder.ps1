[CmdletBinding()]
param(
    [ValidateSet('List', 'Inspect', 'Timeline', 'Checkpoints', 'LastCheckpoint', 'Missing', 'Export')]
    [string]$Action = 'List',
    [string]$SessionId,
    [string]$Directory = (Join-Path $env:LOCALAPPDATA 'MtgTtsBridge\Recordings'),
    [string]$OutputPath,
    [switch]$IncludePrivate
)

$ErrorActionPreference = 'Stop'

function Get-SessionDirectory([string]$Id) {
    if ([string]::IsNullOrWhiteSpace($Id) -or $Id -notmatch '^[A-Za-z0-9_-]+$') {
        throw 'Provide a valid session id. Session ids may contain letters, numbers, underscore, and dash.'
    }
    $candidate = [IO.Path]::GetFullPath((Join-Path $Directory $Id))
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Session path is outside the configured recordings directory.'
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Recording not found: $Id" }
    return $candidate
}

function Read-SessionRecords([string]$Path, [int]$Limit = 0) {
    $records = [Collections.Generic.List[object]]::new()
    $segments = @(Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Name -match '^segment-\d+\.jsonl(\.open)?$' } | Sort-Object Name)
    foreach ($segment in $segments) {
        foreach ($line in [IO.File]::ReadLines($segment.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $records.Add(($line | ConvertFrom-Json)) }
            catch { Write-Warning "Skipped malformed journal line in $($segment.Name)." }
        }
    }
    if ($Limit -gt 0 -and $records.Count -gt $Limit) {
        return @($records.GetRange($records.Count - $Limit, $Limit))
    }
    return @($records)
}

function Get-RecordSummary($Record) {
    $payload = $Record.payload
    $summary = [ordered]@{ type = $Record.type }
    switch ($Record.type) {
        'decision_offered' {
            $summary.kind = $payload.kind
            $summary.seatId = $payload.seatId
            $summary.turnNumber = $payload.turnNumber
            $summary.phaseName = $payload.phaseName
            $summary.offeredActionCount = @($payload.actions).Count
        }
        'tts_decision_presented' {
            $decision = $payload.decision
            $summary.kind = $decision.kind
            $summary.seatId = $decision.seatId
            $summary.offeredActionCount = @($decision.actions).Count
            $summary.origin = $payload.origin
        }
        'choice_requested' {
            $summary.source = $payload.source
            $summary.requestId = $payload.requestId
            $summary.actionRequested = $true
        }
        'choice_result' {
            $summary.outcome = $payload.outcome
        }
        'recorder_loss' {
            $summary.droppedRecords = $payload.droppedRecords
            $summary.reason = $payload.reason
        }
        'forge_event' {
            $summary.kind = $payload.kind
            $summary.turnNumber = $payload.turnNumber
            $summary.phase = $payload.phase
            $summary.activeSeatId = $payload.activeSeatId
            $summary.prioritySeatId = $payload.prioritySeatId
            $summary.sourceZone = $payload.sourceZone
            $summary.destinationZone = $payload.destinationZone
            $summary.tapped = $payload.tapped
            $summary.hiddenIdentity = $payload.containsHiddenIdentity
        }
        'authoritative_checkpoint' {
            $snapshot = $payload.snapshot
            $summary.reason = $payload.reason
            $summary.turnNumber = $snapshot.turnNumber
            $summary.phase = $snapshot.phase
            $summary.activeSeatId = $snapshot.activeSeatId
            $summary.prioritySeatId = $snapshot.prioritySeatId
            $summary.forgeSequence = $snapshot.forgeSequence
            $summary.eventCursor = $snapshot.eventCursor
        }
        default {
            if ($null -ne $payload.stage) { $summary.stage = $payload.stage }
            if ($null -ne $payload.operation) { $summary.operation = $payload.operation }
            if ($null -ne $payload.origin) { $summary.origin = $payload.origin }
            if ($null -ne $payload.sourceZone) { $summary.sourceZone = $payload.sourceZone }
            if ($null -ne $payload.destinationZone) { $summary.destinationZone = $payload.destinationZone }
            if ($null -ne $payload.playerColor) { $summary.playerColor = $payload.playerColor }
            if ($null -ne $payload.physicalObservation) { $summary.physicalObservation = $payload.physicalObservation }
        }
    }
    return $summary
}

function Get-ExternalIdentifier([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
        $hex = [BitConverter]::ToString($digest).Replace('-', '')
        return 'redacted-' + $hex.Substring(0, 16).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-ExternalZone([string]$Zone) {
    if ([string]::IsNullOrWhiteSpace($Zone)) { return $Zone }
    if ($Zone -match '(?i)(hand|library|deck)') { return 'private-zone' }
    return $Zone
}

function Get-ExternalRecordSummary($Record) {
    $safe = Get-RecordSummary $Record
    if ($safe.Contains('sourceZone')) { $safe.sourceZone = Get-ExternalZone ([string]$safe.sourceZone) }
    if ($safe.Contains('destinationZone')) { $safe.destinationZone = Get-ExternalZone ([string]$safe.destinationZone) }
    if ($safe.Contains('physicalObservation')) {
        $safe.Remove('physicalObservation')
        $safe.physicalObservationRecorded = $true
    }
    if ($safe.Contains('reason')) { $safe.reason = 'Recorder reported missing data.' }
    return $safe
}

if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
    if ($Action -eq 'List') { Write-Host "No recordings directory: $Directory"; exit 0 }
    throw "Recordings directory not found: $Directory"
}

switch ($Action) {
    'List' {
        Get-ChildItem -LiteralPath $Directory -Directory | Sort-Object LastWriteTime -Descending | ForEach-Object {
            $manifestPath = Join-Path $_.FullName 'manifest.json'
            $manifest = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } else { $null }
            $segmentCount = @(Get-ChildItem -LiteralPath $_.FullName -File | Where-Object { $_.Name -match '^segment-\d+\.jsonl(\.open)?$' }).Count
            [pscustomobject]@{
                SessionId = $_.Name
                Updated = $_.LastWriteTime
                Segments = $segmentCount
                Complete = if ($null -eq $manifest) { 'unknown / active' } else { $manifest.complete }
                MatchCompleted = if ($null -eq $manifest) { 'unknown' } else { $manifest.matchCompleted }
                RecordingFinalized = if ($null -eq $manifest) { 'unknown / active' } else { $manifest.recordingFinalized }
                MissingData = if ($null -eq $manifest) { 'unknown' } else { $manifest.missingData }
                Dropped = if ($null -eq $manifest) { 'unknown' } else { $manifest.recordsDropped }
                StorageFaulted = if ($null -eq $manifest) { 'unknown' } else { $manifest.storageFaulted }
            }
        } | Format-Table -AutoSize
    }
    'Inspect' {
        $path = Get-SessionDirectory $SessionId
        $manifestPath = Join-Path $path 'manifest.json'
        if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json | Format-List }
        else { Write-Host 'No finalized manifest; the match may still be recording or ended abruptly.' }
        Get-ChildItem -LiteralPath $path -File | Where-Object { $_.Name -like '*.meta.json' } | ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Format-List
        }
    }
    'Timeline' {
        $path = Get-SessionDirectory $SessionId
        Read-SessionRecords $path | ForEach-Object {
            [pscustomobject]@{
                Sequence = $_.sequence
                TimestampUtc = $_.timestampUtc
                Type = $_.type
                DecisionId = $_.decisionId
                EventCursor = $_.eventCursor
                ForgeSequence = $_.forgeSequence
                Details = (Get-RecordSummary $_ | ConvertTo-Json -Depth 10 -Compress)
            }
        } | Format-Table -Wrap -AutoSize
    }
    'Checkpoints' {
        $path = Get-SessionDirectory $SessionId
        Read-SessionRecords $path | Where-Object { $_.type -eq 'authoritative_checkpoint' } | ForEach-Object {
            [pscustomobject]@{
                Sequence = $_.sequence
                TimestampUtc = $_.timestampUtc
                Reason = $_.payload.reason
                Turn = $_.payload.snapshot.turnNumber
                Phase = $_.payload.snapshot.phase
                ActiveSeat = $_.payload.snapshot.activeSeatId
                PrioritySeat = $_.payload.snapshot.prioritySeatId
                EventCursor = $_.payload.snapshot.eventCursor
                ForgeSequence = $_.payload.snapshot.forgeSequence
            }
        } | Format-Table -AutoSize
    }
    'LastCheckpoint' {
        $path = Get-SessionDirectory $SessionId
        $checkpoint = @(Read-SessionRecords $path | Where-Object { $_.type -eq 'authoritative_checkpoint' } |
            Sort-Object sequence | Select-Object -Last 1)
        if ($checkpoint.Count -eq 0) { Write-Warning 'No authoritative checkpoint was recorded for this match.' }
        else {
            $checkpoint[0] | ConvertTo-Json -Depth 100 | Write-Output
        }
    }
    'Missing' {
        $path = Get-SessionDirectory $SessionId
        $manifestPath = Join-Path $path 'manifest.json'
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            Write-Host "Manifest dropped records: $($manifest.recordsDropped)"
            Write-Host "Storage faulted: $($manifest.storageFaulted) $($manifest.storageError)"
            if ($manifest.missingData) { Write-Warning 'Manifest marks the recording as incomplete.' }
        } else { Write-Warning 'Manifest is missing; closed-session completeness cannot be confirmed.' }
        $records = @(Read-SessionRecords $path)
        $lossRecords = @($records | Where-Object { $_.type -eq 'recorder_loss' })
        Write-Host "Explicit loss records: $($lossRecords.Count)"
        if (Get-ChildItem -LiteralPath $path -File | Where-Object { $_.Name -like '*.jsonl.open' }) {
            Write-Warning 'An open segment exists. The match ended abruptly or the bridge has not finalized it.'
        }
        Get-ChildItem -LiteralPath $path -File | Where-Object { $_.Name -match '^segment-\d+\.jsonl$' } | ForEach-Object {
            $metadataPath = [IO.Path]::ChangeExtension($_.FullName, '.meta.json')
            if (-not (Test-Path -LiteralPath $metadataPath)) { Write-Warning "Missing segment metadata: $($_.Name)"; return }
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            $actualHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $actualCount = @([IO.File]::ReadLines($_.FullName)).Count
            [pscustomobject]@{
                Segment = $_.Name
                HashValid = $actualHash -eq $metadata.sha256
                RecordCountValid = $actualCount -eq $metadata.recordCount
                Recovered = $metadata.recoveredAfterInterruption
            }
        } | Format-Table -AutoSize
    }
    'Export' {
        $path = Get-SessionDirectory $SessionId
        if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $Directory "$SessionId-export.zip" }
        $OutputPath = [IO.Path]::GetFullPath($OutputPath)
        if (Test-Path -LiteralPath $OutputPath) { throw "Output already exists: $OutputPath" }
        $staging = Join-Path ([IO.Path]::GetTempPath()) "flight-recorder-export-$([guid]::NewGuid().ToString('N'))"
        [IO.Directory]::CreateDirectory($staging) | Out-Null
        try {
            if ($IncludePrivate) {
                Get-ChildItem -LiteralPath $path -Force | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $staging -Recurse -Force
                }
                [IO.File]::WriteAllText((Join-Path $staging 'EXPORT-PRIVACY.txt'),
                    'PRIVATE EXPORT: may contain hands, deck order, card identities, and private decisions. Share only with authorized recipients.')
            } else {
                $records = @(Read-SessionRecords $path -Limit 2000)
                $timeline = foreach ($record in $records) {
                    [ordered]@{
                        schemaVersion = $record.schemaVersion
                        sequence = $record.sequence
                        timestampUtc = $record.timestampUtc
                        type = $record.type
                        sessionId = Get-ExternalIdentifier ([string]$record.sessionId)
                        decisionId = Get-ExternalIdentifier ([string]$record.decisionId)
                        forgeSequence = $record.forgeSequence
                        eventCursor = $record.eventCursor
                        privacyRedacted = $true
                        payload = Get-ExternalRecordSummary $record
                    } | ConvertTo-Json -Depth 20 -Compress
                }
                [IO.File]::WriteAllLines((Join-Path $staging 'timeline-redacted.jsonl'), @($timeline), [Text.UTF8Encoding]::new($false))
                $manifestPath = Join-Path $path 'manifest.json'
                $sourceManifest = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } else { $null }
                $exportManifest = [ordered]@{
                    schemaVersion = 1
                    sessionId = Get-ExternalIdentifier $SessionId
                    privacy = 'redacted-summary'
                    sourceRecords = $records.Count
                    sourceManifestAvailable = $null -ne $sourceManifest
                    sourceComplete = if ($null -eq $sourceManifest) { $false } else { $sourceManifest.complete }
                    matchCompleted = if ($null -eq $sourceManifest) { $false } else { $sourceManifest.matchCompleted }
                    recordingFinalized = if ($null -eq $sourceManifest) { $false } else { $sourceManifest.recordingFinalized }
                    missingData = if ($null -eq $sourceManifest) { $true } else { $sourceManifest.missingData }
                    recordsDropped = if ($null -eq $sourceManifest) { $null } else { $sourceManifest.recordsDropped }
                    payloadsOmitted = $true
                    fullActionSetsAvailableOnlyInLocalRawRecording = $true
                }
                [IO.File]::WriteAllText((Join-Path $staging 'manifest-redacted.json'),
                    ($exportManifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
            }
            $archiveItems = @(Get-ChildItem -LiteralPath $staging -Force | Select-Object -ExpandProperty FullName)
            Compress-Archive -LiteralPath $archiveItems -DestinationPath $OutputPath -CompressionLevel Optimal
            Write-Host "Wrote $(if ($IncludePrivate) { 'private' } else { 'redacted' }) recorder export: $OutputPath"
        } finally {
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $resolvedStaging = [IO.Path]::GetFullPath($staging)
            if ($resolvedStaging.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($resolvedStaging)) {
                [IO.Directory]::Delete($resolvedStaging, $true)
            }
        }
    }
}
