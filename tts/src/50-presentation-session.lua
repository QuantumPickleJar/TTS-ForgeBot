
    local candidates = seatId and BridgeFindLibraryDeckCandidatesForSeat(seatId) or {}
    local matches = {}
    for _, deck in ipairs(candidates) do
        if BridgeDeckContainsCardName(deck, expectedName) then
            table.insert(matches, deck)
        end
    end
    if #matches == 1 then return matches[1] end
    if #matches > 1 then
        local nearest = BridgeSelectNearestDeckCandidate(seat, matches)
        if nearest ~= nil then return nearest end
        BridgeLog(string.format("[Bridge] ambiguous library deck match for %s (%d candidates)", tostring(expectedName), #matches))
        return nil
    end

    return nil
end

function BridgeTakeCardFromDeckByIdentity(deck, expectedName, position, smooth, callback)
    if not BridgeObjectIsUsable(deck) then
        callback(nil, "physical library deck is no longer available")
        return
    end

    -- TTS turns a one-card Deck into a Card. It is still the authoritative
    -- library object and must be drawable rather than reported as empty.
    if deck.tag == "Card" then
        if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(deck.getName(), expectedName) then
            callback(nil, "physical single-card library mismatched authoritative identity")
            return
        end
        deck.setLock(false)
        deck.use_hands = true
        deck.setPositionSmooth(position, smooth == true, true)
        callback(deck, nil)
        return
    end

    local containedCards = {}
    local containedOk = pcall(function() containedCards = deck.getObjects() or {} end)
    if not containedOk then
        callback(nil, "could not inspect physical library deck contents")
        return
    end
    if #containedCards == 0 then
        callback(nil, "physical library deck is empty")
        return
    end

    table.sort(containedCards, function(left, right)
        local leftIndex = tonumber(left.index or -1) or -1
        local rightIndex = tonumber(right.index or -1) or -1
        if leftIndex == rightIndex then
            return tostring(left.guid or "") < tostring(right.guid or "")
        end
        return leftIndex < rightIndex
    end)

    local matched = nil
    for _, contained in ipairs(containedCards) do
        if contained.index ~= nil then
            if expectedName == nil or expectedName == "" then
                matched = contained
                break
            end
            local containedName = contained.nickname or contained.name
            if BridgeCardNameMatches(containedName, expectedName) then
                matched = contained
                break
            end
        end
    end
    if matched == nil then
        callback(nil, "physical library inventory has no card matching authoritative identity")
        return
    end

    local deckGuid = BridgeSafeObjectGuid(deck)
    deck.takeObject({
        index = matched.index,
        position = position,
        smooth = smooth,
        callback_function = function(taken)
            if not BridgeObjectIsUsable(taken) then
                callback(nil, "physical library returned an unusable card object")
                return
            end
            if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(taken.getName(), expectedName) then
                local liveDeck = BridgeGetLiveObjectByGuid(deckGuid)
                if liveDeck ~= nil then
                    BridgeSafeObjectCall(liveDeck, function(d) d.putObject(taken) end)
                end
                callback(nil, "physical library extraction mismatched authoritative identity")
                return
            end
            callback(taken, nil)
        end
    })
end

-- Forge's library event already identifies the exact instance and its order.
-- For a live transition, take TTS's physical top card rather than selecting a
-- later contained card by its display name. The name is checked only after
-- selecting the top entry, to diagnose a physical-order desync without
-- changing which object Forge's ordered transition embodies.
function BridgeTakeTopCardFromLibrary(deck, expectedName, position, smooth, callback)
    if not BridgeObjectIsUsable(deck) then
        callback(nil, "physical library deck is no longer available")
        return
    end

    if deck.tag == "Card" then
        if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(deck.getName(), expectedName) then
            callback(nil, "physical single-card library top order mismatched authoritative transition")
            return
        end
        deck.setLock(false)
        deck.use_hands = true
        deck.setPositionSmooth(position, smooth == true, true)
        callback(deck, nil)
        return
    end

    local containedCards = {}
    local containedOk = pcall(function() containedCards = deck.getObjects() or {} end)
    if not containedOk then
        callback(nil, "could not inspect physical library deck contents")
        return
    end
    if #containedCards == 0 then
        callback(nil, "physical library deck is empty")
        return
    end
    table.sort(containedCards, function(left, right)
        local leftIndex = tonumber(left.index or -1) or -1
        local rightIndex = tonumber(right.index or -1) or -1
        if leftIndex == rightIndex then return tostring(left.guid or "") < tostring(right.guid or "") end
        return leftIndex < rightIndex
    end)

    local top = containedCards[1]
    local topName = top and (top.nickname or top.name) or nil
    if top == nil or top.index == nil then
        callback(nil, "physical library has no extractable top card")
        return
    end
    if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(topName, expectedName) then
        callback(nil, "physical library top order mismatched authoritative transition")
        return
    end

    deck.takeObject({
        index = top.index,
        position = position,
        smooth = smooth,
        callback_function = function(taken)
            if not BridgeObjectIsUsable(taken) then
                callback(nil, "physical library returned an unusable top card object")
                return
            end
            callback(taken, nil)
        end
    })
end

function BridgeTakeNamedCardFromDeck(deck, expectedName, position, smooth, callback)
    BridgeTakeCardFromDeckByIdentity(deck, expectedName, position, smooth, callback)
end

function BridgeTokenNameKey(name)
    local normalized = BridgeNormalizeCardName(name)
    normalized = string.gsub(normalized, "[,%./%-]", " ")
    normalized = string.gsub(normalized, "%f[%a]token%f[%A]", " ")
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    normalized = string.gsub(normalized, "%s+", " ")
    return normalized
end

function BridgeTokenNameMatches(ttsName, forgeName)
    -- Token materialization has no safe fallback from a partial name.  A
    -- fuzzy match can bind a similarly named token (or the source permanent)
    -- and is especially dangerous when the utility deck is searched first.
    -- Treat the normalized token name as the reusable visual identity; Forge's
    -- exact CardInstanceId still owns the spawned object's session identity.
    local left = BridgeTokenNameKey(ttsName)
    local right = BridgeTokenNameKey(forgeName)
    if left == "" or right == "" then return false end
    return left == right
end

function BridgeMarkTokenPhysicalObject(object)
    local guid = BridgeSafeObjectGuid(object)
    if guid ~= nil then BridgeState.tokenPhysicalGuids[guid] = true end
end

function BridgeButtonLooksLikeTokenSpawner(button)
    if button == nil then return false end
    local label = string.lower(tostring(button.label or ""))
    local tooltip = string.lower(tostring(button.tooltip or ""))
    local text = label .. " " .. tooltip
    -- A generic Encoder button is not a token producer.  Invoking one here
    -- causes Easy Modules MakeExactCopy/APIobjGetPropData errors and can
    -- mutate an ordinary game card.  Only accept explicit token/emblem
    -- controls; the generic proxy fallback below handles tables without one.
    return string.find(text, "emblem", 1, true) ~= nil
        or string.find(text, "spawn token", 1, true) ~= nil
        or string.find(text, "create token", 1, true) ~= nil
        or string.find(text, "make token", 1, true) ~= nil
end

function BridgeInvokeButtonClick(source, button, seatColor)
    if source == nil or button == nil then return false end
    local clickFunction = tostring(button.click_function or "")
    if clickFunction == "" then return false end

    -- TTS invokes a card button as callback(card, playerColor, altClick).
    -- Card Importer's EmblemsAndTokens handler has exactly that positional
    -- shape. Object.call instead supplies one table, leaving playerColor nil
    -- and producing the Easy Modules nil-call failure seen at the table.
    local globalHandler = _G[clickFunction]
    if type(globalHandler) == "function" then
        local ok, callError = pcall(function()
            globalHandler(source, seatColor, false)
        end)
        if ok then
            BridgeLog("[Bridge] invoked built-in card button positionally function=" .. clickFunction)
            return true
        end
        BridgeLog("[Bridge] positional built-in card button failed function=" .. clickFunction
            .. " error=" .. tostring(callError))
    end

    local payload = {
        obj = source,
        player_color = seatColor,
        alt_click = false,
        altClick = false,
        playerColor = seatColor,
    }

    local owner = button.function_owner
    if type(owner) == "string" then
        if owner == "Global" then
            owner = Global
        else
            owner = BridgeGetLiveObjectByGuid(owner)
        end
    end

    if owner ~= nil and type(owner.call) == "function" then
        local ok = pcall(function()
            owner.call(clickFunction, payload)
        end)
        if ok then return true end
    end

    if source.call ~= nil then
        local ok = pcall(function()
            source.call(clickFunction, payload)
        end)
        if ok then return true end
    end

    return false
end

function BridgeTrySpawnTokenViaEncodeButton(expectedName, seatId, callback)
    -- Kept for diagnostics/backward compatibility only.  A source-card
    -- EmblemsAndTokens callback is not safely invocable through Object.call;
    -- automatic materialization uses BridgeImportExactTokenVisual instead.
    BridgeLog("[Bridge] legacy source-card token button path disabled name=" .. tostring(expectedName))
    callback(nil, "legacy source-card token button path disabled")
end

function BridgeSpawnGenericTokenProxy(expectedName, seatId, callback)
    if expectedName == nil or tostring(expectedName) == "" then
        callback(nil, "generic token proxy requires an authoritative card name")
        return
    end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then
        callback(nil, "generic token proxy has no configured seat")
        return
    end
    local anchor = seat.battlefieldAnchors and seat.battlefieldAnchors.creature or seat.commandAnchor
    local position = anchor and {anchor.x, (anchor.y or 2.0) + 1.5, anchor.z} or {0, 3.0, 0}
    _spawn({
        type = "Card",
        position = position,
        rotation = seat.faceUpRotation or {0, 0, 0},
        callback_function = function(object)
            if not BridgeObjectIsUsable(object) then
                callback(nil, "generic token proxy spawn returned an unusable object")
                return
            end
            local ok, setupError = pcall(function()
                object.setName(tostring(expectedName))
                object.setDescription("Forge-created token; characteristics are authoritative in Forge")
                object.use_hands = false
                object.setLock(false)
            end)
            if not ok then
                callback(nil, "generic token proxy setup failed: " .. tostring(setupError))
                return
            end
            BridgeLog("[Bridge] DEGRADED token presentation: exact art-bearing import unavailable; using generic Forge token proxy for " .. tostring(expectedName))
            BridgeMarkTokenPhysicalObject(object)
            callback(object, nil)
        end
    })
end

function BridgeIsArtBearingCard(object)
    if not BridgeObjectIsUsable(object) or object.tag ~= "Card" then return false end
    local ok, data = pcall(function() return object.getData() end)
    if not ok or type(data) ~= "table" then return false end
    local customDeck = data.CustomDeck
    if type(customDeck) ~= "table" or next(customDeck) == nil then return false end
    for _, deck in pairs(customDeck) do
        if type(deck) == "table" and tostring(deck.FaceURL or "") ~= "" then
            return true
        end
    end
    return false
end

local BRIDGE_TOKEN_IMPORT_BACK_URL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
local BRIDGE_TOKEN_IMPORT_PRIMARY_URL = "https://importer.rikrassen.xyz/build"
local BRIDGE_TOKEN_IMPORT_FALLBACK_URL = "https://importer-m7vpzqazfa-uc.a.run.app/build"

function BridgeExactTokenImportPayload(expectedName)
    return {
        url = "",
        -- This is an exact token request, not a source-card request. The
        -- Rikrassen backend returns one TTS custom-card JSON object for it.
        data = "1 " .. tostring(expectedName),
        backURL = BRIDGE_TOKEN_IMPORT_BACK_URL,
        useStates = true,
        hand = {
            position = {x = 0, y = 0, z = 0},
            forward = {x = 0, y = 0, z = 1},
            right = {x = 1, y = 0, z = 0},
            up = {x = 0, y = 1, z = 0}
        }
    }
end

function BridgeParseExactTokenImportJson(text, expectedName)
    local candidates = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local ok, candidate = pcall(function() return JSON.decode(line) end)
        if ok and type(candidate) == "table" and candidate.error == nil then
            table.insert(candidates, candidate)
        end
    end
    if #candidates ~= 1 then
        return nil, "exact token importer returned " .. tostring(#candidates) .. " visual results"
    end
    local cardJson = candidates[1]
    local importedName = BridgeNormalizeCardName(cardJson.Nickname or "")
    if importedName ~= BridgeNormalizeCardName(expectedName) then
        return nil, "exact token importer returned " .. tostring(cardJson.Nickname) .. " instead of " .. tostring(expectedName)
    end
    local customDeck = cardJson.CustomDeck
    local hasFace = false
    for _, deck in pairs(customDeck or {}) do
        if type(deck) == "table" and tostring(deck.FaceURL or "") ~= "" then hasFace = true; break end
    end
    if cardJson.Name ~= "Card" or tonumber(cardJson.CardID or -1) < 0 or not hasFace then
        return nil, "exact token importer returned a non-art-bearing card JSON"
    end
    return cardJson, nil
end

function BridgeImportExactTokenVisual(expectedName, seatId, callback)
    if expectedName == nil or tostring(expectedName) == "" then
        callback(nil, "exact token visual import requires an authoritative card name")
        return
    end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then
        callback(nil, "exact token visual import has no configured seat")
        return
    end

    local anchor = seat.battlefieldAnchors and seat.battlefieldAnchors.creature or seat.commandAnchor
    local position = {x = anchor and anchor.x or 0, y = (anchor and anchor.y or 2.0) + 1.5, z = anchor and anchor.z or 0}
    local rotation = seat.faceUpRotation or {x = 0, y = 0, z = 0}
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    local completed = false
    local function finish(object, err)
        if completed then return end
        completed = true
        if object ~= nil and not BridgeIsArtBearingCard(object) then
            callback(nil, "exact token visual importer returned a non-art-bearing card")
            return
        end
        callback(object, err)
    end

    local function requestVisual(endpoint, allowFallback)
        WebRequest.custom(endpoint, "POST", true, JSON.encode(BridgeExactTokenImportPayload(expectedName)), {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Vokerr-TTS-MTG-Card-Importer",
            ["X-Client-Version"] = "0.9.1"
        }, function(request)
            if not BridgeRuntimeIsCurrent(epoch) then return end
            if request == nil or request.is_error or tonumber(request.response_code or 0) < 200 or tonumber(request.response_code or 0) >= 300 then
                if allowFallback then
                    requestVisual(BRIDGE_TOKEN_IMPORT_FALLBACK_URL, false)
                else
                    finish(nil, "exact token visual backend failed: " .. tostring(request and (request.error or request.response_code) or "unknown error"))
                end
                return
            end
            local cardJson, parseError = BridgeParseExactTokenImportJson(request.text, expectedName)
            if cardJson == nil then
                finish(nil, parseError)
                return
            end
            local spawnHandled = false
            local function handleSpawned(object)
                if spawnHandled then return end
                spawnHandled = true
                if not BridgeObjectIsUsable(object) then
                    finish(nil, "exact token visual spawn returned an unusable object")
                    return
                end
                BridgeWaitFrames(function()
                    if BridgeIsArtBearingCard(object) then
                        BridgeMarkTokenPhysicalObject(object)
                        BridgeLog("[Bridge] token fetcher resolved via exact Rikrassen visual import for " .. tostring(expectedName))
                        finish(object, nil)
                    else
                        finish(nil, "exact token visual spawn produced no CustomDeck/FaceURL")
                    end
                end, 2)
            end
            local spawnOk, objectOrError = pcall(function()
                return spawnObjectJSON({
                    json = JSON.encode(cardJson), position = position, rotation = rotation,
                    callback_function = handleSpawned
                })
            end)
            if not spawnOk then
                finish(nil, "exact token visual spawn failed: " .. tostring(objectOrError))
                return
            end
            if BridgeObjectIsUsable(objectOrError) then handleSpawned(objectOrError) end
        end)
    end

    requestVisual(BRIDGE_TOKEN_IMPORT_PRIMARY_URL, true)
end

function BridgeFindDeckWithContainedCardName(expectedName, excludeDeckGuidSet)
    if expectedName == nil or expectedName == "" then return nil, nil end
    local preferredUtilityDeck = BridgeGetLiveObjectByGuid("946716")
    local candidates = {}
    local expectedTokenKey = BridgeTokenNameKey(expectedName)

    local function addCandidate(container)
        if not BridgeObjectIsUsable(container) then return end
        if container.tag ~= "Deck" and container.tag ~= "Bag" then return end
        local containerGuid = BridgeSafeObjectGuid(container)
        if containerGuid == nil then return end
        if excludeDeckGuidSet ~= nil and excludeDeckGuidSet[containerGuid] == true then return end

        local contained = {}
        local ok = pcall(function() contained = container.getObjects() or {} end)
        if not ok then return end

        local containerName = string.lower(tostring(BridgeSafeObjectName(container) or ""))
        local scoreBase = 0
        if containerGuid == "946716" then scoreBase = scoreBase + 1000 end
        if BridgeIsPresentationOnlyObject(container) then scoreBase = scoreBase + 500 end
        if container.tag == "Bag" then scoreBase = scoreBase + 250 end
        if string.find(containerName, "token", 1, true) ~= nil then scoreBase = scoreBase + 200 end
        if string.find(containerName, "utility", 1, true) ~= nil then scoreBase = scoreBase + 150 end

        for _, item in ipairs(contained) do
            local containedName = item.nickname or item.name or ""
            local exact = BridgeNormalizeCardName(containedName) == BridgeNormalizeCardName(expectedName)
            local tokenExact = expectedTokenKey ~= "" and BridgeTokenNameKey(containedName) == expectedTokenKey
            if exact or tokenExact then
                local entryScore = scoreBase + (exact and 50 or 0) + (tokenExact and 25 or 0)
                table.insert(candidates, {deck = container, entry = item, score = entryScore})
                return
            end
        end
    end

    if preferredUtilityDeck ~= nil then
        addCandidate(preferredUtilityDeck)
        if #candidates > 0 then return candidates[1].deck, candidates[1].entry end
    end

    for _, object in ipairs(getAllObjects()) do
        addCandidate(object)
    end

    if #candidates == 0 then return nil, nil end
    table.sort(candidates, function(left, right)
        if left.score == right.score then
            local leftGuid = BridgeSafeObjectGuid(left.deck) or ""
            local rightGuid = BridgeSafeObjectGuid(right.deck) or ""
            return leftGuid < rightGuid
        end
        return left.score > right.score
    end)
    return candidates[1].deck, candidates[1].entry
end

function BridgeTakeCardFromTokenFetcher(expectedName, seatId, callback)
    local finished = false
    local function finish(object, err)
        if finished then
            BridgeLog("[Bridge] ignored duplicate token visual callback name=" .. tostring(expectedName))
            return
        end
        finished = true
        callback(object, err)
    end
    local excludeDeckGuidSet = {}
    for _, configuredSeatId in ipairs({"forge-player-1", "forge-player-2"}) do
        local deck = BridgeFindLibraryDeckForSeat(configuredSeatId)
        local guid = deck and BridgeSafeObjectGuid(deck) or nil
        if guid ~= nil then excludeDeckGuidSet[guid] = true end
    end

    local function fallbackVisualImport(reason)
        -- Source-card buttons such as EmblemsAndTokens are not a generic
        -- token-import API.  Their TTS callback ABI is (card, player, alt),
        -- which Object.call cannot reproduce, and they may emit a bundle of
        -- related tokens.  Go directly to the exact one-token visual import;
        -- retain the button scanner only as an explicit legacy diagnostic.
        BridgeLog("[Bridge] exact token visual import requested name=" .. tostring(expectedName)
            .. " reason=" .. tostring(reason or "no art-bearing reusable token"))
        BridgeImportExactTokenVisual(expectedName, seatId, function(imported, importError)
            if imported ~= nil then
                finish(imported, nil)
                return
            end
            BridgeSpawnGenericTokenProxy(expectedName, seatId, function(proxy, proxyError)
                if proxy ~= nil then
                    BridgeLog("[Bridge] DEGRADED token presentation: exact art importer failed name="
                        .. tostring(expectedName) .. " importError=" .. tostring(importError))
                    finish(proxy, nil)
                    return
                end
                finish(nil, "exact token visual import failed: " .. tostring(importError)
                    .. "; generic proxy failed: " .. tostring(proxyError))
            end)
        end)
    end

    local deck, entry = BridgeFindDeckWithContainedCardName(expectedName, excludeDeckGuidSet)
    if deck == nil or entry == nil then
        fallbackVisualImport("no matching reusable token in table containers")
        return
    end

    local seat = BRIDGE_SEATS[seatId]
    local anchor = seat and (seat.commandAnchor or (seat.battlefieldAnchors and seat.battlefieldAnchors.creature)) or nil
    local position = anchor and {anchor.x, (anchor.y or 2.0) + 1.5, anchor.z} or {0, 3.0, 0}
    local options = {
        position = position,
        smooth = false,
        callback_function = function(taken)
            if not BridgeObjectIsUsable(taken) then
                finish(nil, "token fetcher returned an unusable card")
                return
            end
            if BridgeIsArtBearingCard(taken) then
                BridgeMarkTokenPhysicalObject(taken)
                finish(taken, nil)
                return
            end
            -- Do not leave the unusable blank fetch result beside the exact
            -- imported token; one Forge identity must yield one physical card.
            pcall(function() taken.destruct() end)
            fallbackVisualImport("reusable token container returned a blank card")
        end
    }
    if deck.tag == "Deck" then
        options.index = entry.index
    elseif deck.tag == "Bag" then
        options.guid = entry.guid
    else
        finish(nil, "unsupported token container tag " .. tostring(deck.tag))
        return
    end
    deck.takeObject(options)
end

function BridgeSetPhysicalFaceDown(object, seat, faceDown)
    if not BridgeObjectIsUsable(object) then return end
    local faceUp = seat.faceUpRotation
    if faceUp == nil then return end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    local baseRotation = {
        x = faceUp.x,
        y = faceUp.y,
        z = faceUp.z + (faceDown and 180 or 0)
    }
    local rotation = {
        x = baseRotation.x,
        y = baseRotation.y + (BridgeState.physicalTappedByGuid[guid] == true and 90 or 0),
        z = baseRotation.z
    }
    if not BridgeSafeObjectCall(object, function(o) o.setRotation(rotation) end) then return end
    BridgeState.untappedRotationByGuid[guid] = baseRotation
end

function BridgeSetPhysicalTapped(object, tapped)
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    BridgeState.physicalTappedByGuid[guid] = tapped == true
    local base = BridgeState.untappedRotationByGuid[guid]
    if base == nil then
        local ok, rotation = pcall(function() return object.getRotation() end)
        if not ok or rotation == nil then return end
        base = rotation
        BridgeState.untappedRotationByGuid[guid] = base
    end
    local targetY = base.y + (tapped and 90 or 0)
    BridgeSafeObjectCall(object, function(o) o.setRotationSmooth({base.x, targetY, base.z}, false, true) end)
end

function BridgeResolveMappedInstance(event)
    if event.cardInstanceId == nil then
        return nil, "authoritative card-state event has no cardInstanceId"
    end
    local guid = BridgeState.physicalByInstanceId[event.cardInstanceId]
    if guid == nil then
        return nil, "no physical GUID mapped for card instance " .. tostring(event.cardInstanceId)
    end
    local object = getObjectFromGUID(guid)
    if object == nil then
        return nil, "mapped physical object vanished for card instance " .. tostring(event.cardInstanceId)
    end
    return object, nil
end

-- Table-native presentation adapter.  Forge supplies the resulting state; this
-- code only drives the already-installed Encoder modules to display it.
local BRIDGE_UNIFIED_PROPERTY = "_MTG_Simplified_UNIFIED"
local BRIDGE_KEYWORDS_PROPERTY = "πKeywords"
local BRIDGE_PHASE_PROPERTY = "MTG_Phase"
local BRIDGE_COUNTER_FALLBACK_PROPERTY = "ForgeBotState"

function BridgeEnsureTableEncoded(object)
    if not BridgeObjectIsUsable(object) then return nil, "card object is unavailable" end
    local encoder = Global.getVar("Encoder")
    if encoder == nil then return nil, "Easy Modules Encoder is unavailable" end

    local guid = BridgeSafeObjectGuid(object)
    local beforeName = BridgeSafeObjectName(object)
    local beforeDescription = object.getDescription()
    local beforeData = object.getData() or {}
    local beforeNickname = beforeData.Nickname or beforeData.nickname

    local ok, encodedOrError = pcall(function()
        return encoder.call("APIobjectExists", {obj = object})
    end)
    if not ok then return nil, "could not inspect Encoder state: " .. tostring(encodedOrError) end
    if encodedOrError ~= true then
        local encoded, encodeError = BridgeEncoderMutation(object, function()
            encoder.call("APIencodeObject", {obj = object})
        end, "APIencodeObject")
        if not encoded then return nil, "could not encode card: " .. tostring(encodeError) end
    end
    if guid ~= nil and BridgeState.encoderIdentityLoggedGuids[guid] ~= true then
        local afterData = object.getData() or {}
        BridgeState.encoderIdentityLoggedGuids[guid] = true
        BridgeLog(string.format(
            "[Bridge] table-encoding identity guid=%s beforeName=%s afterName=%s beforeDescription=%s afterDescription=%s beforeDataNickname=%s afterDataNickname=%s canonical=%s encoderMetadata=%s",
            tostring(guid), tostring(beforeName), tostring(BridgeSafeObjectName(object)),
            tostring(beforeDescription), tostring(object.getDescription()), tostring(beforeNickname),
            tostring(afterData.Nickname or afterData.nickname), tostring(BridgePhysicalCanonicalCardName(object)),
            encodedOrError == true and "existing" or "encoded"))
    end
    return encoder, nil
end

function BridgeEnsureEncoderProperty(object, propertyId)
    local encoder, encoderError = BridgeEnsureTableEncoded(object)
    if encoder == nil then return nil, encoderError end
    local ok, enabledOrError = pcall(function()
        return encoder.call("APIobjIsPropEnabled", {obj = object, propID = propertyId})
    end)
    if not ok then return nil, "could not inspect Encoder property " .. tostring(propertyId) .. ": " .. tostring(enabledOrError) end
    if enabledOrError ~= true then
        local enabled, enableError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjEnableProp", {obj = object, propID = propertyId})
        end, "APIobjEnableProp")
        if not enabled then return nil, "could not enable Encoder property " .. tostring(propertyId) .. ": " .. tostring(enableError) end
    end
    return encoder, nil
end

local function BridgeCardScaleSnapshot(object)
    local ok, scale = pcall(function() return object.getScale() end)
    if not ok or scale == nil then return nil end
    return {x = scale.x, y = scale.y, z = scale.z}
end

-- The first live game-card scale is its canonical embodiment scale. Zones,
-- token imports, Encoder/state rebuilds, and characteristic changes may alter
-- presentation but must never silently resize that physical card.
function BridgeCaptureCanonicalCardScale(object)
    if object == nil or object.tag ~= "Card" then return nil end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return nil end
    local canonical = BridgeState.canonicalCardScaleByGuid[guid]
    if canonical == nil then
        canonical = BridgeCardScaleSnapshot(object)
        if canonical ~= nil then BridgeState.canonicalCardScaleByGuid[guid] = canonical end
    end
    return canonical
end

function BridgeRestoreCanonicalCardScale(object)
    local guid = BridgeSafeObjectGuid(object)
    local canonical = guid and BridgeState.canonicalCardScaleByGuid[guid] or nil
    if canonical == nil then canonical = BridgeCaptureCanonicalCardScale(object) end
    if canonical ~= nil then BridgeRestoreCardScaleIfChanged(object, canonical) end
end

function BridgeRestoreCardScaleIfChanged(object, beforeScale)
    if beforeScale == nil then return end
    local afterScale = BridgeCardScaleSnapshot(object)
    if afterScale == nil then return end
    if math.abs(afterScale.x - beforeScale.x) > 0.001
        or math.abs(afterScale.y - beforeScale.y) > 0.001
        or math.abs(afterScale.z - beforeScale.z) > 0.001 then
        -- Encoder presentation must never resize a physical game card. Apart
        -- from looking wrong, a changed scale desynchronizes the local keyword
        -- decal geometry from the card it annotates.
        object.setScale(beforeScale)
        BridgeLog("[Bridge] restored card scale after Encoder rebuild guid=" .. tostring(BridgeSafeObjectGuid(object)))
    end
end

-- All Encoder mutations on real game cards cross this boundary.  The first
-- call captures the canonical scale before Encoder can alter the transform;
-- the immediate and deferred restores cover both synchronous and delayed TTS
-- rebuild work.  Presentation-only helper objects are intentionally exempt.
function BridgeEncoderMutation(object, operation, label)
    if object == nil or object.tag ~= "Card" then
        return pcall(operation)
    end
    local canonical = BridgeCaptureCanonicalCardScale(object)
    local ok, result = pcall(operation)
    if canonical ~= nil then
        BridgeRestoreCardScaleIfChanged(object, canonical)
        BridgeWaitFrames(function()
            if BridgeObjectIsUsable(object) then
                BridgeRestoreCardScaleIfChanged(object, canonical)
            end
        end, 2)
    end
    if not ok then return false, result end
    BridgeLog("[Bridge] Encoder mutation scale-safe operation=" .. tostring(label or "unknown")
        .. " guid=" .. tostring(BridgeSafeObjectGuid(object)))
    return true, result
end

function BridgeMutateUnifiedState(object, mutate)
    local encoder, encoderError = BridgeEnsureEncoderProperty(object, BRIDGE_UNIFIED_PROPERTY)
    if encoder == nil then return false, encoderError end
    local ok, applyError = pcall(function()
        local encoded = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_UNIFIED_PROPERTY})
        if encoded == nil or encoded.tyrantUnified == nil then error("card lacks Easy Modules Unified metadata") end
        mutate(encoded.tyrantUnified)
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_UNIFIED_PROPERTY, data = encoded})
            BridgePresentationMetric("unifiedPropWriteCount")
            -- Rebuild through Encoder: direct card buttons do not survive this call.
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "APIobjSetPropData+APIrebuildButtons")
        if not mutated then error(mutationError) end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeSetUnifiedState(object, patch)
    if type(patch) ~= "table" then return false, "Unified patch must be a table" end
    return BridgeMutateUnifiedState(object, function(unified)
        for field, value in pairs(patch) do
            unified[field] = value
        end
    end)
