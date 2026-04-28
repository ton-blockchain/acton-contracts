import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "test-utils"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Elector.gen"
import "../wrappers/utils"

fun zeroStorageFees() {
    var config = testing.getConfig();
    var storagePrices = config.getStoragePrices();
    var initial = storagePrices.getInitial();
    initial.masterchainBitPrice = 0;
    initial.masterchainCellPrice = 0;
    initial.bitPrice = 0;
    initial.cellPrice = 0;
    storagePrices.setInitial(initial);
    config.setStoragePrices(storagePrices);
    testing.setConfig(config);
}

fun stakerCredits(elector: Elector): int {
    val stakerAddr = randomAddress("staker", MASTERCHAIN);
    val (_, stakerHash) = stakerAddr.getWorkchainAndHash();
    return elector.computeReturnedStake(stakerHash);
}

/// Validator stakes in 2 consecutive rounds without recovering.
/// Credits must accumulate and be recoverable all at once.
get fun `test credits accumulate across two rounds`() {
    val setup = setupElector();
    val elector = setup.elector;
    zeroStorageFees();

    // === ROUND 1 ===
    announceElections(elector);
    val (_, vset1, _) = conductElectionsAndGetVset(elector, setup.configAddr);
    doInstallPromoteUnfreeze(elector, vset1);

    val creditsR1 = stakerCredits(elector);
    expect(creditsR1).toNotEqual(0);

    // === ROUND 2 (no recovery) ===
    prepareNextRound(elector);
    val (_, vset2, _) = conductElectionsAndGetVset(elector, setup.configAddr);
    doInstallPromoteUnfreeze(elector, vset2);

    val creditsR2 = stakerCredits(elector);
    expect(creditsR2 > creditsR1).toEqual(true);

    // === RECOVER ALL AT ONCE ===
    val stakerAddr = randomAddress("staker", MASTERCHAIN);
    testing.topUp(stakerAddr, ton("10000"));
    val res = elector.sendRecoverStakeRequest(stakerAddr, 42, { value: ton("1") });
    expect(res).toHaveTx<PayStake>({ from: elector.address, to: stakerAddr });
    expect(stakerCredits(elector)).toEqual(0);
}

/// Validator stakes in 3 rounds, recovers only once at the end.
get fun `test credits accumulate across three rounds`() {
    val setup = setupElector();
    val elector = setup.elector;
    zeroStorageFees();

    var prevCredits: int = 0;
    var round = 0;
    while (round < 3) {
        if (round > 0) {
            prepareNextRound(elector);
        } else {
            announceElections(elector);
        }

        val (_, vset, _) = conductElectionsAndGetVset(elector, setup.configAddr);
        doInstallPromoteUnfreeze(elector, vset);

        val credits = stakerCredits(elector);
        expect(credits > prevCredits).toEqual(true);
        prevCredits = credits;
        round += 1;
    }

    val stakerAddr = randomAddress("staker", MASTERCHAIN);
    testing.topUp(stakerAddr, ton("10000"));
    val res = elector.sendRecoverStakeRequest(stakerAddr, 99, { value: ton("1") });
    expect(res).toHaveTx<PayStake>({ from: elector.address, to: stakerAddr });
    expect(stakerCredits(elector)).toEqual(0);
}

// Validator recovers after round 1, then stakes in round 2.
get fun `test partial recovery between rounds`() {
    val setup = setupElector();
    val elector = setup.elector;
    zeroStorageFees();

    val stakerAddr = randomAddress("staker", MASTERCHAIN);

    // === ROUND 1 ===
    announceElections(elector);
    val (_, vset1, _) = conductElectionsAndGetVset(elector, setup.configAddr);
    doInstallPromoteUnfreeze(elector, vset1);
    expect(stakerCredits(elector)).toNotEqual(0);

    testing.topUp(stakerAddr, ton("10000"));
    val res1 = elector.sendRecoverStakeRequest(stakerAddr, 1, { value: ton("1") });
    expect(res1).toHaveTx<PayStake>({ from: elector.address, to: stakerAddr });
    expect(stakerCredits(elector)).toEqual(0);

    // === ROUND 2 ===
    prepareNextRound(elector);
    val (_, vset2, _) = conductElectionsAndGetVset(elector, setup.configAddr);
    doInstallPromoteUnfreeze(elector, vset2);
    expect(stakerCredits(elector)).toNotEqual(0);

    testing.topUp(stakerAddr, ton("10000"));
    val res2 = elector.sendRecoverStakeRequest(stakerAddr, 2, { value: ton("1") });
    expect(res2).toHaveTx<PayStake>({ from: elector.address, to: stakerAddr });
    expect(stakerCredits(elector)).toEqual(0);
}
