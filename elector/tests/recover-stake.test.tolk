import "@acton/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "test-utils"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Elector"

/// Test that recover stake is rejected from basechain
get fun `test recover stake not mc`() {
    val setup = setupElector();
    val elector = setup.elector;

    // Create addresses with same hash on different workchains
    val mcAddr = randomAddress("recoverer", MASTERCHAIN);
    val (_, addrHash) = mcAddr.getWorkchainAndHash();
    val bcAddr = beginCell()
        .storeUint(4, 3)
        .storeInt(BASECHAIN, 8)
        .storeUint(addrHash, 256)
        .endCell()
        .beginParse()
        .loadAddress();

    testing.topUp(bcAddr, ton("10"));
    testing.topUp(mcAddr, ton("10"));

    // From basechain — should be rejected (response with 0xfffffffe)
    val res1 = elector.sendRecoverStakeRequest(bcAddr, 1, { value: ton("1") });
    expect(res1).toHaveTx({
        from: elector.address,
        to: bcAddr,
        opcode: 0xfffffffe,
    });

    // From masterchain — no credits, but should also return error (no credit found)
    val res2 = elector.sendRecoverStakeRequest(mcAddr, 1, { value: ton("1") });
    expect(res2).toHaveTx({
        from: elector.address,
        to: mcAddr,
        opcode: 0xfffffffe,
    });
}

/// Test that recover stake returns credited amounts after elections
get fun `test recover stake credits`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Set maxValidators=5 so that extra validators get their full stake credited
    var config = testing.getConfig();
    config.setParamRaw(
        16,
        ValidatorLimits {
            maxValidators: 5,
            maxMainValidators: 5,
            minValidators: 5,
        }.toCell(),
    );
    testing.setConfig(config);

    // Submit 6 validators — maxValidators=5 so the 6th gets credited back
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");
    var totalStake: coins = 0;
    var i = 0;
    var extraSrcAddr = randomAddress("placeholder", MASTERCHAIN);
    while (i < 6) {
        val (_, srcAddr, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        totalStake += stake;
        if (i == 5) {
            extraSrcAddr = srcAddr;
        }
        i += 1;
    }
    val (_, extraSrcHash) = extraSrcAddr.getWorkchainAndHash();

    // Advance past close and conduct elections
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
    testing.runTickTock(elector.address, true);

    // Extra staker should have credits (not selected, full stake returned)
    val credited = elector.computeReturnedStake(extraSrcHash);
    assert (credited > 0) throw 100;

    // Recover the stake
    val res = elector.sendRecoverStakeRequest(extraSrcAddr, 42, { value: ton("1") });
    expect(res).toHaveTx<PayStake>({ from: elector.address, to: extraSrcAddr });

    // After recovery, credits should be zero
    val creditedAfter = elector.computeReturnedStake(extraSrcHash);
    expect(creditedAfter).toEqual(0);
}