end

local function BridgeUnifiedPrintedFace(unified)
    local faces = unified and unified.cardFaces or nil
    if type(faces) ~= "table" then return nil end
    local activeFace = unified.activeFace
    local face = activeFace ~= nil and faces[activeFace] or nil
    -- Easy Modules alternate layouts do not consistently populate activeFace.
    -- The imported front is still the correct printed base unless Forge later
    -- supplies a verified face change.
    if face == nil then face = faces[1] or faces[0] or faces.front end
    if face == nil then
        for _, candidate in pairs(faces) do
            if type(candidate) == "table" then face = candidate; break end
        end
    end
    return face
end

local function BridgeApplyDerivedStatsToUnified(unified, power, toughness)
    if power == nil and toughness == nil then
        -- Clear stale imported P/T values as well as hiding the display. A
        -- land that previously held a creature must never retain its old
        -- derived characteristics in Unified.
        unified.power = 0
        unified.toughness = 0
        unified.displayPowTou = false
        return
    end
    local cardFace = BridgeUnifiedPrintedFace(unified)
    local basePower = cardFace and tonumber(cardFace.basePower) or nil
    local baseToughness = cardFace and tonumber(cardFace.baseToughness) or nil
    if power ~= nil then unified.power = basePower and (tonumber(power) - basePower) or tonumber(power) end
    if toughness ~= nil then unified.toughness = baseToughness and (tonumber(toughness) - baseToughness) or tonumber(toughness) end
    unified.displayPowTou = true
