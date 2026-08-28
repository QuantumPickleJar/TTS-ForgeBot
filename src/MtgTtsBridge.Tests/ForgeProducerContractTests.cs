namespace MtgTtsBridge.Tests;

public sealed class ForgeProducerContractTests
{
    private static readonly string RepositoryRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
    private static readonly string Patch = File.ReadAllText(Path.Combine(RepositoryRoot, "tools", "forge", "bridge-headless.patch"));
    private static readonly string Bootstrap = File.ReadAllText(Path.Combine(RepositoryRoot, "tools", "forge", "bootstrap.ps1"));
    private static readonly string Launcher = File.ReadAllText(Path.Combine(RepositoryRoot, "tools", "Start-ForgeBot.ps1"));

    [Fact]
    public void TrackedBridgeStateFeed_EmitsTheStructuredCharacteristicAndPlayerContract()
    {
        Assert.Contains("\"currentPower\"", Patch);
        Assert.Contains("\"currentToughness\"", Patch);
        Assert.Contains("\\\"currentTypes\\\"", Patch);
        Assert.Contains("\"ownerSeatId\"", Patch);
        Assert.Contains("\"controllerSeatId\"", Patch);
        Assert.Contains("\"tapped\"", Patch);
        Assert.Contains("\\\"counters\\\"", Patch);
        Assert.Contains("\\\"keywords\\\"", Patch);
        Assert.Contains("\"speed\"", Patch);
        Assert.Contains("\\\"designations\\\"", Patch);
        Assert.Contains("\"monarchSeatId\"", Patch);
        Assert.Contains("ZoneType.Command", Patch);
    }

    [Fact]
    public void TrackedBridgeStateFeed_UsesADirtyGenerationInsteadOfLossyOneShotCoalescing()
    {
        Assert.Contains("AtomicLong mutationGeneration", Patch);
        Assert.Contains("mutationGeneration.incrementAndGet()", Patch);
        Assert.Contains("if (mutationGeneration.get() != generation)", Patch);
        Assert.Contains("ThreadUtil.delay(25, this::emitWhenStable)", Patch);
        Assert.Contains("trace(\"event=\"", Patch);
        Assert.Contains("battlefieldSummary()", Patch);
    }

    [Fact]
    public void TrackedBridgeStateFeed_UsesOnlyTheCompleteCombatSnapshotForBlockers()
    {
        Assert.Contains("GameEventBlockersDeclared", Patch);
        Assert.Contains("not an exact blocker identity", Patch);
        Assert.Contains("sole authoritative source for presentation", Patch);
        Assert.Contains("\\\"blockerForgeObjectIds\\\"", Patch);
        Assert.Contains("combat.getBlockers(attacker)", Patch);
        Assert.DoesNotContain("emitBlockerDeclarations", Patch);
        Assert.DoesNotContain("+++ Block: ", Patch);
    }

    [Fact]
    public void TrackedBridgeStateFeed_EmitsEmptyCombatDuringNewMatchStartup()
    {
        Assert.Contains("json.append(\"],\\\"combat\\\":\");", Patch);
        Assert.Contains("if (combat == null)", Patch);
        Assert.Contains("json.append(\"]}\");", Patch);
    }

    [Fact]
    public void TrackedTuiProducer_ExposesEnumeratedCreatureTypeChoices()
    {
        Assert.Contains("chooseSomeType(String kindOfType", Patch);
        Assert.Contains("creature_type_selection", Patch);
        Assert.Contains("new ArrayList<>(validTypes)", Patch);
        Assert.Contains("if (isOptional) types.add(0, \"None\")", Patch);
    }

    [Fact]
    public void TrackedTuiProducer_EmitsForgeDerivedActionProvenance()
    {
        Assert.Contains("bridgeChoiceMetadata", Patch);
        Assert.Contains("sourceZone=", Patch);
        Assert.Contains("getCastableSpellsFromZone(ZoneType.Graveyard", Patch);
        Assert.Contains("getZone().getZoneType()", Patch);
        Assert.Contains("getKeyword().getKeyword()", Patch);
        Assert.Contains("getAlternativeCost()", Patch);
    }

    [Fact]
    public void HumanCostChoicesAndDiscardProvenanceRemainForgeProduced()
    {
        Assert.Contains("chooseCardsForCost(CardCollectionView optionList", Patch);
        Assert.Contains("chooseEntitiesThroughTui(kind, optionList", Patch);
        Assert.Contains("costKind = sa != null && sa.isCrew() ? \"crew\" : \"total_power\"", Patch);
        Assert.Contains("requiredTotalPower(tapCost)", Patch);
        Assert.Contains("CardPredicates.CAN_CREW", Patch);
        Assert.Contains("emitDiscardDecisionMetadata", Patch);
        Assert.Contains("decisionCause=", Patch);
        Assert.Contains("sourceCardId=", Patch);
        Assert.Contains("sourceCardName=", Patch);
        Assert.Contains("emitDiscardDecisionMetadata(null, \"cleanup_hand_size\")", Patch);
        Assert.Contains("Discard to maximum hand size", Patch);
    }

