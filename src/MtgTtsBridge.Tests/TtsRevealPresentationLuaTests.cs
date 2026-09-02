using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsRevealPresentationLuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void RevealWaitsForAppliedEventAndDuplicateDeliveryIsIdempotent()
    {
        var lua = NewProbe();
        lua.DoString(@"
            reveal = {
                presentationId='reveal-1', originatingEventSequence=12, visibility='public',
                cards={{authoritativeObjectId='forge:card:1', cardName='Island', imageUrl='https://art/island'}},
                lifecycle='opened'
            }
            before = BridgeApplyRevealPresentation(reveal, 12)
            BridgeState.lastAppliedEventSequence = 12
            first = BridgeApplyRevealPresentation(reveal, 12)
            second = BridgeApplyRevealPresentation(reveal, 12)
        ");

        Assert.False(lua.Globals.Get("before").Boolean);
        Assert.True(lua.Globals.Get("first").Boolean);
        Assert.True(lua.Globals.Get("second").Boolean);
        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(1, state.Get("revealedPresentationOrder").Table.Length);
        Assert.Equal("reveal-1@12", state.Get("activeRevealPresentationKey").String);
    }

    [Fact]
    public void PrivateRevealIsVisibleOnlyToEntitledHumanAndMissingArtUsesFallback()
    {
        var lua = NewProbe();
        lua.DoString(@"
            privateReveal = {
                presentationId='look-1', originatingEventSequence=3, visibility='private',
                entitledViewerSeatIds={'forge-player-2'}, cards={{authoritativeObjectId='x', cardName='Secret'}},
                lifecycle='opened'
            }
            hidden = BridgeApplyRevealPresentation(privateReveal, 3)
            BridgeState.lastAppliedEventSequence = 3
            privateReveal.entitledViewerSeatIds = {'forge-player-1'}
            shown = BridgeApplyRevealPresentation(privateReveal, 3)
            probeImage = BridgeRevealCardArt({cardName='Secret'})
            probeKey = BridgeState.activeRevealPresentationKey
        ");

        Assert.False(lua.Globals.Get("hidden").Boolean);
        Assert.True(lua.Globals.Get("shown").Boolean);
        Assert.Equal(DataType.Nil, lua.Globals.Get("probeImage").Type);
        Assert.Equal("look-1@3", lua.Globals.Get("probeKey").String);
    }

    [Fact]
    public void DecisionRevealClosesWhenItsAuthoritativeDecisionIsSuperseded()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 8
            BridgeApplyRevealPresentation({
                presentationId='choice-reveal', originatingEventSequence=8, visibility='public',
                associatedDecisionId='decision-1', acknowledgmentRequired=true,
                cards={{authoritativeObjectId='x', cardName='Mountain'}}, lifecycle='opened'
            }, 8)
            BridgeResolveRevealForDecision({decisionId='decision-1'})
            retained = BridgeState.activeRevealPresentationKey ~= nil
            BridgeResolveRevealForDecision({decisionId='decision-2'})
            closed = BridgeState.activeRevealPresentationKey == nil
        ");

        Assert.True(lua.Globals.Get("retained").Boolean);
        Assert.True(lua.Globals.Get("closed").Boolean);
    }

    [Fact]
    public void RevealScrollUsesOneSurfaceAndPreservesOrderedCards()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 20
            local cards = {
                {authoritativeObjectId='card-1', cardName='Card 1', imageUrl='art-1'},
                {authoritativeObjectId='card-2', cardName='Card 2', imageUrl='art-2'},
                {authoritativeObjectId='card-3', cardName='Card 3', imageUrl='art-3'},
                {authoritativeObjectId='card-4', cardName='Card 4', imageUrl='art-4'},
                {authoritativeObjectId='card-5', cardName='Card 5', imageUrl='art-5'},
                {authoritativeObjectId='card-6', cardName='Card 6', imageUrl='art-6'},
                {authoritativeObjectId='card-7', cardName='Card 7', imageUrl='art-7'},
                {authoritativeObjectId='card-8', cardName='Card 8', imageUrl='art-8'}
            }
            BridgeApplyRevealPresentation({presentationId='batch', originatingEventSequence=20, visibility='public', cards=cards, lifecycle='opened'}, 20)
            activeBefore = BridgeState.activeRevealPresentationKey
            slots = BRIDGE_REVEAL_SURFACE_SLOTS
            cardLength = #cards
            BridgeHudRevealScroll(nil, nil, 'BridgeHudRevealNext')
            offset = BridgeState.revealSurfaceOffset
            count = #BridgeState.revealedPresentationsByKey['batch@20'].cards
        ");

        Assert.Equal("batch@20", lua.Globals.Get("activeBefore").String);
        Assert.Equal(6, lua.Globals.Get("slots").Number);
        Assert.Equal(8, lua.Globals.Get("cardLength").Number);
        Assert.Equal(2, lua.Globals.Get("offset").Number);
        Assert.Equal(8, lua.Globals.Get("count").Number);
    }

    private static Script NewProbe()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function getAllObjects() return {} end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}'; end, decode = function(value) return {}; end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            table.concat = function(values, separator) return 'probe-runtime' end
            UI = {setAttribute = function(id, attribute, value)
                if id == 'BridgeHudRevealFallback1' and attribute == 'active' then fallbackActive = value == 'true' end
                if id == 'BridgeHudRevealFallback1' and attribute == 'text' then fallbackText = value end
            end}
            BridgeState = {}
        ");
        var revealSource = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "tts", "src", "25-revealed-cards.lua"));
        lua.DoString(File.ReadAllText(revealSource));
        lua.DoString(@"
            BridgeState.ui = {mounted=true}
            BridgeState.eventSessionId = 'session'
            BridgeState.lastAppliedEventSequence = 0
            BridgeState.revealedPresentationsByKey = {}
            BridgeState.revealedPresentationOrder = {}
            BridgeState.dismissedRevealKeys = {}
            BridgeState.activeRevealPresentationKey = nil
            BridgeState.revealSurfaceOffset = 1
            function BridgeUiSet(id, attribute, value)
                if id == 'BridgeHudRevealFallback1' and attribute == 'active' then fallbackActive = value == 'true' end
                if id == 'BridgeHudRevealFallback1' and attribute == 'text' then fallbackText = value end
            end
            function BridgeUiMarkDirty(reason) end
        ");
        return lua;
    }
}