end

function BridgeSetDerivedStats(object, power, toughness)
    local guid = BridgeSafeObjectGuid(object)
    local previous = guid and BridgeState.presentedStatsByGuid[guid] or nil
    if previous ~= nil and previous.power == power and previous.toughness == toughness then return true, nil end
    return BridgeMutateUnifiedState(object, function(unified)
        BridgeApplyDerivedStatsToUnified(unified, power, toughness)
        if guid ~= nil then BridgeState.presentedStatsByGuid[guid] = {power = power, toughness = toughness} end
    end)
end

local function BridgeApplyOwnerControllerToUnified(unified, ownerSeatId, controllerSeatId)
    local ownerSeat = BRIDGE_SEATS[ownerSeatId]
    local controllerSeat = BRIDGE_SEATS[controllerSeatId]
    if ownerSeat ~= nil then unified.ownerColor = ownerSeat.ttsColor end
    if controllerSeat ~= nil then unified.controllerColor = controllerSeat.ttsColor end
    unified.displayOwnership = ownerSeat ~= nil or controllerSeat ~= nil
end

function BridgeSetOwnerController(object, ownerSeatId, controllerSeatId)
    local guid = BridgeSafeObjectGuid(object)
    local signature = tostring(ownerSeatId or "") .. "|" .. tostring(controllerSeatId or "")
    if guid ~= nil and BridgeState.presentedOwnerControllerByGuid[guid] == signature then return true, nil end
    return BridgeMutateUnifiedState(object, function(unified)
        BridgeApplyOwnerControllerToUnified(unified, ownerSeatId, controllerSeatId)
        if guid ~= nil then BridgeState.presentedOwnerControllerByGuid[guid] = signature end
    end)
end

function BridgeSetPhasedState(object, phased)
    -- On this table the Phasing property has visible behavior merely by being
    -- enabled.  It must not be activated as a generic false-state container.
    local encoder, encoderError = BridgeEnsureTableEncoded(object)
    if encoder == nil then return false, encoderError end
    local guid = BridgeSafeObjectGuid(object)
    if guid ~= nil and BridgeState.presentedPhasedByGuid[guid] == (phased == true) then return true, nil end
    local ok, applyError = pcall(function()
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            local enabled = encoder.call("APIobjIsPropEnabled", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
            if phased == true then
                if enabled ~= true then
                    encoder.call("APIobjEnableProp", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
                end
                local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
                if data == nil then error("card lacks Phasing metadata") end
                data.mtg_phased = true
                encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY, data = data})
            elseif enabled == true then
                -- Clear stale module data before hiding the property so a later,
                -- genuine phasing event cannot resurrect an old visual state.
                local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
                if data ~= nil then
                    data.mtg_phased = false
                    encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY, data = data})
                end
                encoder.call("APIobjDisableProp", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
            end
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "phase-property+APIrebuildButtons")
        if not mutated then error(mutationError) end
        if guid ~= nil then BridgeState.presentedPhasedByGuid[guid] = phased == true end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeSetFaceState(object, forgeState, seatId)
    if object == nil or forgeState == nil then return object end
    local guid = BridgeSafeObjectGuid(object)
    local resolvedSeatId = seatId or (guid and BridgeState.physicalSeatByGuid[guid]) or forgeState.ownerSeatId
    local seat = BRIDGE_SEATS[resolvedSeatId]
    if seat ~= nil and forgeState.faceDown ~= nil then
        -- Face-down is an explicit Forge state. Do not infer Morph/Manifest or
        -- DFC state IDs from text; a native state replacement needs a runtime
        -- verified structured face identifier before it is safe to use.
        BridgeSetPhysicalFaceDown(object, seat, forgeState.faceDown == true)
    end
    return object
end

function BridgeApplyCardPresentationSnapshot(object, cardSnapshot)
    if object == nil or cardSnapshot == nil then return false, "missing card presentation input" end
    BridgeSetFaceState(object, cardSnapshot)
    local guid = BridgeSafeObjectGuid(object)
    local stats = {power = cardSnapshot.currentPower, toughness = cardSnapshot.currentToughness}
    local types = cardSnapshot.currentTypes or {}
    if #types > 0 then
        local creature = false
        for _, cardType in ipairs(types) do
            if string.lower(tostring(cardType)) == "creature" then creature = true; break end
        end
        if not creature then stats.power, stats.toughness = nil, nil end
    end
    local ownerSignature = tostring(cardSnapshot.ownerSeatId or "") .. "|" .. tostring(cardSnapshot.controllerSeatId or "")
    local statsChanged = guid == nil
        or BridgeState.presentedStatsByGuid[guid] == nil
        or BridgeState.presentedStatsByGuid[guid].power ~= stats.power
        or BridgeState.presentedStatsByGuid[guid].toughness ~= stats.toughness
    local ownershipChanged = guid == nil or BridgeState.presentedOwnerControllerByGuid[guid] ~= ownerSignature
    if statsChanged or ownershipChanged then
        local applied, applyError = BridgeMutateUnifiedState(object, function(unified)
            if statsChanged then BridgeApplyDerivedStatsToUnified(unified, stats.power, stats.toughness) end
            if ownershipChanged then BridgeApplyOwnerControllerToUnified(unified, cardSnapshot.ownerSeatId, cardSnapshot.controllerSeatId) end
            if guid ~= nil then
                BridgeState.presentedStatsByGuid[guid] = stats
                BridgeState.presentedOwnerControllerByGuid[guid] = ownerSignature
            end
        end)
        if not applied then return false, applyError end
    end
    local phased, phaseError = BridgeSetPhasedState(object, cardSnapshot.phasedOut == true)
    if not phased then BridgeLog("[Bridge] optional phasing presentation skipped: " .. tostring(phaseError)) end
    return true, nil
end

-- Existing table integration: Easy Modules Unified is the authoritative visual
-- sink for +1/+1 and generic named counters. Values are set absolutely so event
-- replay cannot double the physical display.
function BridgeNormalizeCounterName(counterType)
    local normalized = string.lower(tostring(counterType or ""))
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    return normalized
end

function BridgeCopyCounterMap(counters)
    local result = {}
    for counterType, counterValue in pairs(counters or {}) do
        local normalized = BridgeNormalizeCounterName(counterType)
        local numeric = tonumber(counterValue) or 0
        if normalized ~= "" and numeric > 0 then result[normalized] = numeric end
    end
    return result
end

function BridgeSetCardCounters(object, absoluteCounters)
    local counters = BridgeCopyCounterMap(absoluteCounters)
    local plusOne = counters["+1/+1"] or 0
    local named = {}
    for counterType, counterValue in pairs(counters) do
        if counterType ~= "+1/+1" and counterType ~= "stun" then
            table.insert(named, {counterType = counterType, counterValue = counterValue})
        end
    end
    table.sort(named, function(left, right) return left.counterType < right.counterType end)
    local signatureParts = {"+1/+1=" .. tostring(plusOne), "stun=" .. tostring(counters.stun or 0)}
    for _, entry in ipairs(named) do table.insert(signatureParts, entry.counterType .. "=" .. tostring(entry.counterValue)) end
    local signature = table.concat(signatureParts, "|")
    local guid = BridgeSafeObjectGuid(object)
    local unifiedAlreadyPresented = guid ~= nil and BridgeState.presentedCounterSignatureByGuid[guid] == signature
    if not unifiedAlreadyPresented then
        local applied, applyError = BridgeMutateUnifiedState(object, function(unified)
            unified.plusOneCounters = plusOne
            unified.displayPlusOne = plusOne ~= 0
            -- Unified has one generic named counter display. Never combine
            -- different Forge counter types into an invented total.
            if #named == 1 then
                unified.namedCounters = named[1].counterValue
                unified.displayCounters = named[1].counterValue ~= 0
            else
                unified.namedCounters = 0
                unified.displayCounters = false
            end
            if guid ~= nil then BridgeState.presentedCounterSignatureByGuid[guid] = signature end
        end)
        if not applied then return false, applyError end

        local stunApplied, stunError = BridgeSetCardKeywordState(object, "stun", (counters.stun or 0) > 0)
        if not stunApplied then
            BridgeLog("[Bridge] optional stun presentation skipped: " .. tostring(stunError))
        end
    end

    local fallbackSignature = table.concat(signatureParts, "|")
    local fallbackAlreadyPresented = guid ~= nil
        and BridgeState.presentedCounterFallbackSignatureByGuid[guid] == fallbackSignature
    if not fallbackAlreadyPresented then
        local fallbackApplied, fallbackError = BridgeSetForgeBotCounterFallback(object, named)
        if fallbackApplied then
            if guid ~= nil then BridgeState.presentedCounterFallbackSignatureByGuid[guid] = fallbackSignature end
        else
            -- Do not cache failure. Encoder can become available after the
            -- first snapshot; an unchanged authoritative lore/level counter
            -- must be retried on a later reconciliation.
            BridgeLog("[Bridge] optional counter fallback skipped: " .. tostring(fallbackError))
        end
    end
    return true, nil
end

function BridgeSetCardCounterState(object, counterType, counterValue)
    if counterValue == nil or counterValue < 0 then
        return false, "invalid authoritative counter value " .. tostring(counterValue)
    end
    local field = nil
    if counterType == "+1/+1" then field = "plusOneCounters" end
    if counterType == "named" then field = "namedCounters" end
    if field == nil then
        return false, "unsupported existing-table counter type " .. tostring(counterType)
    end

    local ok, applyError = BridgeMutateUnifiedState(object, function(unified)
        unified[field] = counterValue
        if field == "plusOneCounters" then unified.displayPlusOne = counterValue ~= 0 end
        if field == "namedCounters" then unified.displayCounters = counterValue ~= 0 end
    end)
    return ok, applyError
end

local BRIDGE_KEYWORD_PROPERTIES = {
    flying = "mtg_flyingcounter", haste = "mtg_hastecounter",
    deathtouch = "mtg_deathtouchcounter", defender = "mtg_defendercounter",
    ["double strike"] = "mtg_doublestrikecounter", ["first strike"] = "mtg_firststrikecounter",
    hexproof = "mtg_hexproofcounter", indestructible = "mtg_indestructiblecounter",
    lifelink = "mtg_lifelinkcounter", menace = "mtg_menacecounter",
    reach = "mtg_reachcounter", trample = "mtg_tramplecounter",
    vigilance = "mtg_vigilancecounter", stun = "mtg_stuncounter"
}

-- πKeywords only creates decals when its own UI toggle marks a global redraw.
-- Forge updates property data directly, so mirror the module's visible decal
-- output for both `art` and alternate `above` layouts without changing rules.
local BRIDGE_KEYWORD_DECALS = {
    flying = {name="Flying", url="http://cloud-3.steamusercontent.com/ugc/1647720820459775349/912974BD1EAE7E35274F2228F0275C08473F73C2/"},
    haste = {name="Haste", url="http://cloud-3.steamusercontent.com/ugc/1647720820459776460/2384D15814E736DCED6F3D755E9C7750DE844CF1/"},
    deathtouch = {name="Deathtouch", url="http://cloud-3.steamusercontent.com/ugc/1647720820459770551/8ED7C2CF930BB048D5D0F281CEE139681D9FC132/"},
    defender = {name="Defender", url="http://cloud-3.steamusercontent.com/ugc/1647720820459771131/766BD64F624C102D6B7824B3D2065DEF1F15BD65/"},
    ["double strike"] = {name="Double Strike", url="http://cloud-3.steamusercontent.com/ugc/1647720820459771597/06334C3958CF7B3C50A76A4F2F22ACD6389D2169/"},
    ["first strike"] = {name="First Strike", url="http://cloud-3.steamusercontent.com/ugc/1647720820459774469/9FB16BFF1B02B2455C3D844127EC39A141534F33/"},
    hexproof = {name="Hexproof", url="http://cloud-3.steamusercontent.com/ugc/1647720820459777186/41A7105B5FBBFE116EBFD950C5809724CCD508B1/"},
    indestructible = {name="Indestructible", url="http://cloud-3.steamusercontent.com/ugc/1647721275620396729/06E0D42899D763E8C179326CB8A904543C1F25DA/"},
    lifelink = {name="Lifelink", url="https://steamusercontent-a.akamaihd.net/ugc/1647720820459778541/EC0A9AE3F2A92ED0070E0050A3AB451046D79A35/"},
    menace = {name="Menace", url="http://cloud-3.steamusercontent.com/ugc/1647720820459779239/1C65FC6264E001EB3DCBC88A8473B0EABE33834A/"},
    reach = {name="Reach", url="http://cloud-3.steamusercontent.com/ugc/1647720820459781368/2390550F830E8BF214F9FF9CD971976A35C95230/"},
    trample = {name="Trample", url="http://cloud-3.steamusercontent.com/ugc/1647720820459785398/41B89DCAC842C5C2624AC5EFA9428492C2841515/"},
    vigilance = {name="Vigilance", url="http://cloud-3.steamusercontent.com/ugc/1647720820459786000/AF931371F2426EF81E336C0BD668EA983AE843D9/"}
}

function BridgeRenderKeywordDecals(object, enabled, encoder)
    local active = {}
    for keyword, isEnabled in pairs(enabled or {}) do if isEnabled and BRIDGE_KEYWORD_DECALS[keyword] ~= nil then table.insert(active, keyword) end end
    table.sort(active)
    local removable = {}
    for _, definition in pairs(BRIDGE_KEYWORD_DECALS) do removable[definition.name] = true end
    local decals = object.getDecals() or {}
    local retained = {}
    for _, decal in ipairs(decals) do if not removable[decal.name] then table.insert(retained, decal) end end
    local layout = "art"
    local ok, layoutData = pcall(function() return encoder.call("APIobjGetValueData", {obj = object, valueID = "iconLayout"}) end)
    if ok and layoutData ~= nil and layoutData.iconLayout ~= nil then layout = layoutData.iconLayout end
    local flip = 1
    local flipOk, flipValue = pcall(function() return encoder.call("APIgetFlip", {obj = object}) end)
    if flipOk and tonumber(flipValue) ~= nil then flip = tonumber(flipValue) end
    for index, keyword in ipairs(active) do
        local position = nil
        local scale = nil
        if layout == "above" then
            local column = (index - 1) % 5
            local row = math.floor((index - 1) / 5)
            position = {(-1) * (1 - 1 / 5 - column * (2 / 5)) * flip, 0.3 * flip, -1.55 - 1 / 5 - row * 2 / 5}
            scale = {0.8, 0.8, 0.8}
        else
            position = {0, 0.3 * flip, -0.5 + (index - 1) * 0.45}
            scale = {0.55, 0.55, 0.55}
        end
        local definition = BRIDGE_KEYWORD_DECALS[keyword]
        table.insert(retained, {name = definition.name, url = definition.url, position = position, rotation = {180 - flip * 90, 90 + flip * 90, 0}, scale = scale})
    end
    object.setDecals(retained)
    BridgePresentationMetric("decalWriteCount")
