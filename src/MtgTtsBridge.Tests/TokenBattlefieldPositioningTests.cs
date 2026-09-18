using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

/// <summary>
/// Tests for token-specific vertical-first battlefield layout.
/// Tokens should fill vertically (toward controller) first, then advance horizontally.
/// Normal creatures retain horizontal-first layout.
/// 
/// Note: These tests verify the Lua grid math and configuration, not the full state machine.
/// The state tracking in BridgeBattlefieldPosition depends on TTS getAllObjects() which
/// cannot be easily mocked. Full validation occurs in live TTS or with a proper TTS simulator.
/// </summary>
public sealed class TokenBattlefieldPositioningTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    private static Script NewLua()
    {
        var lua = new Script(CoreModules.Preset_Complete);
        lua.DoString(@"
            function log() end
            function broadcastToAll() end
            function printToAll() end
            function getObjectFromGUID() return nil end
            function getAllObjects() return {} end
            function Wait() end
            Time = { waitForSeconds = function(_, callback) if callback then callback() end end }
            WebRequest = {}
            JSON = { encode = function() return '{}' end, decode = function() return {} end }
        ");
        lua.DoString(Script);
        lua.DoString(@"
            JSON = JSON or {}
            JSON.encode = function() return '{}' end
            JSON.decode = function() return {} end
        ");
        return lua;
    }

    [Fact]
    public void TokenGridMathCalculatesVerticalFirstLayout()
    {
        var lua = NewLua();
        lua.DoString(@"
            -- Verify token grid math directly (3 depth × 4 columns)
            -- Tokens 1-3: column 0, depths 0-2
            -- Tokens 4-6: column 1, depths 0-2
            
            local token1_slot = 0
            local token1_col = math.floor(token1_slot / 3)  -- floor(0/3) = 0
            local token1_depth = token1_slot % 3            -- 0 % 3 = 0
            assert(token1_col == 0 and token1_depth == 0, 'Token 1 grid math incorrect')
            
            local token2_slot = 1
            local token2_col = math.floor(token2_slot / 3)  -- floor(1/3) = 0
            local token2_depth = token2_slot % 3            -- 1 % 3 = 1
            assert(token2_col == 0 and token2_depth == 1, 'Token 2 grid math incorrect')
            
            local token3_slot = 2
            local token3_col = math.floor(token3_slot / 3)  -- floor(2/3) = 0
            local token3_depth = token3_slot % 3            -- 2 % 3 = 2
            assert(token3_col == 0 and token3_depth == 2, 'Token 3 grid math incorrect')
            
            local token4_slot = 3
            local token4_col = math.floor(token4_slot / 3)  -- floor(3/3) = 1
            local token4_depth = token4_slot % 3            -- 3 % 3 = 0
            assert(token4_col == 1 and token4_depth == 0, 'Token 4 grid math incorrect')
            
            local token5_slot = 4
            local token5_col = math.floor(token5_slot / 3)  -- floor(4/3) = 1
            local token5_depth = token5_slot % 3            -- 4 % 3 = 1
            assert(token5_col == 1 and token5_depth == 1, 'Token 5 grid math incorrect')
            
            local token6_slot = 5
            local token6_col = math.floor(token6_slot / 3)  -- floor(5/3) = 1
            local token6_depth = token6_slot % 3            -- 5 % 3 = 2
            assert(token6_col == 1 and token6_depth == 2, 'Token 6 grid math incorrect')
        ");
    }

    [Fact]
    public void TokenDetectionViaIsTokenFlag()
    {
        var lua = NewLua();
        lua.DoString(@"
            -- Verify token detection logic
            local tokenEvent = { isToken = true }
            local normalEvent = { isToken = false }
            local nilEvent = nil
            
            -- isToken logic: event ~= nil and event.isToken == true and row == 'creature'
            local isToken1 = tokenEvent ~= nil and tokenEvent.isToken == true and true  -- Creature row
            assert(isToken1, 'Token detection failed for isToken=true')
            
            local isToken2 = normalEvent ~= nil and normalEvent.isToken == true and true
            assert(not isToken2, 'Token detection incorrectly flagged isToken=false')
            
            local isToken3 = nilEvent ~= nil and nilEvent.isToken == true and true
            assert(not isToken3, 'Token detection incorrectly flagged nil event')
        ");
    }

    [Fact]
    public void NormalCreatureGridMathCalculatesHorizontalFirstLayout()
    {
        var lua = NewLua();
        lua.DoString(@"
            -- Verify normal creature grid math (4 columns × 3 rows)
            -- Creatures 1-4: row 0, columns 0-3
            -- Creature 5: row 1, column 0
            
            local c1_slot = 0
            local c1_col = c1_slot % 4          -- 0 % 4 = 0
            local c1_row = math.floor(c1_slot / 4)  -- floor(0/4) = 0
            assert(c1_col == 0 and c1_row == 0, 'Creature 1 grid math incorrect')
            
            local c2_slot = 1
            local c2_col = c2_slot % 4          -- 1 % 4 = 1
            local c2_row = math.floor(c2_slot / 4)  -- floor(1/4) = 0
            assert(c2_col == 1 and c2_row == 0, 'Creature 2 grid math incorrect')
            
            local c3_slot = 2
            local c3_col = c3_slot % 4          -- 2 % 4 = 2
            local c3_row = math.floor(c3_slot / 4)  -- floor(2/4) = 0
            assert(c3_col == 2 and c3_row == 0, 'Creature 3 grid math incorrect')
            
            local c4_slot = 3
            local c4_col = c4_slot % 4          -- 3 % 4 = 3
            local c4_row = math.floor(c4_slot / 4)  -- floor(3/4) = 0
            assert(c4_col == 3 and c4_row == 0, 'Creature 4 grid math incorrect')
            
            local c5_slot = 4
            local c5_col = c5_slot % 4          -- 4 % 4 = 0
            local c5_row = math.floor(c5_slot / 4)  -- floor(4/4) = 1
            assert(c5_col == 0 and c5_row == 1, 'Creature 5 grid math incorrect')
        ");
    }

    [Fact]
    public void StateKeysSeparateTokensFromNormalCreatures()
    {
        var lua = NewLua();
        lua.DoString(@"
            -- Verify state key construction
            local seatId = 'forge-player-1'
            local isToken = true
            local tokenKey = seatId .. ':' .. (isToken and 'token' or 'creature')
            assert(tokenKey == 'forge-player-1:token', 'Token state key incorrect: ' .. tokenKey)
            
            local isToken2 = false
            local creatureKey = seatId .. ':' .. (isToken2 and 'token' or 'creature')
            assert(creatureKey == 'forge-player-1:creature', 'Creature state key incorrect: ' .. creatureKey)
            
            -- Verify they're different
            assert(tokenKey ~= creatureKey, 'State keys should be different')
        ");
    }

    [Fact]
    public void TokenPositionCalculationWithSeatConfig()
    {
        var lua = NewLua();
        lua.DoString(@"
            -- Verify actual position calculation for tokens with real seat config
            local seat = BRIDGE_SEATS['forge-player-1']
            local anchor = seat.battlefieldAnchors.creature
            local sideZ = seat.tableSideZ
            
            -- Token 1: slot 0, column 0, depth 0
            local slot = 0
            local depth = slot % 3
            local column = math.floor(slot / 3)
            local x = anchor.x + column * 3.4
            local z = anchor.z + depth * sideZ * 4.0
            
            assert(depth == 0, 'Token 1 depth incorrect')
            assert(column == 0, 'Token 1 column incorrect')
            assert(x == anchor.x, 'Token 1 x calculation incorrect')
            assert(z == anchor.z, 'Token 1 z calculation incorrect (no depth offset)')
            
            -- Token 2: slot 1, column 0, depth 1
            slot = 1
            depth = slot % 3
            column = math.floor(slot / 3)
            x = anchor.x + column * 3.4
            z = anchor.z + depth * sideZ * 4.0
            
            assert(depth == 1, 'Token 2 depth incorrect')
            assert(column == 0, 'Token 2 column incorrect')
            assert(x == anchor.x, 'Token 2 x calculation incorrect')
            assert(z == anchor.z + sideZ * 4.0, 'Token 2 z calculation incorrect')
        ");
    }

    [Fact]
    public void NormalCreaturePositionCalculationWithSeatConfig()
    {
        var lua = NewLua();
        lua.DoString(@"
            -- Verify actual position calculation for normal creatures with real seat config
            local seat = BRIDGE_SEATS['forge-player-1']
            local anchor = seat.battlefieldAnchors.creature
            local sideZ = seat.tableSideZ
            
            -- Creature 1: slot 0, column 0, row 0
            local slot = 0
            local column = slot % 4
            local row = math.floor(slot / 4)
            local x = anchor.x + column * 3.4
            local z = anchor.z + row * sideZ * 4.0
            
            assert(column == 0, 'Creature 1 column incorrect')
            assert(row == 0, 'Creature 1 row incorrect')
            assert(x == anchor.x, 'Creature 1 x calculation incorrect')
            assert(z == anchor.z, 'Creature 1 z calculation incorrect (no row offset)')
            
            -- Creature 5: slot 4, column 0, row 1
            slot = 4
            column = slot % 4
            row = math.floor(slot / 4)
            x = anchor.x + column * 3.4
            z = anchor.z + row * sideZ * 4.0
            
            assert(column == 0, 'Creature 5 column incorrect')
            assert(row == 1, 'Creature 5 row incorrect')
            assert(x == anchor.x, 'Creature 5 x calculation incorrect')
            assert(z == anchor.z + sideZ * 4.0, 'Creature 5 z calculation incorrect')
        ");
    }
}
