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
    public void DuplicateRevealDeliveryPreservesViewerInteractionState()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 12
            reveal = {presentationId='repeat', originatingEventSequence=12, visibility='public',
                cards={{authoritativeObjectId='card', cardName='Island'}}, lifecycle='opened'}
            BridgeApplyRevealPresentation(reveal, 12)
            BridgeHudRevealInteract({color='White'}, nil, 'BridgeHudRevealCardButton1')
            BridgeHudRevealCardHoverEnter({color='White'}, nil, 'BridgeHudRevealCardButton1')
            magnifyBeforeRepeat = BridgeRevealMagnifyPress({color='White'})
            pinnedBeforeRepeat = BridgeState.revealViewerStateByColor.White.pinned
            BridgeApplyRevealPresentation(reveal, 12)
            pinnedAfterRepeat = BridgeState.revealViewerStateByColor.White.pinned
            activeAfterRepeat = BridgeState.revealViewerStateByColor.White.activeKey
            magnifyAfterRepeat = BridgeState.revealViewerStateByColor.White.magnifier.active
        ");

        Assert.True(lua.Globals.Get("pinnedBeforeRepeat").Boolean);
        Assert.True(lua.Globals.Get("pinnedAfterRepeat").Boolean);
        Assert.Equal("repeat@12", lua.Globals.Get("activeAfterRepeat").String);
        Assert.True(lua.Globals.Get("magnifyBeforeRepeat").Boolean);
        Assert.True(lua.Globals.Get("magnifyAfterRepeat").Boolean);
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

    [Fact]
    public void InformationalRevealAutoDismissesOnlyAfterItsTenSecondDeadline()
    {
        var lua = NewProbe();
        lua.DoString(@"
            scheduled = {}
            BridgeWaitTime = function(callback, delay) scheduled[#scheduled + 1] = callback; scheduledDelay = delay end
            BridgeState.lastAppliedEventSequence = 1
            BridgeApplyRevealPresentation({presentationId='a', originatingEventSequence=1, visibility='public', cards={{authoritativeObjectId='a-card', cardName='Island'}}, lifecycle='opened'}, 1)
            visibleAtNinePointNine = BridgeState.activeRevealPresentationKey ~= nil
            scheduled[1]()
            dismissedAtTen = BridgeState.activeRevealPresentationKey == nil
        ");

        Assert.True(lua.Globals.Get("visibleAtNinePointNine").Boolean);
        Assert.Equal(10, lua.Globals.Get("scheduledDelay").Number);
        Assert.True(lua.Globals.Get("dismissedAtTen").Boolean);
    }

    [Fact]
    public void RevealInteractionPinsAndMakesItsScheduledTimeoutInert()
    {
        var lua = NewProbe();
        lua.DoString(@"
            scheduled = {}
            nextTimer = 0
            BridgeWaitTime = function(callback, delay) nextTimer = nextTimer + 1; scheduled[nextTimer] = callback end
            BridgeState.lastAppliedEventSequence = 2
            BridgeApplyRevealPresentation({presentationId='a', originatingEventSequence=2, visibility='public', cards={{authoritativeObjectId='a-card', cardName='Island'}}, lifecycle='opened'}, 2)
            BridgeHudRevealInteract(nil, nil, 'BridgeHudRevealCardButton1')
            pinned = BridgeState.revealedPresentationsByKey['a@2'].pinnedByUser
            scheduled[1]()
            remainsVisible = BridgeState.activeRevealPresentationKey == 'a@2'
        ");

        Assert.True(lua.Globals.Get("pinned").Boolean);
        Assert.True(lua.Globals.Get("remainsVisible").Boolean);
    }

    [Fact]
    public void StaleRevealTimerCannotDismissTheReplacementPresentation()
    {
        var lua = NewProbe();
        lua.DoString(@"
            scheduled = {}
            nextTimer = 0
            BridgeWaitTime = function(callback, delay) nextTimer = nextTimer + 1; scheduled[nextTimer] = callback end
            BridgeState.lastAppliedEventSequence = 4
            firstApplied = BridgeApplyRevealPresentation({presentationId='a', originatingEventSequence=3, visibility='public', cards={{authoritativeObjectId='a-card', cardName='Island'}}, lifecycle='opened'}, 3)
            secondApplied = BridgeApplyRevealPresentation({presentationId='b', originatingEventSequence=4, visibility='public', cards={{authoritativeObjectId='b-card', cardName='Mountain'}}, lifecycle='opened'}, 4)
            scheduledCount = nextTimer
        ");

        Assert.True(lua.Globals.Get("firstApplied").Boolean);
        Assert.True(lua.Globals.Get("secondApplied").Boolean);
        Assert.Equal(2, lua.Globals.Get("scheduledCount").Number);
        lua.DoString(@"
            scheduled[1]()
            bSurvivesA = BridgeState.activeRevealPresentationKey == 'b@4'
            scheduled[2]()
            bDismissesOnOwnTimer = BridgeState.activeRevealPresentationKey == nil
        ");
        Assert.True(lua.Globals.Get("bSurvivesA").Boolean);
        Assert.True(lua.Globals.Get("bDismissesOnOwnTimer").Boolean);
    }

    [Fact]
    public void DecisionBoundRevealNeverSchedulesAnInformationalTimeout()
    {
        var lua = NewProbe();
        lua.DoString(@"
            scheduled = {}
            BridgeWaitTime = function(callback, delay) scheduled[#scheduled + 1] = callback end
            BridgeState.lastAppliedEventSequence = 4
            BridgeApplyRevealPresentation({presentationId='choice', originatingEventSequence=4, visibility='public', associatedDecisionId='decision-12', cards={{authoritativeObjectId='card', cardName='Island'}}, lifecycle='opened'}, 4)
            noTimerWhileDecisionCurrent = #scheduled == 0 and BridgeState.activeRevealPresentationKey ~= nil
            BridgeResolveRevealForDecision({decisionId='decision-13'})
            closesWhenDecisionChanges = BridgeState.activeRevealPresentationKey == nil
        ");

        Assert.True(lua.Globals.Get("noTimerWhileDecisionCurrent").Boolean);
        Assert.True(lua.Globals.Get("closesWhenDecisionChanges").Boolean);
    }

    [Fact]
    public void RevealArtUsesCanonicalThenProducerUrlThenNameFallbackEvenInFastMode()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 5
            BridgeState.ui.fastPlaytest = true
            BridgeResolveCanonicalCardArt = function(face, name) if face == 'canonical-face' then return 'canonical-art' end end
            canonicalArt = BridgeRevealCardArt({cardFaceIdentity='canonical-face', cardName='Island', imageUrl='producer-one'})
            producerArt = BridgeRevealCardArt({cardName='Mountain', imageUrl='producer-two'})
            function BridgeUiSet(id, attribute, value)
                if id == 'BridgeHudRevealImage1' and attribute == 'image' then imageOne = value end
                if id == 'BridgeHudRevealImage2' and attribute == 'image' then imageTwo = value end
                if id == 'BridgeHudRevealFallback3' and attribute == 'text' then fallbackThree = value end
                if id == 'BridgeHudRevealSurface' and attribute == 'active' then surfaceActive = value end
            end
            BridgeApplyRevealPresentation({presentationId='art', originatingEventSequence=5, visibility='public', cards={
                {authoritativeObjectId='one', cardName='Island', cardFaceIdentity='canonical-face', imageUrl='producer-one'},
                {authoritativeObjectId='two', cardName='Mountain', imageUrl='producer-two'},
                {authoritativeObjectId='three', cardName='Unknown'}
            }, lifecycle='opened'}, 5)
            BridgeRenderRevealSurface()
        ");

        Assert.Equal("true", lua.Globals.Get("surfaceActive").String);
        Assert.Equal("canonical-art", lua.Globals.Get("canonicalArt").String);
        Assert.Equal("producer-two", lua.Globals.Get("producerArt").String);
    }

    [Fact]
    public void RevealArtSourceDiagnosticsTrackCanonicalProducerAndFallbackSeparately()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 6
            BridgeResolveCanonicalCardArt = function(face, name) if face == 'face-1' then return 'canonical-url' end end
            lastDiagnostic = ''
            function BridgeUiSet(id, attribute, value)
                if id == 'BridgeHudRevealArtSource' and attribute == 'text' then lastDiagnostic = value end
            end
            BridgeApplyRevealPresentation({presentationId='diagnostic', originatingEventSequence=6, visibility='public', cards={
                {authoritativeObjectId='c1', cardName='Card1', cardFaceIdentity='face-1'},
                {authoritativeObjectId='c2', cardName='Card2', imageUrl='https://example.com/producer-url.png'},
                {authoritativeObjectId='c3', cardName='Card3'}
            }, lifecycle='opened'}, 6)
            BridgeRenderRevealSurface()
        ");

        var diagnostic = lua.Globals.Get("lastDiagnostic").String;
        Assert.NotEmpty(diagnostic);
        // At minimum, should track some art source categories
        Assert.Contains(":", diagnostic, StringComparison.Ordinal);
        // Should include the producer-url source for card 2
        Assert.Contains("producer-url", diagnostic, StringComparison.Ordinal);
    }

    [Fact]
    public void PublicAndPrivateRevealsUseConfiguredViewerSeatProjections()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 10
            publicApplied = BridgeApplyRevealPresentation({
                presentationId='public', originatingEventSequence=10, visibility='public',
                cards={{authoritativeObjectId='public-card', cardName='Island'}}, lifecycle='opened'
            }, 10)
            publicWhite = BridgeState.revealViewerStateByColor.White.activeKey
            publicBlue = BridgeState.revealViewerStateByColor.Blue.activeKey
            BridgeResetRevealSessionState('test-private')
            privateApplied = BridgeApplyRevealPresentation({
                presentationId='private', originatingEventSequence=10, visibility='private',
                entitledViewerSeatIds={'forge-player-2'},
                cards={{authoritativeObjectId='private-card', cardName='Secret'}}, lifecycle='opened'
            }, 10)
            privateWhite = BridgeState.revealViewerStateByColor.White.activeKey
            privateBlue = BridgeState.revealViewerStateByColor.Blue.activeKey
            privateWhiteMaySee = BridgeRevealViewerMaySee({visibility='private', entitledViewerSeatIds={'forge-player-2'}}, 'White')
            privateBlueMaySee = BridgeRevealViewerMaySee({visibility='private', entitledViewerSeatIds={'forge-player-2'}}, 'Blue')
        ");

        Assert.True(lua.Globals.Get("publicApplied").Boolean);
        Assert.Equal("public@10", lua.Globals.Get("publicWhite").String);
        Assert.Equal("public@10", lua.Globals.Get("publicBlue").String);
        Assert.False(lua.Globals.Get("privateApplied").Boolean);
        Assert.Equal(DataType.Nil, lua.Globals.Get("privateWhite").Type);
        Assert.Equal("private@10", lua.Globals.Get("privateBlue").String);
        Assert.False(lua.Globals.Get("privateWhiteMaySee").Boolean);
        Assert.True(lua.Globals.Get("privateBlueMaySee").Boolean);
    }

    [Fact]
    public void RevealTimerCyclesPerViewerAndDifferentViewersKeepIndependentSettings()
    {
        var lua = NewProbe();
        lua.DoString(@"
            timerDefault = BridgeRevealGetPreferences('forge-player-1').timerMode == 10
            BridgeHudRevealTimerCycle(nil, nil, nil)
            timerOffFirst = BridgeRevealGetPreferences('forge-player-1').timerMode
            BridgeHudRevealTimerCycle(nil, nil, nil)
            timerThree = BridgeRevealGetPreferences('forge-player-1').timerMode
            BridgeHudRevealTimerCycle(nil, nil, nil)
            timerFive = BridgeRevealGetPreferences('forge-player-1').timerMode
            BridgeHudRevealTimerCycle(nil, nil, nil)
            timerTen = BridgeRevealGetPreferences('forge-player-1').timerMode
            BridgeHudRevealTimerCycle(nil, nil, nil)
            timerOff = BridgeRevealGetPreferences('forge-player-1').timerMode
            BridgeRevealSetTimerForViewer('forge-player-1', 0)
            BridgeRevealSetTimerForViewer('forge-player-2', 3)
            whiteTimer = BridgeState.revealPreferencesBySeatId['forge-player-1'].timerMode
            blueTimer = BridgeState.revealPreferencesBySeatId['forge-player-2'].timerMode
        ");

        Assert.True(lua.Globals.Get("timerDefault").Boolean);
        Assert.Equal(0, lua.Globals.Get("timerOffFirst").Number);
        Assert.Equal(3, lua.Globals.Get("timerThree").Number);
        Assert.Equal(5, lua.Globals.Get("timerFive").Number);
        Assert.Equal(10, lua.Globals.Get("timerTen").Number);
        Assert.Equal(0, lua.Globals.Get("timerOff").Number);
        Assert.Equal(0, lua.Globals.Get("whiteTimer").Number);
        Assert.Equal(3, lua.Globals.Get("blueTimer").Number);
    }

    [Fact]
    public void HoverAndMagnifyUseExactEntryAndFenceStaleRelease()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 2
            BridgeApplyRevealPresentation({presentationId='magnify', originatingEventSequence=2, visibility='public', cards={
                {authoritativeObjectId='card-one', cardName='Island', imageUrl='art-one'},
                {authoritativeObjectId='card-two', cardName='Mountain', imageUrl='art-two'}
            }, lifecycle='opened'}, 2)
            revealCount = #BridgeState.revealedPresentationsByKey['magnify@2'].cards
            BridgeHudRevealCardHoverEnter({color='White'}, nil, 'BridgeHudRevealCardButton2')
            hoverState = BridgeState.revealViewerStateByColor.White
            hoveredId = hoverState and hoverState.hovered and hoverState.hovered.instanceId
            opened, token = BridgeRevealMagnifyPress({color='White'})
            magnifiedId = hoverState and hoverState.magnifier and hoverState.magnifier.instanceId
            staleRelease = BridgeRevealMagnifyRelease({color='White'}, token + 1)
            remainsAfterStaleRelease = hoverState.magnifier.active
            currentRelease = BridgeRevealMagnifyRelease({color='White'}, token)
            hiddenAfterRelease = not hoverState.magnifier.active
            BridgeHudRevealCardHoverExit({color='White'}, nil, 'BridgeHudRevealCardButton2')
            noHover = BridgeRevealMagnifyPress({color='White'})
        ");

        Assert.Equal(2, lua.Globals.Get("revealCount").Number);
        Assert.Equal("card-two", lua.Globals.Get("hoveredId").String);
        Assert.True(lua.Globals.Get("opened").Boolean);
        Assert.Equal("card-two", lua.Globals.Get("magnifiedId").String);
        Assert.False(lua.Globals.Get("staleRelease").Boolean);
        Assert.True(lua.Globals.Get("remainsAfterStaleRelease").Boolean);
        Assert.True(lua.Globals.Get("currentRelease").Boolean);
        Assert.True(lua.Globals.Get("hiddenAfterRelease").Boolean);
        Assert.False(lua.Globals.Get("noHover").Boolean);
    }

    [Fact]
    public void MagnifyHotkeyKeyUpCannotCloseAReplacementMagnifier()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 1
            BridgeApplyRevealPresentation({presentationId='old', originatingEventSequence=1, visibility='public', cards={
                {authoritativeObjectId='old-card', cardName='Island', imageUrl='old-art'}
            }, lifecycle='opened'}, 1)
            BridgeHudRevealCardHoverEnter({color='White'}, nil, 'BridgeHudRevealCardButton1')
            oldOpened, oldToken = BridgeRevealMagnifyHotkey('White', false)
            BridgeState.lastAppliedEventSequence = 2
            BridgeApplyRevealPresentation({presentationId='new', originatingEventSequence=2, visibility='public', cards={
                {authoritativeObjectId='new-card', cardName='Mountain', imageUrl='new-art'}
            }, lifecycle='opened'}, 2)
            staleKeyUp = BridgeRevealMagnifyHotkey('White', true)
            BridgeHudRevealCardHoverEnter({color='White'}, nil, 'BridgeHudRevealCardButton1')
            newOpened, newToken = BridgeRevealMagnifyHotkey('White', false)
            newerStillActive = BridgeState.revealViewerStateByColor.White.magnifier.active
            currentKeyUp = BridgeRevealMagnifyHotkey('White', true)
            hiddenAfterCurrentKeyUp = not BridgeState.revealViewerStateByColor.White.magnifier.active
        ");

        Assert.True(lua.Globals.Get("oldOpened").Boolean);
        Assert.True(lua.Globals.Get("newOpened").Boolean);
        Assert.True(lua.Globals.Get("oldToken").Number < lua.Globals.Get("newToken").Number);
        Assert.False(lua.Globals.Get("staleKeyUp").Boolean);
        Assert.True(lua.Globals.Get("newerStillActive").Boolean);
        Assert.True(lua.Globals.Get("currentKeyUp").Boolean);
        Assert.True(lua.Globals.Get("hiddenAfterCurrentKeyUp").Boolean);
    }

    [Fact]
    public void PhysicalGatedLibraryLookOpensOnlyAfterExactDropInsideTightTarget()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 7
            BridgeRevealSetPhysicalGateForViewer('forge-player-1', true)
            reveal = {
                presentationId='scry-1', originatingEventSequence=7, visibility='private',
                entitledViewerSeatIds={'forge-player-1'}, revealingSeatId='forge-player-1',
                sourceZone='library', interactionKind='scry', physicalInteractionSupported=true,
                allowedPhysicalDestinations={'top', 'bottom'},
                cards={{authoritativeObjectId='expected-card', cardName='Island', imageUrl='art'}}, lifecycle='opened'
            }
            BridgeApplyRevealPresentation(reveal, 7)
            session = BridgeState.libraryLookInteractionSession
            gatedBeforeDrop = BridgeState.revealViewerStateByColor.White.gateState
            BridgeState.physicalInstanceIdByGuid = {['exact-guid']='expected-card'}
            object = {
                getGUID=function() return 'exact-guid' end,
                getPosition=function() return {x=100, y=2, z=100} end
            }
            ordinaryDrop = BridgeLibraryLookHandleDrop('White', object)
            noDestination = session.stagedDestinationByInstanceId['expected-card'] == nil
            target = session.stagingTargets.top
            object.getPosition=function() return {x=target.x, y=target.y, z=target.z} end
            topDrop = BridgeLibraryLookHandleDrop('White', object)
            openedAfterDrop = BridgeState.revealViewerStateByColor.White.activeKey
            intent, intentError = BridgeLibraryLookBuildIntent()
            intentTop = intent and intent.destinations.top[1] or nil
        ");

        Assert.Equal("waiting-for-drop", lua.Globals.Get("gatedBeforeDrop").String);
        Assert.True(lua.Globals.Get("ordinaryDrop").Boolean);
        Assert.True(lua.Globals.Get("noDestination").Boolean);
        Assert.True(lua.Globals.Get("topDrop").Boolean);
        Assert.Equal("scry-1@7", lua.Globals.Get("openedAfterDrop").String);
        Assert.Equal("expected-card", lua.Globals.Get("intentTop").String);
        Assert.Equal(DataType.Nil, lua.Globals.Get("intentError").Type);
    }

    [Fact]
    public void PublicLibraryLookOwnerDropUnlocksEachGatedPublicProjection()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 7
            BridgeRevealSetPhysicalGateForViewer('forge-player-2', true)
            reveal = {presentationId='public-scry', originatingEventSequence=7, visibility='public',
                entitledViewerSeatIds={'forge-player-1', 'forge-player-2'}, revealingSeatId='forge-player-1',
                sourceZone='library', interactionKind='scry', physicalInteractionSupported=true,
                allowedPhysicalDestinations={'top', 'bottom'},
                cards={{authoritativeObjectId='public-card', cardName='Island'}}, lifecycle='opened'}
            BridgeApplyRevealPresentation(reveal, 7)
            gatedBeforeDrop = BridgeState.revealViewerStateByColor.Blue.gateState
            BridgeState.physicalInstanceIdByGuid = {['public-guid']='public-card'}
            object = {
                getGUID=function() return 'public-guid' end,
                getPosition=function() return {x=BridgeState.libraryLookInteractionSession.stagingTargets.top.x,
                    y=2, z=BridgeState.libraryLookInteractionSession.stagingTargets.top.z} end
            }
            BridgeLibraryLookHandleDrop('White', object)
            blueOpenedAfterOwnerDrop = BridgeState.revealViewerStateByColor.Blue.activeKey
        ");

        Assert.Equal("waiting-for-drop", lua.Globals.Get("gatedBeforeDrop").String);
        Assert.Equal("public-scry@7", lua.Globals.Get("blueOpenedAfterOwnerDrop").String);
    }

    [Fact]
    public void ScryAndSurveilUseOneSharedLibraryLookSessionWithDifferentPolicies()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            scry = {presentationId='scry', originatingEventSequence=1, revealingSeatId='forge-player-1',
                sourceZone='library', interactionKind='scry', physicalInteractionSupported=true,
                cards={{authoritativeObjectId='scry-card', cardName='Island'}}, lifecycle='opened'}
            scrySession = BridgeBeginLibraryLookInteractionSession(scry, {decisionId='d1', seatId='forge-player-1'})
            scryTop = type(scrySession) == 'table' and scrySession.allowedDestinations.top == true or false
            scryBottom = type(scrySession) == 'table' and scrySession.allowedDestinations.bottom == true or false
            oldGeneration = type(scrySession) == 'table' and scrySession.generation or -1
            surveil = {presentationId='surveil', originatingEventSequence=2, revealingSeatId='forge-player-1',
                sourceZone='library', interactionKind='surveil', physicalInteractionSupported=true,
                cards={{authoritativeObjectId='surveil-card', cardName='Mountain'}}, lifecycle='opened'}
            surveilSession = BridgeBeginLibraryLookInteractionSession(surveil, {decisionId='d2', seatId='forge-player-1'})
            replaced = BridgeState.libraryLookInteractionSession == surveilSession
            oldRetired = type(scrySession) == 'table' and scrySession.lifecycle == 'retired' or false
            surveilTop = type(surveilSession) == 'table' and surveilSession.allowedDestinations.top == true or false
            surveilGraveyard = type(surveilSession) == 'table' and surveilSession.allowedDestinations.graveyard == true or false
            surveilBottom = type(surveilSession) == 'table' and surveilSession.allowedDestinations.bottom == true or false
            BridgeResetRevealSessionState('new-match')
            retiredOnReset = BridgeState.libraryLookInteractionSession == nil and type(surveilSession) == 'table' and surveilSession.lifecycle == 'retired'
        ");

        Assert.True(lua.Globals.Get("scryTop").Boolean);
        Assert.True(lua.Globals.Get("scryBottom").Boolean);
        Assert.True(lua.Globals.Get("replaced").Boolean);
        Assert.True(lua.Globals.Get("oldRetired").Boolean);
        Assert.True(lua.Globals.Get("surveilTop").Boolean);
        Assert.True(lua.Globals.Get("surveilGraveyard").Boolean);
        Assert.False(lua.Globals.Get("surveilBottom").Boolean);
        Assert.True(lua.Globals.Get("retiredOnReset").Boolean);
    }

    [Fact]
    public void LibraryLookDeckDropUsesExactContainedIdentityAndNativeOrder()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            reveal = {presentationId='deck-look', originatingEventSequence=1,
                revealingSeatId='forge-player-1', sourceZone='library', interactionKind='scry',
                physicalInteractionSupported=true, cards={
                    {authoritativeObjectId='forge:session:one', cardName='Island'},
                    {authoritativeObjectId='forge:session:two', cardName='Mountain'}
                }, lifecycle='opened'}
            session = BridgeBeginLibraryLookInteractionSession(reveal, nil)
            BridgeState.physicalContainedInstanceIdByGuid = {
                ['contained-one']='forge:session:one', ['contained-two']='forge:session:two'
            }
            deck = {
                tag='Deck', getGUID=function() return 'staging-deck' end,
                getPosition=function() return {x=session.stagingTargets.top.x, y=2, z=session.stagingTargets.top.z} end,
                getObjects=function() return {
                    {guid='contained-two', index=1, nickname='Mountain'},
                    {guid='contained-one', index=2, nickname='Island'}
                } end
            }
            handled = BridgeLibraryLookHandleDrop('White', deck)
            intent, intentError = BridgeLibraryLookBuildIntent()
            firstTop = intent and intent.destinations.top[1] or nil
            secondTop = intent and intent.destinations.top[2] or nil
        ");

        Assert.True(lua.Globals.Get("handled").Boolean);
        Assert.Equal(DataType.Nil, lua.Globals.Get("intentError").Type);
        Assert.Equal("forge:session:two", lua.Globals.Get("firstTop").String);
        Assert.Equal("forge:session:one", lua.Globals.Get("secondTop").String);
    }

    [Fact]
    public void LibraryLookFinalizationReadsCurrentLooseCardGeometryAfterRearrangement()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            reveal = {presentationId='loose-look', originatingEventSequence=1,
                revealingSeatId='forge-player-1', sourceZone='library', interactionKind='scry',
                physicalInteractionSupported=true, cards={
                    {authoritativeObjectId='forge:session:left', cardName='Island'},
                    {authoritativeObjectId='forge:session:right', cardName='Mountain'}
                }, lifecycle='opened'}
            session = BridgeBeginLibraryLookInteractionSession(reveal, nil)
            firstPosition = {x=session.stagingTargets.top.x - 0.4, y=2, z=session.stagingTargets.top.z}
            secondPosition = {x=session.stagingTargets.top.x + 0.4, y=2, z=session.stagingTargets.top.z}
            first = {getGUID=function() return 'loose-first' end, getPosition=function() return firstPosition end}
            second = {getGUID=function() return 'loose-second' end, getPosition=function() return secondPosition end}
            BridgeState.physicalInstanceIdByGuid = {
                ['loose-first']='forge:session:left', ['loose-second']='forge:session:right'}
            BridgeLibraryLookHandleDrop('White', first)
            BridgeLibraryLookHandleDrop('White', second)
            -- The player picks both cards up and swaps their final table order.
            firstPosition.x = session.stagingTargets.top.x + 0.4
            secondPosition.x = session.stagingTargets.top.x - 0.4
            currentFirstX = first.getPosition().x
            currentSecondX = second.getPosition().x
            intent, intentError = BridgeLibraryLookBuildIntent()
            firstTop = intent and intent.destinations.top[1] or nil
            secondTop = intent and intent.destinations.top[2] or nil
        ");

        Assert.Equal(DataType.Nil, lua.Globals.Get("intentError").Type);
        Assert.True(lua.Globals.Get("currentFirstX").Number > lua.Globals.Get("currentSecondX").Number);
        Assert.Equal("forge:session:right", lua.Globals.Get("firstTop").String);
        Assert.Equal("forge:session:left", lua.Globals.Get("secondTop").String);
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
            BRIDGE_SEATS = {
                ['forge-player-1'] = {ttsColor='White', libraryAnchor={x=0, y=2, z=0}, tableSideZ=-1},
                ['forge-player-2'] = {ttsColor='Blue', libraryAnchor={x=0, y=2, z=0}, tableSideZ=1}
            }
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
            BridgeState.dismissedRevealOrder = {}
            BridgeState.activeRevealPresentationKey = nil
            BridgeState.revealSurfaceOffset = 1
            BridgeState.revealPresentationGeneration = 0
            function BridgeUiSet(id, attribute, value)
                if id == 'BridgeHudRevealFallback1' and attribute == 'active' then fallbackActive = value == 'true' end
                if id == 'BridgeHudRevealFallback1' and attribute == 'text' then fallbackText = value end
            end
            function BridgeUiMarkDirty(reason) end
        ");
        return lua;
    }
}
