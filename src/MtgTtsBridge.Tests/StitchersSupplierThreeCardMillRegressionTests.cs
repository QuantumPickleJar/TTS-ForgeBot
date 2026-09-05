using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class StitchersSupplierThreeCardMillRegressionTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void StitchersSupplierThreeCardMillConvergesThroughNativeDeck()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local stage=1
            local deck={tag='Deck',getGUID=function() return 'grave-deck' end}
            deck.getObjects=function()
                if stage==1 then return {{guid='old-9',nickname='Stitcher',index=1}} end
                if stage==2 then return {{guid='new-9',nickname='Stitcher',index=1},{guid='new-35',nickname='Scour',index=2}} end
                if stage==3 then return {{guid='final-9',nickname='Stitcher',index=1},{guid='final-35',nickname='Scour',index=2},{guid='final-17',nickname='Island',index=3}} end
                return {{guid='armored-9',nickname='Stitcher',index=1},{guid='armored-35',nickname='Scour',index=2},{guid='armored-17',nickname='Island',index=3},{guid='armored-37',nickname='Baleful Strix',index=4}}
            end
            deck.putObject=function(object,position)
                stage=stage+1
                return deck
            end
            local c2={tag='Card',name='Scour',getGUID=function() return 'loose-35' end,setPositionSmooth=function() end,setLock=function() end}
            local c3={tag='Card',name='Island',getGUID=function() return 'loose-17' end,setPositionSmooth=function() end,setLock=function() end}
            local c4={tag='Card',name='Baleful Strix',getGUID=function() return 'loose-37' end,setPositionSmooth=function() end,setLock=function() end}
            function getAllObjects() return {deck} end
            function getObjectFromGUID(guid) if guid=='grave-deck' then return deck end return nil end
            function BridgeFindGraveyardContainer(seatId,excludeGuid) return deck end
            function BridgeWaitFrames(callback,frames) callback() end
            BRIDGE_SEATS['forge-player-1']={graveyardAnchor={x=0,y=0,z=0}}
            BridgeGraveyardPosition=function() return {x=0,y=0,z=0} end
            BridgeSetPhysicalFaceDown=function() end
            BridgeRetirePendingCastForInstance=function() end
            BridgeClearCardDesignationPresentation=function() end
            BridgeAssertGraveyardObjectShape=function() return true,nil end
            BridgeState.eventSessionId='supplier-session'
            BridgeState.physicalTransactionGeneration=1
            BridgeState.cardNameByInstanceId[':9']='Stitcher'
            BridgeState.cardNameByInstanceId[':35']='Scour'
            BridgeState.cardNameByInstanceId[':17']='Island'
            BridgeState.cardNameByInstanceId[':37']='Baleful Strix'
            BridgeRecordLooseCardIdentity(':9','old-9','forge-player-1','graveyard')
            local e2={sequence=188,seatId='forge-player-1',cardInstanceId=':35',cardName='Scour',destinationZone='graveyard'}
            local e3={sequence=189,seatId='forge-player-1',cardInstanceId=':17',cardName='Island',destinationZone='graveyard'}
            local e4={sequence=190,seatId='forge-player-1',cardInstanceId=':37',cardName='Baleful Strix',destinationZone='graveyard'}
            ok2,reason2=BridgeMoveToGraveyard(e2,c2,function(ok,reason) done2=ok; callback2=reason end)
            ok3,reason3=BridgeMoveToGraveyard(e3,c3,function(ok,reason) done3=ok; callback3=reason end)
            ok4,reason4=BridgeMoveToGraveyard(e4,c4,function(ok,reason) done4=ok; callback4=reason end)
            deckCount=#deck.getObjects()
        ");
        Assert.True(lua.Globals.Get("ok2").Boolean, lua.Globals.Get("reason2").ToPrintString());
        Assert.True(lua.Globals.Get("ok3").Boolean, lua.Globals.Get("reason3").ToPrintString());
        Assert.True(lua.Globals.Get("done2").Boolean, lua.Globals.Get("callback2").ToPrintString());
        Assert.True(lua.Globals.Get("done3").Boolean, lua.Globals.Get("callback3").ToPrintString());
        Assert.True(lua.Globals.Get("ok4").Boolean, lua.Globals.Get("reason4").ToPrintString());
        Assert.True(lua.Globals.Get("done4").Boolean, lua.Globals.Get("callback4").ToPrintString());
        Assert.Equal(4, lua.Globals.Get("BridgeState").Table.Get("physicalContainerByInstanceId").Table.Keys.Count());
        Assert.Equal(4, lua.Globals.Get("deckCount").Number);
    }

    [Fact]
    public void DuplicatePrintedNamesStillUseExactContainedIdentity()
    {
        var lua=NewProbe();
        lua.DoString(@"
            local deck={tag='Deck',getGUID=function() return 'grave-deck' end,getObjects=function() return {{guid='a',nickname='Forest',index=1},{guid='b',nickname='Forest',index=2}} end}
            function getObjectFromGUID(guid) if guid=='grave-deck' then return deck end return nil end
            BridgeState.eventSessionId='duplicate-session'
            BridgeRecordContainedCardIdentity(':100','grave-deck','a','forge-player-1','graveyard','Forest')
            BridgeRecordContainedCardIdentity(':101','grave-deck','b','forge-player-1','graveyard','Forest')
            verified100,error100=BridgeVerifyFinalPhysicalRepresentation(':100','forge-player-1','graveyard')
            verified101,error101=BridgeVerifyFinalPhysicalRepresentation(':101','forge-player-1','graveyard')
        ");
        Assert.True(lua.Globals.Get("verified100").Boolean, lua.Globals.Get("error100").ToPrintString());
        Assert.True(lua.Globals.Get("verified101").Boolean, lua.Globals.Get("error101").ToPrintString());
    }

    [Fact]
    public void UnstableSettlementFailsAfterBoundedObservations()
    {
        var lua=NewProbe();
        lua.DoString(@"
            local n=0
            local deck={tag='Deck',getGUID=function() return 'unstable-deck' end}
            deck.getObjects=function() n=n+1; return {{guid='unstable-'..tostring(n),index=1}} end
            function BridgeWaitFrames(callback,frames) callback() end
            settled,settleError=nil,nil
            BridgeVerifyGraveyardDeckSettlement(deck,4,function(ok,reason) settled=ok; settleError=reason end)
        ");
        Assert.False(lua.Globals.Get("settled").Boolean);
        Assert.Contains("did not stabilize", lua.Globals.Get("settleError").String);
    }

    private static Script NewProbe()
    {
        var lua=new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message,color) end
            function printToAll(message,color) end
            function getObjectFromGUID(guid) return nil end
            function getAllObjects() return {} end
            function Wait(frames) end
            Time={waitForSeconds=function(seconds,callback) callback() end}
            JSON={encode=function(value) return '{}' end,decode=function(value) return {} end}
            os={time=function() return 1 end,clock=function() return 0 end}
            table.concat=function(values,separator) local result=''; for index,value in ipairs(values) do if index>1 then result=result..separator end; result=result..tostring(value) end; return result end
        ");
        lua.DoString(Script);
        lua.DoString(@"
            function BridgeStopOnDesync(reason) desyncReason=reason end
            function BridgeScheduleSnapshotReconcile(reason,category) end
            function BridgeTryPresentPendingDecision(reason) end
            function BridgeTryApplyDeferredSnapshotReconcile(reason) end
            function BridgeTryStartPendingSnapshotReconcile(reason) end
            function BridgeRefreshDecisionAfterStateTransition(reason) end
            function BridgeShouldReconcileAfterEvent(event) return false end
            BridgeState.eventSessionId='probe-session'
            BridgeState.eventSessionGeneration=1
            BridgeState.physicalTransactionGeneration=1
            BridgeState.physicalByInstanceId={}
            BridgeState.physicalInstanceIdByGuid={}
            BridgeState.physicalContainerByInstanceId={}
            BridgeState.physicalContainedInstanceIdByGuid={}
            BridgeState.physicalSeatByGuid={}
            BridgeState.physicalZoneByGuid={}
            BridgeState.cardNameByInstanceId={}
            BridgeState.zoneAnchorGuidBySeatAndZone={}
        ");
        return lua;
    }
}
