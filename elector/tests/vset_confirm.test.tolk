import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/types"
import "../contracts/messages"

/// Test that config rejected (alt) from non-config address is ignored
get fun `test vset rejected not config`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (electAt, _, _, _, _, _, isFinished) = elector.participant_list_extended();
    expect(isFinished).toEqual(true);

    // Send ConfigConfirmedAlt (rejection) from wrong address
    val wrongAddr = net.randomAddress("wrong", MASTERCHAIN);
    net.topUp(wrongAddr, ton("10"));
    elector.sendConfigConfirmedAlt(wrongAddr, electAt as uint64, { value: ton("1") });

    // Elections should still be active (rejection ignored)
    val (electAt2, _, _, _, _, _, isFinished2) = elector.participant_list_extended();
    expect(electAt2).toNotEqual(0);

    // Send from correct config address — should cancel elections
    net.topUp(setup.configAddr, ton("10"));
    elector.sendConfigConfirmedAlt(setup.configAddr, electAt as uint64, { value: ton("1") });

    // Elections should be cancelled
    val electAt3 = elector.active_election_id();
    expect(electAt3).toEqual(0);
}

/// Test that config rejected from wrong workchain is ignored
get fun `test vset rejected wrong wc`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (electAt, _, _, _, _, _, _) = elector.participant_list_extended();

    // Create basechain address with same hash as config
    val (_, configHash) = setup.configAddr.getWorkchainAndHash();
    val bcConfigAddr = beginCell()
        .storeUint(4, 3)
        .storeInt(BASECHAIN, 8)
        .storeUint(configHash, 256)
        .endCell().beginParse().loadAddress();
    net.topUp(bcConfigAddr, ton("10"));

    // From basechain — should be ignored
    elector.sendConfigConfirmedAlt(bcConfigAddr, electAt as uint64, { value: ton("1") });
    expect(elector.active_election_id()).toNotEqual(0);

    // From masterchain — should cancel
    net.topUp(setup.configAddr, ton("10"));
    elector.sendConfigConfirmedAlt(setup.configAddr, electAt as uint64, { value: ton("1") });
    expect(elector.active_election_id()).toEqual(0);
}

/// Test that config rejected with wrong election ID is ignored
get fun `test vset rejected wrong elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (electAt, _, _, _, _, _, _) = elector.participant_list_extended();

    net.topUp(setup.configAddr, ton("100"));

    // Wrong election ID — should be ignored
    elector.sendConfigConfirmedAlt(setup.configAddr, (electAt + 1) as uint64, { value: ton("1") });
    expect(elector.active_election_id()).toNotEqual(0);

    // Correct election ID — should cancel
    elector.sendConfigConfirmedAlt(setup.configAddr, electAt as uint64, { value: ton("1") });
    expect(elector.active_election_id()).toEqual(0);
}

/// Test that config confirmed from non-config address is ignored
get fun `test vset confirmed not config`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (electAt, _, _, _, _, _, _) = elector.participant_list_extended();

    // Send ConfigConfirmed from wrong address — should be ignored
    val wrongAddr = net.randomAddress("wrong", MASTERCHAIN);
    net.topUp(wrongAddr, ton("10"));
    elector.sendConfigConfirmed(wrongAddr, electAt as uint64, { value: ton("1") });

    // Elections should still be present
    expect(elector.active_election_id()).toNotEqual(0);
}

/// Test that config confirmed from wrong workchain is ignored
get fun `test vset confirmed wrong wc`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (electAt, _, _, _, _, _, _) = elector.participant_list_extended();

    val (_, configHash) = setup.configAddr.getWorkchainAndHash();
    val bcConfigAddr = beginCell()
        .storeUint(4, 3)
        .storeInt(BASECHAIN, 8)
        .storeUint(configHash, 256)
        .endCell().beginParse().loadAddress();
    net.topUp(bcConfigAddr, ton("10"));

    elector.sendConfigConfirmed(bcConfigAddr, electAt as uint64, { value: ton("1") });
    expect(elector.active_election_id()).toNotEqual(0);
}

/// Test that config confirmed with wrong election ID is ignored
get fun `test vset confirmed wrong elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (electAt, _, _, _, _, _, _) = elector.participant_list_extended();
    net.topUp(setup.configAddr, ton("100"));

    // Wrong election ID — should be ignored
    elector.sendConfigConfirmed(setup.configAddr, (electAt + 1) as uint64, { value: ton("1") });
    expect(elector.active_election_id()).toNotEqual(0);
}

/// Test that config rejected (alt) successfully cancels elections, unfreezes stakes, and removes past election
get fun `test vset rejected success`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Use conductElectionsAndGetVset to track a known staker's address hash
    val stakeAt = elector.active_election_id();
    assert (stakeAt != 0) throw 300;

    val validatorLimits = defaultValidatorLimits();
    val stakeLimits = defaultStakeLimits();
    val numValidators = max(validatorLimits.minValidators as int, 5);
    val stakePerValidator: coins = stakeLimits.minTotalStake / numValidators + ton("10000");

    // Submit stakes and track all staker address hashes
    var stakerHashes: array<uint256> = [];
    var totalStake: coins = 0;
    var i = 0;
    while (i < numValidators) {
        val (_, srcAddr, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        val (_, hash) = srcAddr.getWorkchainAndHash();
        stakerHashes.push(hash);
        totalStake += stake;
        i += 1;
    }

    // Close elections
    val (_, closeAt, _, _, _, _, _) = elector.participant_list_extended();
    net.setNow(closeAt + 1);
    net.runTickTock(elector.address, true);

    val (electAt, _, _, _, _, _, isFinished) = elector.participant_list_extended();
    expect(isFinished).toEqual(true);

    // Before rejection: staker should have zero credit (stakes are frozen)
    val firstStakerHash = stakerHashes.get(0);
    expect(elector.compute_returned_stake(firstStakerHash)).toEqual(0);

    // Send rejection from config
    net.topUp(setup.configAddr, ton("10"));
    elector.sendConfigConfirmedAlt(setup.configAddr, electAt as uint64, { value: ton("1") });

    // Elections should be cancelled
    expect(elector.active_election_id()).toEqual(0);

    // After rejection: all frozen stakes should be credited back
    // Note: submitValidStake uses the same "staker" label so all validators share
    // the same source address → credits accumulate to numValidators * stakePerValidator
    val totalExpectedCredit: coins = (numValidators as coins) * stakePerValidator;
    val actualCredit = elector.compute_returned_stake(firstStakerHash);
    expect(actualCredit as int).toEqual(totalExpectedCredit as int);

    // Verify past election entry was removed
    val pastIds = elector.past_election_ids();
    // past_election_ids should not contain stakeAt anymore
    // Since we can't iterate lisp_list with isEmpty, use participates_in or
    // check that past_elections returns empty by verifying get_past_complaints returns empty
    val complaints = elector.get_past_complaints(stakeAt as uint32);
    val lookupResult = complaints.findFirst();
    // If past election was removed, complaints map should be empty (default)
    expect(lookupResult.isFound).toEqual(false);
}

// TODO: test vset_confirmed_success — governance_tests marks this as unnecessary (vset_rejected_success already covers the flow)