    [Fact]
    public void DelveAndMulliganRemainNativeForgeControllerTransactions()
    {
        Assert.Contains("chooseCardsToDelve(int genericAmount, CardCollection grave)", Patch);
        Assert.Contains("costKind=delve sourceZone=graveyard", Patch);
        Assert.Contains("mulliganKeepHand(Player firstPlayer, int cardsToReturn)", Patch);
        Assert.Contains("mulliganStage=keep_or_mulligan", Patch);
        Assert.Contains("tuckCardsViaMulligan(CardCollectionView hand, int cardsToReturn)", Patch);
        Assert.Contains("mulliganStage=bottom_selection sourceZone=hand", Patch);
        Assert.Contains("MulliganService owns the mulligan rule", Patch);
    }

    [Fact]
    public void HumanPriorityUsesForgeLegalityAndAutoPassesOnlyEmptyWindows()
    {
        Assert.Contains("List<SpellAbility> landAbilities = getPlayableLands();", Patch);
        Assert.Contains("getCastableCreaturesAndArtifacts(true)", Patch);
        Assert.Contains("auto-passing empty human priority window", Patch);
        Assert.Contains("sa.setActivatingPlayer(player);", Patch);
        Assert.Contains("sa.isLandAbility() && sa.canPlay()", Patch);
        Assert.DoesNotContain("boolean sorcerySpeedWindow", Patch);
        Assert.Contains("} else if (totalActions == 0) {", Patch);
    }

    [Fact]
    public void PrototypeActionsExposeTypedCastModeAndBothLegalAbilities()
    {
        Assert.Contains("boolean prototypeSpell", Patch);
        Assert.Contains("castMode = preparedSpell ? \"prepare\" : prototypeSpell ? \"prototype\"", Patch);
        Assert.Contains("prototypePower=", Patch);
        Assert.Contains("prototypeToughness=", Patch);
        Assert.Contains("bridgeDisplayedManaCost", Patch);
        Assert.Contains("sa.getPayCosts().toString()", Patch);
        Assert.Contains("Keep every legal ability", Patch);
    }

    [Fact]
    public void ProliferateEntitiesExposeExactCardInstancesAndPlayerSeats()
    {
        Assert.Contains("bridgeEntityMetadata", Patch);
        Assert.Contains("String entityKind = zone == ZoneType.Battlefield ? \"permanent\" : \"card\"", Patch);
        Assert.Contains("entityKind=\" + entityKind + \" cardInstanceId=", Patch);
        Assert.Contains("entityKind=player seatId=forge-player-", Patch);
        Assert.Contains("selectionKind=proliferate", Patch);
        Assert.Contains("ApiType.Proliferate", Patch);
        Assert.Contains("chooseEntitiesForEffect", Patch);
    }

    [Fact]
    public void PrototypeDesignationIsAuthoritativeAndSeparateFromKeywords()
    {
        Assert.Contains("isPrototyped()", Patch);
        Assert.Contains("string(json, \"prototyped\")", Patch);
        Assert.Contains("json.append(\"\\\"cardDesignations\\\":[\");", Patch);
    }

    [Fact]
    public void NumericBlockerMenusEnumerateOnlyForgeLegalRelationshipsIncludingTokens()
    {
        Assert.Contains("List<Card> legalBlockers = new ArrayList<>()", Patch);
        Assert.Contains("CombatUtil.canBlock(attacker, candidate, combat)", Patch);
        Assert.Contains("for (int i = 0; i < legalBlockers.size(); i++)", Patch);
        Assert.Contains("getIntInput(0, legalBlockers.size())", Patch);
        Assert.Contains("Card blocker = legalBlockers.get(choice - 1)", Patch);
        Assert.Contains("blockerForCardId=", Patch);
        Assert.Contains("blockerForName=", Patch);
    }

    [Fact]
    public void ForgeBuildStamp_BindsJarToPatchAndUpstreamCommit()
    {
        Assert.Contains("forge-headless-bridge-build.json", Bootstrap);
        Assert.Contains("Skipping patch application because Forge has local bridge changes", Bootstrap);
        Assert.Contains("if ($hasLocalChanges)", Bootstrap);
        Assert.Contains("bridgePatchSha256", Bootstrap);
        Assert.Contains("upstreamForgeCommit", Bootstrap);
        Assert.Contains("jarSha256", Bootstrap);
        Assert.Contains("patchedSourceSha256", Bootstrap);
        Assert.Contains("bridgePatchSha256", Launcher);
        Assert.Contains("patchedSourceSha256", Launcher);
        Assert.Contains("BridgeStateFeed source is newer than the assembled JAR", Launcher);
    }
}
