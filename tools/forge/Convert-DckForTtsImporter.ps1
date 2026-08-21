param(
    [Parameter(Mandatory = $true)]
    [string] $InputPath,

    [Parameter(Mandatory = $true)]
    [string] $OutputPath,

    [switch] $IncludeSideboard
)

$ErrorActionPreference = "Stop"

$resolvedInput = Resolve-Path -LiteralPath $InputPath
$outputDirectory = Split-Path -Parent $OutputPath

if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$inMain = $false
$inSideboard = $false
$converted = New-Object System.Collections.Generic.List[string]

foreach ($rawLine in Get-Content -LiteralPath $resolvedInput) {
    $line = $rawLine.Trim()

    if ($line.Length -eq 0) {
        continue
    }

    if ($line.StartsWith("[") -and $line.EndsWith("]")) {
        $section = $line.Trim("[", "]")
        $inMain = $section -ieq "Main"
        $inSideboard = $section -ieq "Sideboard"
        continue
    }

    if (-not $inMain -and -not ($IncludeSideboard -and $inSideboard)) {
        continue
    }

    if ($line -notmatch "^(?<count>\d+)\s+(?<card>.+)$") {
        throw "Unsupported deck line in ${resolvedInput}: '$line'"
    }

    $count = $Matches["count"]
    $card = $Matches["card"].Split("|")[0].Trim()

    if ($card.Length -eq 0) {
        throw "Deck line has an empty card name in ${resolvedInput}: '$line'"
    }

    $converted.Add("$count $card")
}

if ($converted.Count -eq 0) {
    throw "No deck entries were converted from ${resolvedInput}."
}

Set-Content -LiteralPath $OutputPath -Value $converted -Encoding utf8
Write-Host "Wrote $($converted.Count) importer lines to $OutputPath"