end

function BridgeEnsureKeywordIconLayout(object, encoder)
    local guid = BridgeSafeObjectGuid(object)
    if guid ~= nil and BridgeState.presentedIconLayoutByGuid[guid] == "above" then return true, nil, false end
    local ok, valueData = pcall(function()
        return encoder.call("APIobjGetValueData", {obj = object, valueID = "iconLayout"})
    end)
    if not ok then return false, "could not inspect icon layout", false end
    if valueData ~= nil and valueData.iconLayout == "above" then
        if guid ~= nil then BridgeState.presentedIconLayoutByGuid[guid] = "above" end
        return true, nil, false
    end
    local applied, applyError = BridgeEncoderMutation(object, function()
        encoder.call("APIobjSetValueData", {obj = object, valueID = "iconLayout", data = {iconLayout = "above"}})
    end, "APIobjSetValueData")
    if not applied then return false, tostring(applyError), false end
    if guid ~= nil then BridgeState.presentedIconLayoutByGuid[guid] = "above" end
    return true, nil, true
end

function BridgeNormalizeKeywordName(keyword)
    local normalized = string.lower(tostring(keyword or ""))
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    normalized = string.gsub(normalized, "%s+", " ")
    local reminderStart = string.find(normalized, " (", 1, true)
    if reminderStart ~= nil then
        normalized = string.sub(normalized, 1, reminderStart - 1)
        normalized = string.gsub(normalized, "%s+$", "")
    end
    normalized = string.gsub(normalized, "%.$", "")
    return normalized
end

function BridgeSetCardKeywordState(object, keyword, enabled)
    local normalized = BridgeNormalizeKeywordName(keyword)
    local property = BRIDGE_KEYWORD_PROPERTIES[normalized]
    if property == nil then return false, "unsupported existing-table keyword " .. tostring(keyword) end

    local encoder, encoderError = BridgeEnsureEncoderProperty(object, BRIDGE_KEYWORDS_PROPERTY)
    if encoder == nil then return false, encoderError end
    local layoutOk, layoutError = BridgeEnsureKeywordIconLayout(object, encoder)
    if not layoutOk then return false, layoutError end
    local ok, applyError = pcall(function()
        local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY})
        if data == nil then error("card is not encoded with πKeywords") end
        data[property] = enabled and 1 or 0
        data.activeIcons = data.activeIcons or {}
        local found = nil
        for index, value in ipairs(data.activeIcons) do
            if value == property then found = index; break end
        end
        if enabled and found == nil then table.insert(data.activeIcons, property) end
        if not enabled and found ~= nil then table.remove(data.activeIcons, found) end
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY, data = data})
            BridgePresentationMetric("keywordPropWriteCount")
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "keyword-state+APIrebuildButtons")
        if not mutated then error(mutationError) end
        BridgeRenderKeywordDecals(object, enabled, encoder)
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeSetCardKeywords(object, absoluteKeywords)
    local enabled = {}
    local unsupported = {}
    for _, keyword in ipairs(absoluteKeywords or {}) do
        local normalized = BridgeNormalizeKeywordName(keyword)
        if BRIDGE_KEYWORD_PROPERTIES[normalized] ~= nil then
            enabled[normalized] = true
        elseif normalized ~= "" then
            table.insert(unsupported, normalized)
        end
    end
    local supported = {}
    for keyword, isEnabled in pairs(enabled) do if isEnabled then table.insert(supported, keyword) end end
    table.sort(supported)
    table.sort(unsupported)
    local guid = BridgeSafeObjectGuid(object)
    local signature = table.concat(supported, "|")
    local encoder, encoderError = BridgeEnsureEncoderProperty(object, BRIDGE_KEYWORDS_PROPERTY)
    if encoder == nil then return false, encoderError end
    local layoutOk, layoutError, layoutChanged = BridgeEnsureKeywordIconLayout(object, encoder)
    if not layoutOk then return false, layoutError end
    if guid ~= nil and BridgeState.presentedKeywordSignatureByGuid[guid] == signature then
        if layoutChanged then
            local rebuilt, rebuildError = BridgeEncoderMutation(object, function()
                encoder.call("APIrebuildButtons", {obj = object})
                BridgePresentationMetric("encoderRebuildCount")
            end, "keyword-layout+APIrebuildButtons")
            if not rebuilt then return false, rebuildError end
        end
        return true, nil
    end
    for _, keyword in ipairs(unsupported) do
        local logKey = tostring(guid or "unknown") .. "|" .. keyword
        if BridgeState.unsupportedKeywordLogged[logKey] ~= true then
            BridgeState.unsupportedKeywordLogged[logKey] = true
            BridgeLog("[Bridge] presentation capability gap: unsupported native keyword icon " .. tostring(keyword))
        end
    end
    local ok, applyError = pcall(function()
        local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY})
        if data == nil then error("card lacks πKeywords metadata") end
        data.activeIcons = {}
        for keyword, property in pairs(BRIDGE_KEYWORD_PROPERTIES) do
            local isEnabled = enabled[keyword] == true
            data[property] = isEnabled and 1 or 0
            if isEnabled then table.insert(data.activeIcons, property) end
        end
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY, data = data})
            BridgePresentationMetric("keywordPropWriteCount")
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "keywords+APIrebuildButtons")
        if not mutated then error(mutationError) end
        BridgeRenderKeywordDecals(object, enabled, encoder)
        if guid ~= nil then BridgeState.presentedKeywordSignatureByGuid[guid] = signature end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

