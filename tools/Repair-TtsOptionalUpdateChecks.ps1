[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TableSourceRoot
)

$ErrorActionPreference = 'Stop'
$objects = Join-Path (Resolve-Path $TableSourceRoot) 'extracted\objects'
$encoderPath = Get-ChildItem $objects -Filter '*_02e062_Encoder.lua' | Select-Object -First 1
$importerPath = Get-ChildItem $objects -Filter '*_80c03d_00B4FF_MTG_Importer*.lua' | Select-Object -First 1
if ($null -eq $encoderPath -or $null -eq $importerPath) {
    throw "Could not find the Encoder and MTG Importer scripts under $objects."
}

function Update-TextFile([System.IO.FileInfo]$Path, [scriptblock]$Transform) {
    $before = [System.IO.File]::ReadAllText($Path.FullName).Replace("`r`n", "`n")
    $after = & $Transform $before
    if ($after -eq $before) {
        Write-Host "Already repaired: $($Path.Name)"
        return
    }
    [System.IO.File]::WriteAllText($Path.FullName, $after, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Repaired: $($Path.Name)"
}

Update-TextFile $encoderPath {
    param($text)
    if ($text.Contains('local source = wr and wr.text or nil')) { return $text }

    $oldUpdate = @'
function updateCheck(wr)
  wr = wr.text
  local ver = versionComp(string.match(wr,"version = '(.-)'"),version)
'@
    $newUpdate = @'
function updateCheck(wr)
  local source = wr and wr.text or nil
  if type(source) ~= "string" then return end
  local remoteVersion = string.match(source,"version = '(.-)'")
  if type(remoteVersion) ~= "string" or remoteVersion == "" then return end
  local ver = versionComp(remoteVersion,version)
'@
    $oldVersion = @'
function versionCheck(wr)
  wr = wr.text
  local ver = versionComp(string.match(wr,"version = '(.-)'"),version)
'@
    $newVersion = @'
function versionCheck(wr)
  local source = wr and wr.text or nil
  if type(source) ~= "string" then return end
  local remoteVersion = string.match(source,"version = '(.-)'")
  if type(remoteVersion) ~= "string" or remoteVersion == "" then return end
  local ver = versionComp(remoteVersion,version)
'@
    $oldCompare = @'
function versionComp(a,b)
  --First does the pattern
'@
    $newCompare = @'
function versionComp(a,b)
  if type(a) ~= "string" or type(b) ~= "string" then
    return b
  end
  --First does the pattern
'@
    foreach ($pair in @(@($oldUpdate, $newUpdate), @($oldVersion, $newVersion), @($oldCompare, $newCompare))) {
        if (-not $text.Contains($pair[0])) { throw "Encoder repair pattern not found in $($encoderPath.Name)." }
        $text = $text.Replace($pair[0], $pair[1])
    }
    return $text
}

Update-TextFile $importerPath {
    param($text)
    if ($text.Contains('webRequestErrorText')) { return $text }

    $oldHelper = @'
local function printInfo(string, pc)
    if pc then
        printToColor(ERROR_MESSAGE_IMPORTER .. string, pc)
    else
        printToAll(ERROR_MESSAGE_IMPORTER .. string)
    end
end
'@
    $newHelper = @'
local function printInfo(string, pc)
    if pc then
        printToColor(ERROR_MESSAGE_IMPORTER .. string, pc)
    else
        printToAll(ERROR_MESSAGE_IMPORTER .. string)
    end
end

local function webRequestErrorText(res)
    if res == nil then return "no response" end
    local detail = res.error
    if type(detail) == "string" and detail ~= "" then return detail end
    return "request failed"
end
'@
    if (-not $text.Contains($oldHelper)) { throw "Importer helper pattern not found in $($importerPath.Name)." }
    $text = $text.Replace($oldHelper, $newHelper)
    $text = $text.Replace('            error(res)', '            printInfo("Update request skipped: " .. webRequestErrorText(res))')
    $text = $text.Replace('                    error(res)', '                    printInfo("Update check skipped: " .. webRequestErrorText(res))')
    if ($text.Contains('error(res)')) { throw "Importer repair left error(res) in $($importerPath.Name)." }
    return $text
}
