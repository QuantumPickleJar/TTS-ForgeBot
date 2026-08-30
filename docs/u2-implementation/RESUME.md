# U2 Resume Quick-Start

⚠️ **READ U2-ADDENDUM-REQUIREMENTS.md FIRST** ⚠️

**Current Status**: Paused. Addendum requirements added. Implementation blockers identified.

## Where You Are

- ✅ U2-A contracts complete (338 tests passing)
- ✅ Rebased onto latest main @ 9fecfef
- ✅ Forge producer design complete
- ⚠️ **ADDENDUM REQUIREMENTS ADDED** - See U2-ADDENDUM-REQUIREMENTS.md
- 🚨 **IMPLEMENTATION BLOCKERS IDENTIFIED** - Must resolve before proceeding
- 📋 Ready to implement ~280 lines AFTER resolving blockers

## Resume Commands

⚠️ **STOP: Read U2-ADDENDUM-REQUIREMENTS.md before implementing** ⚠️

Critical blockers must be resolved first:
1. SpellAbility identity stability (may need alternative to IdentityHashMap)
2. Loyalty/Defense semantic clarification (base value vs counter quantity)

```bash
cd C:\Users\vmorr\Documents\code\tts-forgebot\TTS-ForgeBot-U2

# Read addendum requirements FIRST
cat docs/u2-implementation/U2-ADDENDUM-REQUIREMENTS.md

# Verify clean state
git status

# Check current tests
dotnet test --filter "U2Provenance"
```

## Implementation Path

**Follow**: `files/u2-forge-producer-implementation-guide.md`

**Summary of 4 parts** (~2-3 hours work):
1. Payment context tracking (PlayerControllerTUI fields + helpers)
2. Cost components emission (helper methods + metadata output)
3. Complete characteristics (BridgeStateFeed appendCharacteristics helper)
4. Characteristic change events (event emission method + trigger)

**Target file**: `tools/forge/bridge-headless.patch`

## After Implementation

1. Mark Forge producer todos done (SQL query in guide)
2. Move to bridge parser phase (3 todos)
3. Then behavioral tests (3 todos)
4. Then live canaries (6 todos)
5. Finally validation & compatibility

## Key Resources

- **Implementation Guide**: files/u2-forge-producer-implementation-guide.md (17KB, detailed steps)
- **Design Doc**: checkpoints/002-u2-forge-producer-design.md (architecture & rationale)
- **Plan**: plan.md (overall progress tracking)
- **Todo Tracking**: SQL database (18 todos, 4 in_progress, 14 pending)

## Quick Check Before Starting

```bash
# Verify latest state
git log --oneline -3
# Should show: 5c41d9c fix: update combat selection test pattern

# Verify tests pass
dotnet test
# Should show: 338 passed

# Check session files
ls ~/.copilot/session-state/d4b01a68-e1fc-494d-8feb-b4d310b00fdb/files/
# Should show: u2-forge-producer-implementation-guide.md
```

## Contact Points

If implementation reveals Forge API issues not covered in guide:
- Check actual Forge source at .deps/forge-source/ (if exists)
- Consult existing patch patterns for similar operations
- Document deviation and adjust parser expectations accordingly

## Success Criteria

After this implementation session:
- [ ] ~280 lines added to bridge-headless.patch
- [ ] Manual test shows new metadata in Forge TUI output
- [ ] Bridge tests still pass (338)
- [ ] Single commit with comprehensive message (template in guide)
- [ ] 4 Forge producer todos marked done
- [ ] 3 bridge parser todos now unblocked

**Estimated Time**: 2-3 hours (implementation + testing)
**Credit Budget**: Medium (substantial Java work + testing cycles)