-- This hidden Encoder property is only enabled when Unified's single generic
-- counter display cannot faithfully show the complete Forge counter map.
function BridgeEnsureForgeBotCounterFallbackProperty()
    local encoder = Global.getVar("Encoder")
    if encoder == nil then return nil, "Easy Modules Encoder is unavailable" end
    local ok, existsOrError = pcall(function()
        return encoder.call("APIpropertyExists", {propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
    end)
    if not ok then return nil, "could not inspect ForgeBot counter property: " .. tostring(existsOrError) end
    if existsOrError ~= true then
        local registered, registerError = pcall(function()
            encoder.call("APIregisterProperty", {
                propID = BRIDGE_COUNTER_FALLBACK_PROPERTY,
                name = "ForgeBot Counters",
                values = {},
                funcOwner = Global,
                activateFunc = "",
                visible = false
            })
        end)
        if not registered then return nil, "could not register ForgeBot counter property: " .. tostring(registerError) end
    end
    return encoder, nil
end

function BridgeSetForgeBotCounterFallback(object, namedCounters)
    local encoder, encoderError = BridgeEnsureForgeBotCounterFallbackProperty()
    if encoder == nil then return false, encoderError end
    -- Encoder's generic counter presentation is not reliably visible for a
    -- single named counter, such as lore on a Saga or level on a Class.
    local needsFallback = #(namedCounters or {}) > 0
    local ok, applyError = pcall(function()
        local encoded = encoder.call("APIobjectExists", {obj = object})
        if encoded ~= true then error("card is not Encoder-managed") end
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            local enabled = encoder.call("APIobjIsPropEnabled", {obj = object, propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
            if needsFallback and enabled ~= true then
                encoder.call("APIobjEnableProp", {obj = object, propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
            elseif not needsFallback and enabled == true then
                encoder.call("APIobjDisableProp", {obj = object, propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
            end
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "counter-fallback+APIrebuildButtons")
        if not mutated then error(mutationError) end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeIgnoreCardPresentationClick()
end

-- Encoder invokes createButtons on the property owner during every rebuild.
-- This is deliberately a property-owned button, never a persistent direct card
-- button that would be erased by APIrebuildButtons.
function createButtons(t)
    local object = t and t.obj or nil
    local guid = BridgeSafeObjectGuid(object)
    local instanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
    local counters = instanceId and BridgeState.counterStateByInstanceId[instanceId] or nil
    if counters == nil then return end
    local labels = {}
    for counterType, counterValue in pairs(counters) do
        if counterType ~= "+1/+1" and counterType ~= "stun" and tonumber(counterValue or 0) > 0 then
            table.insert(labels, tostring(counterType) .. " " .. tostring(counterValue))
        end
    end
    table.sort(labels)
    if #labels == 0 then return end
    BridgeSafeObjectCall(object, function(card)
        card.createButton({
            click_function = "BridgeIgnoreCardPresentationClick",
            function_owner = Global,
            label = table.concat(labels, "\n"),
            position = {0.82, 0.29, -1.05},
            rotation = {0, 0, 0},
            width = 0,
            height = 0,
            font_size = 105,
            color = {0, 0, 0, 0},
            font_color = {1, 0.9, 0.35, 1},
            tooltip = "Forge-authoritative counters"
        })
    end)
end

function BridgeResolvePhysicalCard(event, expectedZone, options)
    options = options or {}
    if not options.skipMappedLookup and event.cardInstanceId ~= nil then
        local existingGuid = BridgeState.physicalByInstanceId[event.cardInstanceId]
        if existingGuid ~= nil then
            local existing = getObjectFromGUID(existingGuid)
            if existing == nil then
                -- TTS Card GUIDs can disappear when cards become deck-contained.
                BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
                BridgeState.physicalSeatByGuid[existingGuid] = nil
                BridgeState.physicalZoneByGuid[existingGuid] = nil
                BridgeAdvancePhysicalPresentationGeneration("missing-card-mapping")
            else
                if existing.tag == "Card" then
                    local mappedZone = BridgeState.physicalZoneByGuid[existingGuid]
                    if expectedZone == "hand" and mappedZone ~= "hand" then
                        -- A land-play event can race the physical hand-zone
                        -- bookkeeping. The exact Forge-instance mapping is
                        -- still authoritative, but only trust it here when
                        -- TTS confirms that this same GUID is actually in the
                        -- configured seat hand.
                        local handObjects = BridgeTryGetSeatHandObjects(event.seatId)
                        for _, handObject in ipairs(handObjects or {}) do
                            if BridgeSafeObjectGuid(handObject) == existingGuid then
                                BridgeRecordLooseCardIdentity(event.cardInstanceId, existingGuid, event.seatId, "hand")
                                BridgeLog(string.format(
                                    "[Bridge] repaired stale hand mapping event=%s instance=%s guid=%s previousZone=%s",
                                    tostring(event.sequence), tostring(event.cardInstanceId), tostring(existingGuid), tostring(mappedZone)))
                                return existing, nil
                            end
                        end
                    end
                    if options.allowMappedZoneMismatch == true or expectedZone == nil or mappedZone == nil or mappedZone == expectedZone then
                        return existing, nil
                    end
                end
                if expectedZone == "library" and existing.tag == "Deck" then
                    return existing, nil
                end
                if existing.tag ~= "Card" and not (expectedZone == "library" and existing.tag == "Deck") then
                    -- A stale mapping can temporarily point at a deck object while the
                    -- authoritative card instance has moved into a public zone.
                    BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
                    BridgeAdvancePhysicalPresentationGeneration("stale-object-mapping")
                end
            end
        end
    end

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then
        return nil, BridgePhysicalMappingError(event, expectedZone, 0, "seat is not configured")
    end

    local source = {}
    if expectedZone == "hand" then
        local handObjects, handError = BridgeTryGetSeatHandObjects(event.seatId)
        if handObjects == nil then
            return nil, BridgePhysicalMappingError(event, expectedZone, 0, handError)
        end
        source = handObjects
    elseif expectedZone == "library" then
        local deck = nil
        if event.cardName ~= nil and event.cardName ~= "" then
            deck = BridgeFindSeatLibraryDeckWithCard(seat, event.cardName)
        end
        if deck == nil then deck = BridgeFindLibraryDeckForSeat(event.seatId) end
        if deck ~= nil then
            return deck, nil
        end
        return nil, BridgePhysicalMappingError(event, expectedZone, 0, "library deck not found or empty")
    else
        for _, object in ipairs(getAllObjects()) do
            if object.tag == "Card"
                and IsGameCardCandidate(object, event.seatId, nil)
                and BridgeState.physicalSeatByGuid[object.getGUID()] == event.seatId
                and BridgeState.physicalZoneByGuid[object.getGUID()] == expectedZone then
                table.insert(source, object)
            end
        end
    end

    local matches = {}
    for _, sourceObject in ipairs(source) do
        if sourceObject.tag == "Card" then
            if event.cardName == nil or event.cardName == "" or BridgeCardNameMatches(sourceObject.getName(), event.cardName) then
                table.insert(matches, sourceObject)
            end
        end
    end

    if #matches == 0 and options.allowUntrackedByName == true then
        -- A semantic attack/block event can arrive before the normal snapshot
        -- has recorded the physical reverse mapping. Recover only from a
        -- unique, same-seat, same-name game card; never guess among duplicates.
        for _, candidate in ipairs(getAllObjects()) do
            if candidate.tag == "Card"
                and IsGameCardCandidate(candidate, event.seatId, nil)
                and BridgeObjectIsOnSeatSide(candidate, seat)
                and (event.cardName == nil or event.cardName == "" or BridgeCardNameMatches(candidate.getName(), event.cardName)) then
                table.insert(matches, candidate)
            end
        end
        if #matches == 1 then
            BridgeLog("[Bridge] repaired untracked attack presentation mapping instance=" .. tostring(event.cardInstanceId)
                .. " guid=" .. tostring(matches[1].getGUID()))
        end
    end

    if #matches ~= 1 then
        return nil, BridgePhysicalMappingError(event, expectedZone, #matches, "cannot uniquely identify physical card")
    end

    local object = matches[1]
    local guid = object.getGUID()
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, expectedZone)
    return object, nil
end

function BridgePhysicalMappingError(event, expectedZone, candidateCount, detail, options)
    options = options or {}
    local mappedGuid = options.mappedGuid or (event.cardInstanceId and BridgeState.physicalByInstanceId[event.cardInstanceId] or nil)
    local mappedObject = BridgeGetLiveObjectByGuid(mappedGuid)
    local mappedTag = mappedObject and mappedObject.tag or "nil"
    return string.format(
        "physical mapping failed: seq=%s kind=%s seat=%s instance=%s card='%s' source=%s dest=%s expectedZone=%s mappedGuid=%s mappedTag=%s candidates=%d (%s)",
        tostring(event.sequence),
        tostring(event.kind),
        tostring(event.seatId),
        tostring(event.cardInstanceId),
        tostring(event.cardName),
        tostring(event.sourceZone),
        tostring(event.destinationZone),
        tostring(expectedZone),
        tostring(mappedGuid),
        tostring(mappedTag),
        candidateCount,
        tostring(detail))
end

function BridgeBattlefieldRowForEvent(event, defaultRow)
    if event ~= nil then
        local hasCurrentType = false
        for _, cardType in ipairs(event.currentTypes or {}) do
            local normalizedType = string.lower(tostring(cardType))
            if normalizedType ~= "" then hasCurrentType = true end
            if normalizedType == "land" then return "land" end
        end
        -- CurrentTypes is the live Forge characteristic state. Prefer it
        -- whenever present so a stale event-level BattlefieldKind cannot put
        -- a land into the permanent row (or vice versa).
        if hasCurrentType then
            return "creature"
        end
        if event.battlefieldKind == "land" or event.battlefieldKind == "creature" then
            return event.battlefieldKind
        end
        local knownRow = event.cardInstanceId ~= nil
            and BridgeState.battlefieldKindByInstanceId[event.cardInstanceId] or nil
        if knownRow == "land" or knownRow == "creature" then return knownRow end
    end
    return defaultRow == "land" and "land" or "creature"
end

function BridgeMoveToBattlefield(event, object, row, countAsNewPlacement)
    row = row == "land" and "land" or "creature"
    if event ~= nil and event.cardInstanceId ~= nil then
        BridgeState.battlefieldKindByInstanceId[event.cardInstanceId] = row
    end
    BridgeLog(string.format("[Bridge] ROW_PLACEMENT seat=%s instance=%s row=%s source=%s destination=%s",
        tostring(event and event.seatId), tostring(event and event.cardInstanceId), tostring(row),
        tostring(event and event.sourceZone), tostring(event and event.destinationZone)))
    local destination, positionError = BridgeBattlefieldPosition(event.seatId, row)
    if destination == nil then
        return false, positionError
    end

    local sourcePhysicalZone = nil
    local guidBeforeMove = BridgeSafeObjectGuid(object)
    if guidBeforeMove ~= nil then sourcePhysicalZone = BridgeState.physicalZoneByGuid[guidBeforeMove] end
    local moved, movementError = pcall(function()
        local prepared, prepareError = BridgePreparePhysicalCardForPublicZoneMove(object, "battlefield")
        if not prepared then error(prepareError) end
        BridgeCaptureCanonicalCardScale(object)
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, BRIDGE_SEATS[event.seatId], event.faceDown == true)
        object.setPosition(destination)
        BridgeRestoreCanonicalCardScale(object)
    end)
    if not moved then
        return false, "event " .. tostring(event.sequence) .. " could not move physical card: " .. tostring(movementError)
    end

    BridgeTracePermanentTransition(
        "PHYSICAL_MOVE_TO_BATTLEFIELD", event, object, sourcePhysicalZone)

    -- TTS hand/Encoder presentation can apply a scale change on the frame in
    -- which the card leaves its prior container. Restore again after that
    -- deferred work has run. Also verify the exact object did not get put back
    -- at the temporary stack anchor by a previously queued smooth movement.
    BridgeWaitFrames(function()
        if not BridgeObjectIsUsable(object) then return end
        if guidBeforeMove == nil or BridgeState.physicalZoneByGuid[guidBeforeMove] ~= "battlefield" then return end
        BridgeRestoreCanonicalCardScale(object)
        if not BridgePhysicalObjectAtStackAnchor(object) then return end
        local corrected = pcall(function() object.setPosition(destination) end)
        BridgeTracePermanentTransition(
            "PHYSICAL_MOVE_TO_BATTLEFIELD", event, object, "stack",
            corrected and "deferred stack-anchor correction" or "deferred correction failed")
        if corrected then
            BridgeRestoreCanonicalCardScale(object)
            BridgeWaitFrames(function()
                if not BridgeObjectIsUsable(object) then return end
                if BridgeState.physicalZoneByGuid[guidBeforeMove] ~= "battlefield" then return end
                if BridgePhysicalObjectAtStackAnchor(object) then
                    BridgeStopOnDesync(BridgePhysicalMappingError(
                        event, "battlefield", 1,
                        "exact battlefield card remained at the physical stack anchor",
                        {mappedGuid = guidBeforeMove}))
                end
            end, 2)
        end
    end, 2)

    local guid = object.getGUID()
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "battlefield")
    if row == "land" and event.cardInstanceId ~= nil and BridgeState.landInsertionOrderByInstanceId[event.cardInstanceId] == nil then
        BridgeState.nextLandInsertionOrder = (BridgeState.nextLandInsertionOrder or 0) + 1
        BridgeState.landInsertionOrderByInstanceId[event.cardInstanceId] = BridgeState.nextLandInsertionOrder
    end
    local rowKey = event.seatId .. ":" .. row
    if countAsNewPlacement ~= false then
        BridgeState.battlefieldCounts[rowKey] = (BridgeState.battlefieldCounts[rowKey] or 0) + 1
    end
    if row == "land" and BridgeLandPlacementMode() == "STRICT" then BridgeRelayoutStrictLandRow(event.seatId) end
    return true, nil
end

function BridgeLandPlacementMode()
    local mode = string.upper(tostring(BridgeState.landPlacementMode or BRIDGE_LAND_PLACEMENT_MODE or "FREEFORM"))
    return mode == "STRICT" and "STRICT" or "FREEFORM"
end

function BridgeSetLandPlacementMode(mode)
    local normalized = string.upper(tostring(mode or "FREEFORM"))
    if normalized ~= "STRICT" and normalized ~= "FREEFORM" then
        BridgeShowError("unknown land placement mode " .. tostring(mode))
        return false
    end
    BridgeState.landPlacementMode = normalized
    BRIDGE_LAND_PLACEMENT_MODE = normalized
    if normalized == "STRICT" then
        for seatId, _ in pairs(BRIDGE_SEATS) do BridgeRelayoutStrictLandRow(seatId) end
    end
    BridgeLog("[Bridge] land placement mode=" .. normalized)
    return true
end

function BridgeRelayoutStrictLandRow(seatId)
    if BridgeLandPlacementMode() ~= "STRICT" then return end
    local seat = BRIDGE_SEATS[seatId]
    local anchor = seat and seat.battlefieldAnchors and seat.battlefieldAnchors.land
    if anchor == nil then return end
    local lands = {}
    for instanceId, order in pairs(BridgeState.landInsertionOrderByInstanceId or {}) do
        local guid = BridgeState.physicalByInstanceId[instanceId]
        local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
        if object ~= nil and BridgeState.physicalSeatByGuid[guid] == seatId
            and BridgeState.physicalZoneByGuid[guid] == "battlefield" then
            table.insert(lands, {instanceId = instanceId, order = order, object = object})
        end
    end
    table.sort(lands, function(left, right) return left.order < right.order end)
    local x = anchor.x
    for index, land in ipairs(lands) do
        local bounds = nil
        pcall(function() bounds = land.object.getBoundsNormalized() end)
        local width = bounds and bounds.size and tonumber(bounds.size.x) or 2.8
        local position = {x = x + width / 2, y = anchor.y, z = anchor.z}
        BridgeSafeObjectCall(land.object, function(card)
            BridgeCaptureCanonicalCardScale(card)
            card.setPositionSmooth(position, false, true)
            BridgeRestoreCanonicalCardScale(card)
        end)
        x = position.x + width / 2 + 0.35
    end
end

function BridgeBattlefieldPosition(seatId, row)
    local seat = BRIDGE_SEATS[seatId]
    local anchor = seat and seat.battlefieldAnchors and seat.battlefieldAnchors[row]
    if anchor == nil then
        return nil, "no battlefield anchor configured for seat " .. tostring(seatId) .. " row " .. tostring(row)
    end

    local rowKey = seatId .. ":" .. row
    local count = BridgeState.battlefieldCounts[rowKey] or 0
    for offset = 0, 11 do
        local slot = count + offset
        local candidate = {
            -- A tapped card is roughly as wide as an upright card is tall.
            -- Four wider slots preserve a grab/tap gap instead of overlapping
            -- adjacent creatures in the old six-card row.
            x = anchor.x + (slot % 4) * 3.4,
            y = anchor.y,
            z = anchor.z + math.floor(slot / 4) * seat.tableSideZ * 4.0
        }
        if not BridgeBattlefieldPositionOccupied(candidate) then
            BridgeState.battlefieldCounts[rowKey] = slot
            return candidate, nil
        end
    end
    return nil, "no unoccupied battlefield slot for seat " .. tostring(seatId) .. " row " .. tostring(row)
end

function BridgeBattlefieldPositionOccupied(candidate)
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Card" or object.tag == "Deck" then
            local position = object.getPosition()
            local dx = position.x - candidate.x
            local dz = position.z - candidate.z
            if dx * dx + dz * dz < 3.0 then return true end
        end
    end
    return false
end

function BridgeUnitTowardTableCenter(position)
    local length = math.sqrt(position.x * position.x + position.z * position.z)
    if length < 0.01 then
        return {x = 0, z = 1}
    end
    return {x = -position.x / length, z = -position.z / length}
end

function BridgeMoveToAttackLane(seatId, object)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local guid = object.getGUID()
    local position = object.getPosition()
    if BridgeState.attackOriginByGuid[guid] == nil then
        BridgeState.attackOriginByGuid[guid] = {x = position.x, y = position.y, z = position.z}
    end
    BridgeState.attackLaneGuidBySeatId[seatId] = BridgeState.attackLaneGuidBySeatId[seatId] or {}
    BridgeState.attackLaneGuidBySeatId[seatId][guid] = true
    -- Parallel translation preserves the battlefield's lateral X separation.
    object.setPositionSmooth({x = position.x, y = math.max(position.y, 2.0), z = seat.attackLaneZ}, false, true)
end

function BridgeCombatLaneXAvailable(laneZ, candidateX, ignoredGuid)
    for _, other in ipairs(getAllObjects()) do
        if other.tag == "Card" then
            local guid = BridgeSafeObjectGuid(other)
            if guid ~= nil and guid ~= ignoredGuid then
                local position = other.getPosition()
                local dx = position.x - candidateX
                local dz = position.z - laneZ
                if dx * dx < 2.8 * 2.8 and dz * dz < 1.0 * 1.0 then
                    return false
                end
            end
        end
    end
    return true
end

function BridgeFindCombatLaneX(object, laneZ)
    local position = object.getPosition()
    local guid = BridgeSafeObjectGuid(object)
    local candidates = {position.x}
    for distance = 3.4, 20.4, 3.4 do
        table.insert(candidates, position.x + distance)
        table.insert(candidates, position.x - distance)
    end
    for _, candidateX in ipairs(candidates) do
        if BridgeCombatLaneXAvailable(laneZ, candidateX, guid) then return candidateX end
    end
    return position.x
end

function BridgeMoveToBlockerLane(seatId, object)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local guid = object.getGUID()
    local position = object.getPosition()
    if BridgeState.attackOriginByGuid[guid] == nil then
        BridgeState.attackOriginByGuid[guid] = {x = position.x, y = position.y, z = position.z}
    end
    local laneX = BridgeFindCombatLaneX(object, seat.blockerLaneZ)
    object.setPositionSmooth({x = laneX, y = math.max(position.y, 2.0), z = seat.blockerLaneZ}, false, true)
end

function BridgeGraveyardPosition(seatId)
    local seat = BRIDGE_SEATS[seatId]
    local anchor = BridgeResolveSeatZoneAnchor(seatId, "graveyard")
    if anchor == nil then return nil end

    -- Visually pile the graveyard in one place, but retain each card object
    -- and its exact Forge-instance mapping rather than letting TTS merge the
    -- pile into a Deck.
    local count = BridgeState.graveyardCounts[seatId] or 0
    BridgeState.graveyardCounts[seatId] = count + 1
    return {
        x = anchor.x,
        y = anchor.y + 0.08 + count * 0.12,
        z = anchor.z
    }
end

function BridgeReturnCombatPreviewCard(seatId, object)
    if object == nil then return end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    local origin = BridgeState.attackOriginByGuid[guid]
    if origin ~= nil and BridgeState.physicalZoneByGuid[guid] == "battlefield" then
        object.setPositionSmooth(origin, false, true)
    end
    BridgeState.attackOriginByGuid[guid] = nil
    if BridgeState.attackLaneGuidBySeatId[seatId] ~= nil then
        BridgeState.attackLaneGuidBySeatId[seatId][guid] = nil
    end
    BridgeState.combatSelectedByGuid[guid] = nil
end

function BridgeReturnAttackPresentation(seatId)
    for guid, origin in pairs(BridgeState.attackOriginByGuid or {}) do
        local objectSeat = BridgeState.physicalSeatByGuid[guid]
        if seatId == nil or seatId == objectSeat then
            local object = getObjectFromGUID(guid)
            if object ~= nil and BridgeState.physicalZoneByGuid[guid] == "battlefield" then
                object.setPositionSmooth(origin, false, true)
            end
            BridgeState.attackOriginByGuid[guid] = nil
            if BridgeState.attackLaneGuidBySeatId[objectSeat] ~= nil then
                BridgeState.attackLaneGuidBySeatId[objectSeat][guid] = nil
            end
            BridgeState.combatSelectedByGuid[guid] = nil
        end
    end
    for guid, _ in pairs(BridgeState.combatSelectedByGuid or {}) do
        if seatId == nil or BridgeState.physicalSeatByGuid[guid] == seatId then
            BridgeState.combatSelectedByGuid[guid] = nil
        end
    end
end

function BridgeStopOnDesync(message)
    local diagnostic = tostring(message or "")
    if BridgeState.resyncInFlight == true then
        BridgeState.desyncFailureCount = (BridgeState.desyncFailureCount or 0) + 1
        BridgeState.desyncLastMessage = diagnostic
        BridgeLog("[Bridge] suppressed desync during authoritative resync: " .. diagnostic)
        return
    end
    if BridgeState.desyncLatched == true then
        BridgeState.desyncFailureCount = (BridgeState.desyncFailureCount or 0) + 1
        BridgeState.desyncLastMessage = diagnostic
        BridgeStopEventPolling("desync-latched")
        BridgeEnsureDesyncRecovery("duplicate-desync")
        BridgeLog("[Bridge] duplicate synchronization failure suppressed: " .. diagnostic)
        return
    end
    BridgeState.desyncLatched = true
    BridgeState.desyncFailureCount = (BridgeState.desyncFailureCount or 0) + 1
    BridgeState.desyncLastMessage = diagnostic
    BridgeStopEventPolling("desync-latched")
    BridgeStopDecisionPolling()
    BridgeState.animationRunning = false
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    if string.sub(diagnostic, 1, 16) == "LIBRARY MISMATCH" then
        -- Bootstrap mismatch has already emitted its complete, read-only
        -- inventory to the scripting log.  Keep the table-facing signal to
        -- one concise status diagnostic rather than broadcasting retries.
        BridgeLog("[Bridge] synchronization stopped: " .. diagnostic)
        BridgeSetStatus("LIBRARY MISMATCH", diagnostic)
        BridgeEnsureDesyncRecovery("library-mismatch")
        return
    end
    BridgeShowError("synchronization stopped: " .. diagnostic)
    BridgeEnsureDesyncRecovery("desync")
end

function BridgeEnforceDesyncRecovery(reason)
    if BridgeState.desyncLatched == true
        and not BridgeState.resyncInFlight
        and not BridgeState.resyncScheduled
        and not BridgeState.recoveryCheckpointCommitInProgress then
        BridgeEnsureDesyncRecovery(reason or "liveness-watchdog")
    end
end

function BridgeEnsureDesyncRecovery(reason)
    if BridgeState.desyncLatched ~= true or BridgeState.resyncInFlight == true then return end
    if BridgeState.resyncScheduled == true then return end
    if BridgeState.eventSessionId == nil then
        BridgeState.desyncLatched = false
        BridgeLog("[Bridge] cleared desync latch: no active session reason=" .. tostring(reason))
        return
    end
    BridgeState.resyncScheduled = true
    BridgeLog("[Bridge] RESYNC_SCHEDULED reason=" .. tostring(reason))
    BridgeWaitFrames(function()
        if BridgeState.resyncScheduled ~= true then return end
        if BridgeState.desyncLatched ~= true or BridgeState.resyncInFlight == true then
            BridgeState.resyncScheduled = false
            return
        end
        BridgeResyncFromAuthoritativeSnapshot("automatic-desync-recovery")
    end, 1)
end

function BridgePrintEventSyncStatus()
    BridgeLog(string.format(
        "[Bridge] event sync session=%s polling=%s received=%s applied=%s queued=%d retries=%d inFlight=%s",
        tostring(BridgeState.eventSessionId), tostring(BridgeState.eventPolling),
        tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence),
        #BridgeState.eventQueue, BridgeState.eventRetryCount, tostring(BridgeState.eventRequestInFlight)))
end

function BridgeDumpSyncState()
    BridgePrintEventSyncStatus()
    BridgeLogPresentationMetrics("sync-dump")
    BridgeLog("[Bridge] pendingIntent=" .. JSON.encode(BridgeState.pendingIntent or {}))
    BridgeLog("[Bridge] yieldPolicyActiveSeatId=" .. tostring(BridgeState.yieldPolicyActiveSeatId))
    BridgeLog("[Bridge] pendingQueue=" .. JSON.encode(BridgeState.eventQueue))
    BridgeLog("[Bridge] physicalByInstanceId=" .. JSON.encode(BridgeState.physicalByInstanceId))
    BridgeLog("[Bridge] physicalSeatByGuid=" .. JSON.encode(BridgeState.physicalSeatByGuid))
    BridgeLog("[Bridge] physicalZoneByGuid=" .. JSON.encode(BridgeState.physicalZoneByGuid))
end

-- ============================================================
-- F2D GAME HUD / DEV PRESENTATION OVERRIDES
--
-- This block intentionally sits at the end of Global.lua so the HUD polish
-- remains easy to remove or split into a generated module later.  It only
-- overrides presentation helpers; Forge remains authoritative for game state.
-- ============================================================

BRIDGE_DEV_UI_ENABLED = true
BRIDGE_DEV_ANNOTATIONS_ENABLED = true
BRIDGE_PHYSICAL_PRIORITY_CONTROLS_ENABLED = true
BRIDGE_SCRIPT_REVISION = "2026-08-30-u2-gameplay-repair"

BRIDGE_HUD_COLORS = {
    active = "#6DB5FF",
    inactive = "#718096",
    success = "#7BD88F",
    warning = "#F4C76B",
    danger = "#F27D7D"
}

function BridgeHudToggleDev(player, value, id)
    if BRIDGE_DEV_UI_ENABLED ~= true or BridgeState.ui == nil then return end
    BridgeState.ui.diagnosticsVisible = not (BridgeState.ui.diagnosticsVisible == true)
    BridgeUiMarkDirty("dev-drawer-toggle")
end

BRIDGE_REPORT_CATEGORIES = {
    "Gameplay sync", "Combat", "Card movement", "Presentation/UI", "Decision/prompt",
    "Mana/payment", "Performance / Freeze", "Crash/error", "Other"
}

function BridgeHudReportOpen(player, value, id)
    if BRIDGE_DEV_UI_ENABLED ~= true or BridgeState.ui == nil then return end
    BridgeState.ui.reportPanelVisible = true
    BridgeState.ui.reportStatus = "Ready to capture local diagnostic ZIP."
    BridgeUiMarkDirty("report-open")
end

function BridgeHudReportCancel(player, value, id)
    if BridgeState.ui == nil or BridgeState.ui.reportCaptureInFlight then return end
    BridgeState.ui.reportPanelVisible = false
    BridgeState.ui.reportStatus = ""
    BridgeUiMarkDirty("report-cancel")
end

function BridgeHudReportCategoryChanged(player, value, id)
    if BridgeState.ui == nil or BridgeState.ui.reportCaptureInFlight then return end
    for index, category in ipairs(BRIDGE_REPORT_CATEGORIES) do
        if value == category then
            BridgeState.ui.reportCategoryIndex = index
            BridgeUiMarkDirty("report-category-dropdown")
            return
        end
    end
end

function BridgeHudReportCategoryPrevious(player, value, id)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    local count = #BRIDGE_REPORT_CATEGORIES
    if count == 0 then return end
    local index = (tonumber(ui.reportCategoryIndex or 1) or 1) - 1
    if index < 1 then index = count end
    ui.reportCategoryIndex = index
    BridgeUiMarkDirty("report-category-previous")
end

function BridgeHudReportCategory(player, value, id)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    local count = #BRIDGE_REPORT_CATEGORIES
    if count == 0 then return end
    local index = (tonumber(ui.reportCategoryIndex or 1) or 1) + 1
    if index > count then index = 1 end
    ui.reportCategoryIndex = index
    BridgeUiMarkDirty("report-category-next")
end

function BridgeHudReportMappedCardInstanceIds()
    local ids = {}
    for cardInstanceId, _ in pairs(BridgeState.physicalByInstanceId or {}) do
        table.insert(ids, cardInstanceId)
    end
    table.sort(ids)
    return ids
end

function BridgeHudReportPhysicalMappings()
    local mappings = {}
    local seenGuids = {}
    for cardInstanceId, guid in pairs(BridgeState.physicalByInstanceId or {}) do
        local object = BridgeGetLiveObjectByGuid(guid)
        table.insert(mappings, {
            cardInstanceId = cardInstanceId,
            guid = guid,
            zone = BridgeState.physicalZoneByGuid[guid],
            isLive = object ~= nil,
            advertisedCardInstanceId = BridgeReadPhysicalIdentity(object)
        })
        seenGuids[guid] = true
    end
    -- A mapped table entry cannot reveal an extra physical duplicate.  Only
    -- inspect cards that explicitly advertise a Bridge identity; foreign or
    -- importer-owned cards remain outside Forge mapping ownership.
    if type(getAllObjects) == "function" then
        for _, object in ipairs(getAllObjects() or {}) do
            if object ~= nil and object.tag == "Card" then
                local guid = BridgeSafeObjectGuid(object)
                local advertised = BridgeReadPhysicalIdentity(object)
                if guid ~= nil and advertised ~= nil and not seenGuids[guid] then
                    table.insert(mappings, {
                        cardInstanceId = advertised,
                        guid = guid,
                        zone = nil,
                        isLive = true,
                        advertisedCardInstanceId = advertised
                    })
                    seenGuids[guid] = true
                end
            end
        end
    end
    table.sort(mappings, function(left, right)
        return tostring(left.cardInstanceId) < tostring(right.cardInstanceId)
    end)
    return mappings
end

function BridgeHudReportSummaryText()
    local ok, value = pcall(function() return UI.getAttribute("BridgeHudReportSummary", "text") end)
    if not ok or value == nil then return nil end
    value = tostring(value)
    return value ~= "" and value or nil
end

function BridgeScheduleDiagnosticCaptureFollowup(token, sessionId, epoch)
    if token == nil or BridgeState.diagnosticCaptureFollowupToken == token then return end
    BridgeState.diagnosticCaptureFollowupToken = token
    BridgeState.diagnosticCaptureFollowupUntil = os.clock() + BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_SECONDS
    local function sample()
        if not BridgeRuntimeIsCurrent(epoch)
            or BridgeState.eventSessionId ~= sessionId
            or BridgeState.diagnosticCaptureFollowupToken ~= token then
            return
        end
        if os.clock() > BridgeState.diagnosticCaptureFollowupUntil then return end
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_POSTCHECK", token, "post-capture")
        BridgeWaitTime(sample, BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_INTERVAL_SECONDS)
    end
    BridgeWaitTime(sample, BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_INTERVAL_SECONDS)
end

function BridgeDiagnosticCaptureGameplayFingerprint()
    local decision = BridgeState.lastDecision
    local pending = BridgeState.pendingDecision
    local ui = BridgeState.ui or {}
    local function value(v) return tostring(v == nil and "<nil>" or v) end
    return table.concat({
        value(BridgeState.eventSessionId), value(decision and decision.decisionId),
        value(pending and pending.decisionId), value(BridgeState.currentPhase),
        value(BridgeState.currentTurnSeatId), value(BridgeState.prioritySeatId),
        value(BridgeState.lastReceivedEventSequence), value(BridgeState.lastAppliedEventSequence),
        value(BridgeState.lastConsumedEventSequence), value(BridgeState.lastStateProjectedEventSequence),
        value(BridgeState.lastPhysicalPresentationEventSequence), value(#(BridgeState.eventQueue or {})),
        value(BridgeState.eventPollGeneration), value(BridgeState.eventSessionGeneration),
        value(BridgeState.eventPolling), value(BridgeState.eventRequestInFlight),
        value(BridgeState.eventPollScheduled), value(BridgeState.decisionPollGeneration),
        value(BridgeState.decisionPollInFlight), value(BridgeState.decisionPollScheduled),
        value(BridgeState.decisionPresentationGeneration), value(BridgeState.submitting),
        value(BridgeState.choiceProtocolPaused), value(BridgeState.animationRunning),
        value(BridgeState.yieldPolicyTurnNumber), value(BridgeState.yieldPolicyActiveSeatId),
        value(BridgeState.yieldPolicySessionId), value(BridgeState.resyncInFlight),
        value(BridgeState.resyncScheduled), value(BridgeState.desyncLatched),
        value(ui.autoAdvanceMode), value(ui.autoPassEmpty), value(ui.fastForwardActive)
    }, "|")
end

function BridgeCheckDiagnosticCapturePurity(before, token, stage)
    local after = BridgeDiagnosticCaptureGameplayFingerprint()
    if before ~= after then
        BridgeLog(string.format("[Bridge] DIAG_CAPTURE_PURITY_VIOLATION token=%s stage=%s before=%s after=%s",
            tostring(token), tostring(stage), tostring(before), tostring(after)))
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_PURITY_VIOLATION", token, stage)
        return false
    end
    return true
end

function BridgeRecoverGameplayPumps(reason, expectedSessionId, expectedEpoch, captureToken)
    local sessionId = expectedSessionId or BridgeState.eventSessionId
    local epoch = expectedEpoch or BRIDGE_RUNTIME_EPOCH_LOCAL
    local isCaptureRecovery = captureToken ~= nil
    local recoveryEnded = false
    local function endRecovery(detail)
        if recoveryEnded then return end
        recoveryEnded = true
        if isCaptureRecovery then
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_RECOVERY_END", captureToken, detail or reason)
            BridgeScheduleDiagnosticCaptureFollowup(captureToken, sessionId, epoch)
        else
            BridgeLog("[Bridge] gameplay pump recovery complete reason=" .. tostring(detail or reason))
        end
    end
    if isCaptureRecovery then
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_RECOVERY_BEGIN", captureToken, reason)
    end
    if not BridgeRuntimeIsCurrent(epoch)
        or BridgeState.eventSessionId ~= sessionId
        or sessionId == nil
        or BridgeState.desyncLatched then
        endRecovery("recovery-fence-not-current")
        return false
    end

    -- The event poll generation belongs to HTTP callback freshness. These
    -- checks deliberately inspect the request/schedule state too; `true`
    -- alone is not evidence that an event pump is alive.
    if BridgeState.eventPolling ~= true then
        BridgeStartEventPolling(sessionId, false)
    elseif not BridgeState.eventRequestInFlight and not BridgeState.eventPollScheduled then
        BridgePollEvents(BridgeState.eventPollGeneration)
    end

    if BridgeState.lastDecision == nil then
        if BridgeState.gameEnded == nil and not BridgeState.submitting
            and not BridgeState.decisionPollInFlight
            and not BridgeState.decisionPollScheduled
            and not BridgeState.choiceProtocolPaused then
            BridgeStartDecisionPolling()
        end
        endRecovery("no-current-decision")
        return true
    end

    -- A non-nil decision can still have lost its render/control path. Ask
    -- Forge for the current decision once, then use the existing acceptance
    -- path. Same-id responses are rendered again without creating a choice.
    if BridgeState.decisionRefreshInFlight then
        endRecovery("decision-refresh-already-in-flight")
        return true
    end
    local expectedPresentationGeneration = BridgeState.decisionPresentationGeneration
    local priorDecision = BridgeState.lastDecision
    local priorDecisionId = priorDecision.decisionId
    BridgeState.decisionRefreshInFlight = true
    BridgeGetDecision(function(ok, body, err)
        if (expectedSessionId ~= nil and expectedSessionId ~= BridgeState.eventSessionId)
            or not BridgeRuntimeIsCurrent(epoch)
            or expectedPresentationGeneration ~= BridgeState.decisionPresentationGeneration then
            BridgeState.decisionRefreshInFlight = false
            if isCaptureRecovery then
                BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_DECISION_REFRESH_CALLBACK", captureToken, "stale")
            end
            return
        end
        BridgeState.decisionRefreshInFlight = false
        if ok and body ~= nil then
            local sameDecision = body.decisionId == priorDecisionId
            local transactionExists = BridgeState.choiceTransactions[priorDecisionId] ~= nil
            if sameDecision and transactionExists then
                -- A submitted/active transaction is presentation-live only
                -- through its existing response path. Do not re-accept it and
                -- risk clearing the transaction during diagnostic recovery.
                BridgeLog("[Bridge] diagnostic decision refresh preserved active choice transaction decision=" .. tostring(priorDecisionId))
            else
                BridgeAcceptDecision(body, "diagnostic_capture_recovery", sessionId, expectedPresentationGeneration)
            end
            if isCaptureRecovery then
                BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_DECISION_REFRESH_CALLBACK", captureToken, sameDecision and "same-decision" or "new-decision")
            end
            endRecovery(sameDecision and "same-decision-represented" or "new-decision-accepted")
            return
        end
        local responseCode = nil
        if body ~= nil and body.errorCode ~= nil then responseCode = tostring(body.errorCode) end
        if responseCode == "no_pending_decision" then
            -- Keep the existing presentation intact while Forge is between
            -- decisions. The ordinary poller is allowed to observe through
            -- that presentation and will replace it only with an
            -- authoritative response.
            BridgeStartDecisionPolling(true)
        end
        BridgeLog("[Bridge] diagnostic decision refresh failed: " .. tostring(err or responseCode or "unknown"))
        if isCaptureRecovery then
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_DECISION_REFRESH_CALLBACK", captureToken, responseCode or "failed")
        end
        endRecovery("decision-refresh-failed")
    end)
    return true
end

function BridgeHudRecoverPumps(player, value, id)
    if BRIDGE_DEV_UI_ENABLED ~= true or BridgeState.ui == nil then return end
    if BridgeState.eventSessionId == nil then
        BridgeState.ui.reportStatus = "No active Forge session to recover."
        BridgeUiMarkDirty("manual-pump-recovery-unavailable")
        return
    end
    BridgeState.ui.reportStatus = "Recovering gameplay observation..."
    BridgeUiMarkDirty("manual-pump-recovery-start")
    BridgeRecoverGameplayPumps("manual-control", BridgeState.eventSessionId, BRIDGE_RUNTIME_EPOCH_LOCAL, nil)
end

function BridgeHudSubmitReport(category, summary)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    local requestUi = ui
    local requestEpoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    local requestSession = BridgeState.eventSessionId
    requestUi.reportCaptureToken = (tonumber(requestUi.reportCaptureToken or 0) or 0) + 1
    local captureToken = requestUi.reportCaptureToken
    local completed = false

    BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_REQUESTED", captureToken, "user-request")
    BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_BEGIN", captureToken, "capture-start")
    local capturePurityBefore = BridgeDiagnosticCaptureGameplayFingerprint()

    ui.reportCaptureInFlight = true
    ui.reportStatus = "Capturing..."
    BridgeUiMarkDirty("report-capture-start")

    local function finish(ok, body, err, recoveryReason, lifecycleStage)
        BridgeRecordDiagnosticCaptureLifecycle(lifecycleStage or "DIAG_CAPTURE_CALLBACK", captureToken, recoveryReason or "callback")
        if completed then return end
        if requestUi.reportCaptureToken ~= captureToken then return end
        completed = true
        if not BridgeRuntimeIsCurrent(requestEpoch)
            or BridgeState.ui ~= requestUi
            or BridgeState.eventSessionId ~= requestSession then
            BridgeLog("[Bridge] diagnostic capture completion ignored by runtime/session fence")
            return
        end
        requestUi.reportCaptureInFlight = false
        if ok and body ~= nil and body.success == true then
            local reportId = tostring(body.reportId or "unknown")
            local reportPath = tostring(body.reportPath or "BugReports")
            requestUi.reportStatus = "CAPTURED â€¢ " .. reportId .. "\n" .. reportPath
            BridgeLog("[Bridge] diagnostic report captured id=" .. reportId .. " path=" .. reportPath)
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_COMPLETED", captureToken, "response-success")
        else
            local detail = BridgeHttpFailureDetail(body, err or "capture failed")
            requestUi.reportStatus = "ERROR â€¢ " .. detail
            BridgeLog("[Bridge] diagnostic report failed: " .. detail)
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_FAILED", captureToken, detail)
        end
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_CLEANUP_COMPLETED", captureToken, "capture-state-released")
        BridgeUiMarkDirty("report-capture-result")
        -- A report is an observer. Completion must not restart pollers,
        -- refresh a decision, or rebuild presentation; normal liveness and
        -- recovery watchdogs own those mutations.
        BridgeCheckDiagnosticCapturePurity(capturePurityBefore, captureToken, "completion")
    end

    -- Arm the watchdog before collecting any diagnostic payload.  Payload
    -- collection runs inside TTS and may encounter a transient/invalid object;
    -- an exception there must not strand reportCaptureInFlight forever.
    BridgeWaitTime(function()
        if requestUi.reportCaptureToken == captureToken and requestUi.reportCaptureInFlight then
            finish(false, nil, "diagnostic capture timed out after " .. tostring(BRIDGE_REPORT_CAPTURE_TIMEOUT_SECONDS) .. " seconds", "watchdog", "DIAG_CAPTURE_TIMEOUT")
        end
    end, BRIDGE_REPORT_CAPTURE_TIMEOUT_SECONDS)

    local performanceOk, performance = pcall(BridgePerformanceDiagnosticPayload)
    if not performanceOk or performance == nil then
        finish(false, nil, "diagnostic payload failed: " .. tostring(performance), "payload-failure")
        return
    end
    BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_SNAPSHOT_COPIED", captureToken, "immutable-payload-copied")
    local request = {
        summary = summary or BridgeHudReportSummaryText(),
        category = category or BRIDGE_REPORT_CATEGORIES[tonumber(ui.reportCategoryIndex or 1) or 1] or "Other",
        sessionId = BridgeState.eventSessionId,
        decisionId = BridgeState.lastDecision and BridgeState.lastDecision.decisionId or nil,
        clientRuntimeId = BRIDGE_CLIENT_RUNTIME_ID,
        clientRevision = BRIDGE_SCRIPT_REVISION,
        lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
        turn = BridgeState.tableTurnCount,
        phase = BridgeState.currentPhase,
        activePlayer = BridgeState.currentTurnSeatId,
        priorityPlayer = BridgeState.prioritySeatId,
        mappedCardInstanceIds = BridgeHudReportMappedCardInstanceIds(),
        physicalMappings = BridgeHudReportPhysicalMappings(),
        status = BridgeState.statusHeadline,
        performanceSummary = performance.performanceSummary,
        recentTtsTrace = performance.recentTtsTrace,
        diagnosticCaptureLifecycle = performance.diagnosticCaptureLifecycle,
        eventDrainDiagnostics = performance.eventDrainDiagnostics
    }
    local requestOk, requestError = pcall(function()
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_HANDED_OFF", captureToken, "bridge-request")
        BridgeHttp.requestJson("POST", "/api/v1/diagnostics/report", request, function(ok, body, err)
            finish(ok, body, err, "callback", "DIAG_CAPTURE_CALLBACK")
            return
        --[[ legacy inline completion retained only as a source-compatible
             comment while all completion is routed through finish above.
        ui.reportCaptureInFlight = false
        if ok and body ~= nil and body.success == true then
            local reportId = tostring(body.reportId or "unknown")
            local reportPath = tostring(body.reportPath or "BugReports")
            ui.reportStatus = "CAPTURED • " .. reportId .. "\n" .. reportPath
            BridgeLog("[Bridge] diagnostic report captured id=" .. reportId .. " path=" .. reportPath)
        else
            local detail = BridgeHttpFailureDetail(body, err or "capture failed")
            ui.reportStatus = "ERROR • " .. detail
            BridgeLog("[Bridge] diagnostic report failed: " .. detail)
        end
        BridgeUiMarkDirty("report-capture-result") ]]
        end)
    end)
    if not requestOk then
        finish(false, nil, "diagnostic request failed: " .. tostring(requestError), "request-error")
    end
end

function BridgeHudReportCapture(player, value, id)
    BridgeHudSubmitReport(nil, nil)
end

function BridgeHudRollingCapture(player, value, id)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    -- This button is intentionally visible outside the developer drawer so a
    -- recovered freeze can be captured without first navigating another UI.
    -- Open the drawer after the one-click request so the result path/status is
    -- still visible to the host.
    ui.diagnosticsVisible = true
    ui.reportPanelVisible = true
    BridgeHudSubmitReport("Performance / Freeze", "Rolling freeze capture")
end

function BridgeHudResyncFromForge(player, value, id)
    local ui = BridgeState.ui
    if ui == nil then
        BridgeLog("[Bridge] RESYNC_CLICK ignored reason=ui-unavailable")
        return
    end
    local queueState = BridgeEventDrainQueueState()
    BridgeLog(string.format(
        "[Bridge] RESYNC_CLICK session=%s resyncInFlight=%s physicalQueuesIdle=%s eventQueueHead=%s eventQueueLength=%s desyncLatched=%s bootstrapping=%s runtimeEpoch=%s",
        tostring(BridgeState.eventSessionId), tostring(ui.resyncInFlight),
        tostring(queueState.physicalLibraryQueuesIdle), tostring(queueState.headSequence),
        tostring(queueState.queueLength), tostring(queueState.desyncLatched),
        tostring(queueState.bootstrapping), tostring(BRIDGE_RUNTIME_EPOCH_LOCAL)))
    if ui.resyncInFlight == true then
        BridgeLog("[Bridge] RESYNC_DEFERRED reason=ui-latched")
        return
    end
    local started = BridgeResyncFromAuthoritativeSnapshot("hud")
    if started ~= true then
        BridgeLog("[Bridge] RESYNC_DEFERRED reason=local-recovery-path")
    end
end

function BridgeHudPhaseElementId(phase)
    local value = string.upper(tostring(phase or ""))
    if string.find(value, "UNTAP", 1, true) then return "BridgePhaseUntap" end
    if string.find(value, "UPKEEP", 1, true) then return "BridgePhaseUpkeep" end
    if string.find(value, "DRAW", 1, true) then return "BridgePhaseDraw" end
    if string.find(value, "MAIN", 1, true) then
        if string.find(value, "POSTCOMBAT", 1, true)
            or string.find(value, "MAIN 2", 1, true)
            or string.find(value, "SECOND", 1, true) then
            return "BridgePhaseMain2"
        end
        if string.find(value, "PRECOMBAT", 1, true)
            or string.find(value, "MAIN 1", 1, true)
            or string.find(value, "FIRST", 1, true) then
            return "BridgePhaseMain1"
        end
        return "BridgePhaseMain1"
    end
    if string.find(value, "COMBAT", 1, true)
        or string.find(value, "ATTACK", 1, true)
        or string.find(value, "BLOCK", 1, true)
        or string.find(value, "DAMAGE", 1, true) then
        return "BridgePhaseCombat"
    end
    if string.find(value, "END", 1, true) or string.find(value, "CLEANUP", 1, true) then
        return "BridgePhaseEnd"
    end
    return nil
end

function BridgeHudRefreshPhaseRibbon()
    local phaseIds = {
        "BridgePhaseUntap",
        "BridgePhaseUpkeep",
        "BridgePhaseDraw",
        "BridgePhaseMain1",
        "BridgePhaseCombat",
        "BridgePhaseMain2",
        "BridgePhaseEnd"
    }
    local activeId = BridgeHudPhaseElementId(BridgeState.currentPhase)
    for _, phaseId in ipairs(phaseIds) do
        BridgeUiSet(
            phaseId,
            "color",
            phaseId == activeId and BRIDGE_HUD_COLORS.active or BRIDGE_HUD_COLORS.inactive
        )
    end
end

-- Phase presentation is derived from the authoritative Forge phase field.
-- The HUD never advances phases; this color is only a readable cue that the
-- state machine has already moved to a new phase.
function BridgeHudPhaseColor(phase)
    local value = string.upper(tostring(phase or ""))
    if string.find(value, "UNTAP", 1, true) then return "#94A3B8" end
    if string.find(value, "UPKEEP", 1, true) then return "#F59E0B" end
    if string.find(value, "DRAW", 1, true) then return "#22C55E" end
    if string.find(value, "MAIN", 1, true) then return "#38BDF8" end
    if string.find(value, "COMBAT", 1, true)
        or string.find(value, "ATTACK", 1, true)
        or string.find(value, "BLOCK", 1, true)
        or string.find(value, "DAMAGE", 1, true) then return "#F97316" end
    if string.find(value, "END", 1, true) or string.find(value, "CLEANUP", 1, true) then return "#A78BFA" end
    return "#F8FAFC"
end

function BridgeHudConnectionPresentation()
    local headline = string.upper(tostring(BridgeState.statusHeadline or ""))
    if BridgeState.choiceProtocolPaused == true then
        return "● PAUSED", BRIDGE_HUD_COLORS.danger
    end
    if string.find(headline, "OFFLINE", 1, true) then
        return "● OFFLINE", BRIDGE_HUD_COLORS.danger
    end
    if BridgeState.eventSessionId ~= nil then
        return "● MATCH", BRIDGE_HUD_COLORS.success
    end
    if string.find(headline, "ERROR", 1, true) then
        return "● ERROR", BRIDGE_HUD_COLORS.danger
    end
    return "○ SETUP", BRIDGE_HUD_COLORS.warning
end

-- Preserve the existing HUD renderer and layer game-HUD presentation over it.
-- Existing IDs, action rows, exact Forge choices, FAST/MANA/LOG behavior, and
-- footer semantics remain owned by the original renderer above.
local BridgeUiFlushBase = BridgeUiFlush
function BridgeUiFlush()
    BridgeUiFlushBase()
    local ui = BridgeState.ui
    if ui == nil or not ui.mounted then return end

    local devEnabled = BRIDGE_DEV_UI_ENABLED == true
    local devExpanded = devEnabled and ui.diagnosticsVisible == true
    BridgeUiSet("BridgeHudDevToggle", "active", devEnabled and "true" or "false")
    BridgeUiSet("BridgeHudDevRoot", "active", devExpanded and "true" or "false")
    local yieldUi = ui.fastForwardActive and "FAST-FORWARD" or (ui.autoPassEmpty and "AUTO-PASS: ON" or "AUTO-PASS: OFF")
    BridgeUiSet("BridgeHudMode", "text", yieldUi)
    BridgeUiSet("BridgeHudFastForward", "text", ui.fastForwardActive and "CANCEL FAST-FORWARD" or "FAST-FORWARD")
    local stops = ui.fastForwardStops or {own_turn = {}, other_turn = {}}
    local stopButtons = {
        BridgeHudStopOwn_Upkeep = {"own_turn", "upkeep"}, BridgeHudStopOwn_Draw = {"own_turn", "draw"},
        BridgeHudStopOwn_MainPre = {"own_turn", "main_precombat"}, BridgeHudStopOwn_BeginningCombat = {"own_turn", "beginning_combat"},
        BridgeHudStopOwn_Attackers = {"own_turn", "declare_attackers"}, BridgeHudStopOwn_Blockers = {"own_turn", "declare_blockers"},
        BridgeHudStopOwn_Damage = {"own_turn", "combat_damage"}, BridgeHudStopOwn_EndCombat = {"own_turn", "end_combat"},
        BridgeHudStopOwn_MainPost = {"own_turn", "main_postcombat"}, BridgeHudStopOwn_EndStep = {"own_turn", "end_step"},
        BridgeHudStopOther_Upkeep = {"other_turn", "upkeep"}, BridgeHudStopOther_Draw = {"other_turn", "draw"},
        BridgeHudStopOther_MainPre = {"other_turn", "main_precombat"}, BridgeHudStopOther_BeginningCombat = {"other_turn", "beginning_combat"},
        BridgeHudStopOther_Attackers = {"other_turn", "declare_attackers"}, BridgeHudStopOther_Blockers = {"other_turn", "declare_blockers"},
        BridgeHudStopOther_Damage = {"other_turn", "combat_damage"}, BridgeHudStopOther_EndCombat = {"other_turn", "end_combat"},
        BridgeHudStopOther_MainPost = {"other_turn", "main_postcombat"}, BridgeHudStopOther_EndStep = {"other_turn", "end_step"}
    }
    for id, value in pairs(stopButtons) do
        local active = stops[value[1]] and stops[value[1]][value[2]] == true
        BridgeUiSet(id, "color", active and "#A16207EE" or "#334155CC")
    end
    BridgeUiSet("BridgeHudDevToggle", "text", devExpanded and "DEV ▲" or "DEV ▼")
    local reportVisible = devExpanded and ui.reportPanelVisible == true
    local reportCategoryIndex = tonumber(ui.reportCategoryIndex or 1) or 1
    BridgeUiSet("BridgeHudReportPanel", "active", reportVisible and "true" or "false")
    BridgeUiSet("BridgeHudReportOpen", "active", devEnabled and "true" or "false")
    BridgeUiSet("BridgeHudRollingCapture", "active", devEnabled and (ui.reportCaptureInFlight and "false" or "true") or "false")
    -- Keep recovery available after BridgeStopOnDesync.  The handler gives a
    -- diagnostic error if no Forge session exists; hiding it here made the
    -- recovery control disappear exactly when a library mismatch needed it.
    BridgeUiSet("BridgeHudResyncFromForge", "active", devEnabled and not ui.resyncInFlight and "true" or "false")
    BridgeUiSet("BridgeHudResyncFromForge", "text", ui.resyncInFlight and "RESYNCING..." or "RESYNC FORGE")
    -- Some TTS clients render Dropdown as a non-interactive checkbox. The
    -- adjacent previous/current buttons use ordinary Button callbacks and are
    -- reliable in desktop and VR, so they are the supported category control.
    BridgeUiSet("BridgeHudReportCategoryDropdown", "active", "false")
    BridgeUiSet("BridgeHudReportCategoryDropdown", "options", table.concat(BRIDGE_REPORT_CATEGORIES, "|"))
    BridgeUiSet("BridgeHudReportCategoryDropdown", "value", BRIDGE_REPORT_CATEGORIES[reportCategoryIndex] or "Other")
    local categoryControlsActive = reportVisible and not ui.reportCaptureInFlight
    BridgeUiSet("BridgeHudReportCategoryPrevious", "active", categoryControlsActive and "true" or "false")
    BridgeUiSet("BridgeHudReportCategory", "active", categoryControlsActive and "true" or "false")
    BridgeUiSet("BridgeHudReportCategory", "text", BRIDGE_REPORT_CATEGORIES[reportCategoryIndex] or "Other")
    BridgeUiSet("BridgeHudReportCapture", "active", reportVisible and (ui.reportCaptureInFlight and "false" or "true") or "false")
    BridgeUiSet("BridgeHudReportCancel", "active", reportVisible and (ui.reportCaptureInFlight and "false" or "true") or "false")
    BridgeUiSet("BridgeHudReportStatus", "text", ui.reportStatus or "")
    BridgeUiSet("BridgeHudReportStatus", "color", string.find(string.upper(tostring(ui.reportStatus or "")), "ERROR", 1, true) and BRIDGE_HUD_COLORS.danger or BRIDGE_HUD_COLORS.success)

    local decision = BridgeState.lastDecision
    local terminal = BridgeState.gameEnded
    local requiresConfirm = decision ~= nil and BridgeDecisionNeedsConfirmation(decision)
    local creatureTypeDecision = decision ~= nil and decision.kind == "creature_type_selection"
    local castPreviewPending = BridgeState.pendingIntent ~= nil
        and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell"
    local gameControlsActive = terminal == nil and not requiresConfirm and not creatureTypeDecision
        and not castPreviewPending
    BridgeUiSet("BridgeHudGameControls", "active", gameControlsActive and "true" or "false")
    BridgeUiSet("BridgeHudDecisionControls", "active", (terminal == nil and (requiresConfirm or castPreviewPending)) and "true" or "false")

    -- Keep the fixed 24-row action transport intact.  The tray itself is now
    -- contextual and disappears when PASS/YIELD are the only available choice.
    local hasTextChoices = false
    for _, action in ipairs(ui.actionRows or {}) do
        if action.type ~= "pass_priority" then
            hasTextChoices = true
            break
        end
    end
    local graveyardFolderVisible = decision ~= nil
        and ui.graveyardFolderDecisionId == decision.decisionId
        and ui.graveyardFolderOpen == true
    BridgeUiSet("BridgeHudChoiceTray", "active", hasTextChoices and not creatureTypeDecision
        and not graveyardFolderVisible and "true" or "false")
    BridgeUiSet("BridgeHudGraveyardPanel", "active", graveyardFolderVisible and "true" or "false")
    local graveyardPage = tonumber(ui.graveyardFolderPage or 1) or 1
    local graveyardPageCount = math.max(math.ceil(#(ui.graveyardActionRows or {}) / 24), 1)
    BridgeUiSet("BridgeHudGraveyardOverflow", "text", graveyardFolderVisible
        and ("Page " .. tostring(graveyardPage) .. " / " .. tostring(graveyardPageCount)) or "")
    BridgeUiSet("BridgeHudGraveyardPrev", "active", graveyardFolderVisible and graveyardPage > 1 and "true" or "false")
    BridgeUiSet("BridgeHudGraveyardNext", "active", graveyardFolderVisible and graveyardPage < graveyardPageCount and "true" or "false")
    for i = 1, 24 do
        local action = graveyardFolderVisible and ui.graveyardActionRows[(graveyardPage - 1) * 24 + i] or nil
        BridgeUiSet("BridgeHudGraveyardAction" .. tostring(i), "active", action ~= nil and "true" or "false")
        if action ~= nil then
            BridgeUiSet("BridgeHudGraveyardAction" .. tostring(i), "text", BridgeUiActionLabel(action))
            BridgeUiSet("BridgeHudGraveyardAction" .. tostring(i), "tooltip", "Forge action from "
                .. tostring(action.sourceCardName or action.cardIdentity or "graveyard card")
                .. "\nAction ID: " .. tostring(action.actionId))
        end
    end
    BridgeUiSet("BridgeHudGraveyardClose", "active", graveyardFolderVisible and "true" or "false")
    local creatureTypeLabels = {}
    local creatureTypeSelectedLabel = ""
    for _, option in ipairs(ui.creatureTypeOptions or {}) do
        table.insert(creatureTypeLabels, option.label)
        if option.actionId == ui.creatureTypeDraftActionId then creatureTypeSelectedLabel = option.label end
    end
    BridgeUiSet("BridgeHudCreatureTypePanel", "active", creatureTypeDecision and "true" or "false")
    -- TTS Dropdown cannot safely hold an empty option list, even while the
    -- containing panel is inactive. Keep a neutral sentinel until Forge
    -- supplies a creature-type decision.
    local creatureTypeOptions = #creatureTypeLabels > 0 and table.concat(creatureTypeLabels, "|") or "Choose"
    local creatureTypeValue = creatureTypeSelectedLabel ~= "" and creatureTypeSelectedLabel or "Choose"
    BridgeUiSet("BridgeHudCreatureTypeDropdown", "options", creatureTypeOptions)
    BridgeUiSet("BridgeHudCreatureTypeDropdown", "value", creatureTypeValue)
    BridgeUiSet("BridgeHudCreatureTypeConfirm", "active", creatureTypeDecision
        and ui.creatureTypeDraftActionId ~= nil and "true" or "false")
    BridgeUiSet("BridgeHudCreatureTypeStatus", "text", creatureTypeDecision
        and (ui.creatureTypeDraftActionId and "Draft selected — press CONFIRM to submit to Forge"
            or "Choose a creature type, then press CONFIRM") or "")

    local connectionText, connectionColor = BridgeHudConnectionPresentation()
    BridgeUiSet("BridgeHudConnection", "text", connectionText)
    BridgeUiSet("BridgeHudConnection", "color", connectionColor)

    local stack = BridgeState.stackSummary or {}
    BridgeUiSet("BridgeHudStack", "text", #stack > 0 and ("STACK " .. tostring(#stack)) or "")
    BridgeHudRefreshPhaseRibbon()

    if BRIDGE_DEV_ANNOTATIONS_ENABLED == true then
        local diagnostic = string.format(
            "session=%s  decision=%s  events=%s/%s  queue=%d  forgeSeq=%s",
            tostring(BridgeState.eventSessionId or "none"),
            tostring(decision and decision.decisionId or "none"),
            tostring(BridgeState.lastAppliedEventSequence or 0),
            tostring(BridgeState.lastReceivedEventSequence or 0),
            #(BridgeState.eventQueue or {}),
            tostring(BridgeState.snapshotForgeSequence or 0)
        )
        BridgeUiSet("BridgeHudDevDiagnostic", "text", diagnostic)
    else
        BridgeUiSet("BridgeHudDevDiagnostic", "text", "")
    end
end

-- Dedicated physical priority controls can survive Save & Play while their
-- scripted createButton overlay does not.  Always rehydrate that overlay when
-- an existing control is rediscovered, instead of leaving a blank colored slab.
function BridgeConfigureEndTurnObject(object, seat)
    if object == nil or seat == nil or not BridgeObjectIsUsable(object) then return end
    BridgeSafeObjectCall(object, function(o)
        o.setName("Forge End Turn")
        o.setLock(true)
        o.setColorTint({0.12, 0.3, 0.62})
        o.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
        if o.clearButtons ~= nil then o.clearButtons() end
        o.createButton({
            click_function = "BridgePressEndTurn",
            function_owner = Global,
            label = "END TURN\n(YIELD)",
            position = {0, 0.6, 0},
            width = 1100,
            height = 520,
            font_size = 170,
            color = {0.15, 0.35, 0.65, 1.0},
            font_color = {1.0, 1.0, 1.0, 1.0},
            tooltip = "Yield Forge priority for the rest of this turn"
        })
    end)
end

function BridgeConfigurePassObject(object, seat)
    if object == nil or seat == nil or not BridgeObjectIsUsable(object) then return end
    BridgeSafeObjectCall(object, function(o)
        o.setName("Forge Pass Priority")
        o.setLock(true)
        o.setColorTint({0.22, 0.5, 0.56})
        o.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
        if o.clearButtons ~= nil then o.clearButtons() end
        o.createButton({
            click_function = "BridgePressPass",
            function_owner = Global,
            label = "PASS /\nCONTINUE",
            position = {0, 0.6, 0},
            width = 1000,
            height = 520,
            font_size = 160,
            color = {0.22, 0.5, 0.56, 1.0},
            font_color = {1, 1, 1, 1},
            tooltip = "Pass exactly this Forge priority decision"
        })
    end)
end

function BridgeEnsureEndTurnButton(seatId)
    if BRIDGE_PHYSICAL_PRIORITY_CONTROLS_ENABLED ~= true then return end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local targetPosition = {-11.0, 1.6, seat.tableSideZ * 4.2}
    local existing = BridgeGetLiveObjectByGuid(BridgeState.endTurnObjectGuidBySeatId[seatId])
    if existing == nil then
        existing = BridgeFindNamedObject("Forge End Turn")
        if existing ~= nil then
            BridgeState.endTurnObjectGuidBySeatId[seatId] = existing.getGUID()
        end
    end
    if existing ~= nil then
        BridgeConfigureEndTurnObject(existing, seat)
        BridgeSafeObjectCall(existing, function(o) o.setPositionSmooth(targetPosition, false, true) end)
        return
    end
    spawnObject({
        type = "BlockSquare",
        position = targetPosition,
        scale = {3.2, 0.35, 1.6},
        callback_function = function(object)
            BridgeConfigureEndTurnObject(object, seat)
            if BridgeObjectIsUsable(object) then
                BridgeState.endTurnObjectGuidBySeatId[seatId] = object.getGUID()
            end
        end
    })
end

function BridgeEnsurePassButton(seatId)
    if BRIDGE_PHYSICAL_PRIORITY_CONTROLS_ENABLED ~= true then return end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local targetPosition = {-6.8, 1.6, seat.tableSideZ * 4.2}
    local existing = BridgeGetLiveObjectByGuid(BridgeState.passObjectGuidBySeatId[seatId])
    if existing == nil then
        existing = BridgeFindNamedObject("Forge Pass Priority")
        if existing ~= nil then
            BridgeState.passObjectGuidBySeatId[seatId] = existing.getGUID()
        end
    end
    if existing ~= nil then
        BridgeConfigurePassObject(existing, seat)
        BridgeSafeObjectCall(existing, function(o) o.setPositionSmooth(targetPosition, false, true) end)
        return
    end
    spawnObject({
        type = "BlockSquare",
        position = targetPosition,
        scale = {2.7, 0.35, 1.6},
        callback_function = function(object)
            BridgeConfigurePassObject(object, seat)
            if BridgeObjectIsUsable(object) then
                BridgeState.passObjectGuidBySeatId[seatId] = object.getGUID()
            end
        end
    })
end

-- Flight-recorder wrappers keep the hot paths unchanged. They append a few
-- scalar values to the bounded in-memory ring and never perform I/O.
local BridgeAcceptDecisionFlightRecorderBase = BridgeAcceptDecision
function BridgeAcceptDecision(decision, origin, expectedSessionId, presentationGeneration)
    local token = BridgePerformanceBegin("decision_accept_begin")
    BridgeAcceptDecisionFlightRecorderBase(decision, origin, expectedSessionId, presentationGeneration)
    BridgePerformanceEnd(token, "decision_accept_end")
end

local BridgeRenderDecisionFlightRecorderBase = BridgeRenderDecision
function BridgeRenderDecision(decision, force)
    local token = BridgePerformanceBegin("decision_render_begin")
    local key = BridgeDecisionPresentationKey(decision)
    local skipped = force ~= true and key == BridgeState.renderedDecisionPresentationKey
        and BridgeState.renderedDecisionPhysicalGeneration == (BridgeState.currentPhysicalPresentationGeneration or 0)
    if skipped then BridgePerformanceTrace("decision_render_skipped") end
    local candidateToken = BridgePerformanceBegin("candidate_collection_begin")
    local matchingToken = BridgePerformanceBegin("action_matching_begin")
    BridgeRenderDecisionFlightRecorderBase(decision, force)
    BridgePerformanceRecordTtsActionRepresentation()
    BridgePerformanceEnd(matchingToken, "action_matching_end", "actionMatching")
    BridgePerformanceEnd(candidateToken, "candidate_collection_end", "candidateCollection")
    BridgePerformanceEnd(token, "decision_render_end", "render")
end

local BridgeClearHighlightsFlightRecorderBase = BridgeClearHighlights
function BridgeClearHighlights()
    local token = BridgePerformanceBegin("clear_highlights_begin")
    BridgeClearHighlightsFlightRecorderBase()
    BridgePerformanceEnd(token, "clear_highlights_end", "clearHighlights")
end

local BridgeRenderPreparedFlightRecorderBase = BridgeRenderPreparedSpellPresentations
function BridgeRenderPreparedSpellPresentations(decision)
    local token = BridgePerformanceBegin("prepared_presentation_begin")
    BridgeRenderPreparedFlightRecorderBase(decision)
    BridgePerformanceEnd(token, "prepared_presentation_end", "preparedPresentation")
end

local BridgeApplyEventFlightRecorderBase = BridgeApplyAuthoritativeEvent
function BridgeApplyAuthoritativeEvent(event)
    local token = BridgePerformanceBegin("authoritative_event_begin", event and event.sequence)
    local applied, delay, errorMessage = BridgeApplyEventFlightRecorderBase(event)
    BridgePerformanceEnd(token, "authoritative_event_end", nil, event and event.sequence)
    return applied, delay, errorMessage
end

local BridgeSnapshotReconcileFlightRecorderBase = BridgeApplySafeSnapshotReconcile
function BridgeApplySafeSnapshotReconcile(snapshot, reason)
    local totalToken = BridgePerformanceBegin("snapshot_reconcile.total", snapshot and snapshot.eventCursor)
    local token = BridgePerformanceBegin("snapshot_reconcile_begin", snapshot and snapshot.eventCursor)
    BridgeSnapshotReconcileFlightRecorderBase(snapshot, reason)
    BridgePerformanceEnd(token, "snapshot_reconcile_end", "snapshotReconcile")
    BridgePerformanceEnd(totalToken, "snapshot_reconcile.total.end", "snapshotReconcile")
end

local BridgeMoveToBattlefieldFlightRecorderBase = BridgeMoveToBattlefield
function BridgeMoveToBattlefield(event, object, row, countAsNewPlacement)
    local token = BridgePerformanceBegin("physical_move_begin", event and event.sequence)
    local moved, errorMessage = BridgeMoveToBattlefieldFlightRecorderBase(event, object, row, countAsNewPlacement)
    BridgePerformanceEnd(token, "physical_move_end", nil, event and event.sequence)
    return moved, errorMessage
end

local BridgeCollectSeatAssetsFlightRecorderBase = BridgeCollectSeatAssets
function BridgeCollectSeatAssets(seatId, seatSnapshot, callback)
    local token = BridgePerformanceBegin("candidate_collection_begin")
    return BridgeCollectSeatAssetsFlightRecorderBase(seatId, seatSnapshot, function(ok, assets, errorMessage)
        BridgePerformanceEnd(token, "candidate_collection_end", "candidateCollection", assets and #assets or 0)
        callback(ok, assets, errorMessage)
    end)
end

local BridgeUiFlushFlightRecorderBase = BridgeUiFlush
function BridgeUiFlush()
    local token = BridgePerformanceBegin("ui_flush_begin")
    BridgeUiFlushFlightRecorderBase()
    BridgePerformanceEnd(token, "ui_flush_end", "uiFlush")
end
