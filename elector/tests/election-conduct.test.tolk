import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "test-utils"
import "../contracts/types"
import "../wrappers/Elector.gen"
import "../wrappers/utils"

/// Test that elections don't finish before close time
get fun `test elections ongoing`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.activeElectionId();
    expect(stakeAt).toNotEqual(0);

    // Submit enough stakes for a valid election
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");
    var totalStake: coins = 0;
    var i = 0;
    while (i < 5) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        totalStake += stake;
        i += 1;
    }

    val (
        _,
        closeAt,
        _,
        _,
        _,
        _,
        _,
    ) = elector.participantListExtended();

    // Set time BEFORE close — elections should NOT finish
    testing.setNow(closeAt - 1);
    testing.runTickTock(elector.address, true);

    val (
        _,
        _,
        _,
        _,
        _,
        isFailed1,
        isFinished1,
    ) = elector.participantListExtended();
    expect(isFailed1).toEqual(false);
    expect(isFinished1).toEqual(false);

    // Now advance past close — elections should finish
    testing.setNow(closeAt + 1);
    testing.runTickTock(elector.address, true);

    val (
        _,
        _,
        _,
        _,
        _,
        isFailed2,
        isFinished2,
    ) = elector.participantListExtended();
    expect(isFailed2).toEqual(false);
    expect(isFinished2).toEqual(true);
}

// TODO: test elections no config — config.delete(0) doesn't seem to remove param from emulator
// Skipping until we find how to remove a config param in the emulator

/// Test that elections fail with fewer than minValidators participants
get fun `test election less min participants`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Submit only 2 validators (minValidators is 5)
    // Each needs to stake enough that total >= minTotalStake so we get to tryElect
    var totalStake: coins = 0;
    val bigStake: coins = ton("1000000"); // 1M TON each, total 2M
    var i = 0;
    while (i < 2) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake, bigStake);
        totalStake += stake;
        i += 1;
    }

    val (
        _,
        closeAt,
        _,
        _,
        _,
        _,
        _,
    ) = elector.participantListExtended();
    testing.setNow(closeAt + 1);

    // Tick-tock — elections should fail (not enough validators)
    // tryElect returns count=0 when n < minValidators, so isFailed=true
    testing.runTickTock(elector.address, true);
    val (
        _,
        _,
        _,
        _,
        _,
        isFailed1,
        isFinished1,
    ) = elector.participantListExtended();
    expect(isFailed1).toEqual(true);
    expect(isFinished1).toEqual(false);

    // Add more validators to meet minimum (need 3 more for total of 5)
    while (i < 5) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake, bigStake);
        totalStake += stake;
        i += 1;
    }

    // Tick-tock again — elections should now succeed (new stake arrived, isFailed reset)
    testing.runTickTock(elector.address, true);
    val (
        _,
        _,
        _,
        _,
        _,
        isFailed2,
        isFinished2,
    ) = elector.participantListExtended();
    expect(isFailed2).toEqual(false);
    expect(isFinished2).toEqual(true);
}

/// Test that elections are postponed when total stake is below minTotalStake
get fun `test election less min total stake`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Submit 5 validators with small stakes (below minTotalStake of 2M TON)
    // conductElections checks totalStake < minTotalStake BEFORE calling tryElect
    // and returns postponeElections() — no state change (not failed, not finished)
    val smallStake: coins = ton("50000"); // 50K each = 250K total, well below 2M
    var totalStake: coins = 0;
    var i = 0;
    while (i < 5) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake, smallStake);
        totalStake += stake;
        i += 1;
    }

    val (
        _,
        closeAt,
        _,
        tStake,
        _,
        _,
        _,
    ) = elector.participantListExtended();
    assert (tStake < defaultStakeLimits().minTotalStake) throw 100; // confirm below minTotalStake
    testing.setNow(closeAt + 1);

    // Tick-tock — elections should NOT finish or fail (just postponed)
    testing.runTickTock(elector.address, true);
    val (
        _,
        _,
        _,
        _,
        _,
        isFailed1,
        isFinished1,
    ) = elector.participantListExtended();
    expect(isFailed1).toEqual(false);
    expect(isFinished1).toEqual(false);
}

/// Test that effective stake (after maxStakeFactor cap) can be below minTotalStake
/// even when nominal totalStake exceeds it
get fun `test true stake less min total stake`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Strategy: 5 validators with enough nominal total >= minTotalStake
    // but with low maxFactor so effective/true stake < minTotalStake.
    //
    // maxStakeFactor from config = (27 << 16) / 10 ≈ 176947 (2.7 in fixed-point)
    // Each validator maxFactor = 1.5 (from submitValidStake) = 0x18000
    // trueStake[i] = min(stake[i], (maxFactor[i] * mStake) >> 16)
    //
    // If 1 fat cat has 1.8M and 4 small have minStake (~10K), mStake = 10K
    // trueStake for fat cat = min(1.8M, 1.5 * 10K) = 15K
    // total true stake = 15K + 4*10K = 55K << 2M = FAILS
    //
    // But we need nominal total >= 2M. 1.8M + 4*10K = 1.84M < 2M. Not enough.
    // Let's use 1 fat cat at 1.96M and 4 small at 11K each.
    // Nominal = 1.96M + 44K = 2.004M >= 2M ✓
    // mStake = min(11K, maxStake=500K) = 11K
    // trueStake for fat cat = min(min(1.96M, 500K), 1.5*11K) = min(500K, 16.5K) = 16.5K
    // total true = 16.5K + 4*11K = 60.5K < 2M → FAIL ✓
    val stakeLimits = defaultStakeLimits();

    val fatStake: coins = ton("1960000");
    val (_, _, _, _, _) = submitValidStake(elector, 0, fatStake);

    val smallStake: coins = stakeLimits.minStake + ton("1000");
    var totalNominal: coins = fatStake;
    var i = 0;
    while (i < 4) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalNominal, smallStake);
        totalNominal += stake;
        i += 1;
    }

    val (
        _,
        closeAt,
        _,
        tStake,
        _,
        _,
        _,
    ) = elector.participantListExtended();
    // Verify nominal total >= minTotalStake
    assert (tStake >= stakeLimits.minTotalStake) throw 100;
    testing.setNow(closeAt + 1);

    testing.runTickTock(elector.address, true);
    val (
        _,
        _,
        _,
        _,
        _,
        isFailed,
        isFinished,
    ) = elector.participantListExtended();

    // Elections should fail: tryElect returns count=0 because bestStake < minTotalStake
    expect(isFailed).toEqual(true);
    expect(isFinished).toEqual(false);
}

/// Test full successful election cycle
get fun `test successful elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.activeElectionId();
    expect(stakeAt).toNotEqual(0);

    // Conduct elections
    conductValidElections(elector);

    // Check elections finished
    val (
        electAt,
        _,
        _,
        _,
        _,
        isFailed,
        isFinished,
    ) = elector.participantListExtended();
    expect(electAt).toNotEqual(0);
    expect(isFailed).toEqual(false);
    expect(isFinished).toEqual(true);
    expect(electAt).toEqual(stakeAt);
}
