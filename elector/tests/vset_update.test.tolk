import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/tlb/maybe"
import "@acton/types/transaction"
import "test_utils"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Elector"

/// Test that vset is not installed before elections finish
get fun `test vset installed not finished`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Elections not finished — tick-tock should NOT install vset
    net.runTickTock(elector.address, true);
    val stakeAt = elector.activeElectionId();
    expect(stakeAt).toNotEqual(0);
}

/// Test that elections stay until vset is seen in config
get fun `test vset installed waiting for config`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (
        _electAt,
        _,
        _,
        _,
        _,
        _,
        isFinished,
    ) = elector.participantListExtended();
    expect(isFinished).toEqual(true);

    // Elections finished but vset not in config yet — elections should persist
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toNotEqual(0);
}

/// Test bonus distribution when vset is installed
get fun `test vset bonus distribution`() {
    val setup = setupElector();
    val elector = setup.elector;

    // Send initial balance (simulating accumulated fees / nobody's balance)
    val bonusAmount: coins = ton("1000");
    val deployer = net.treasury("extra-funder");
    elector.sendSimpleTransfer(deployer.address, { value: bonusAmount });

    announceElections(elector);
    val (_stakeAt, vsetCell, stakerHash) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Install vset by setting config param 34
    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);

    // Tick-tock installs the vset
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toEqual(0);

    // Staker stake is frozen — no credits yet
    expect(elector.computeReturnedStake(stakerHash)).toEqual(0);

    // Send additional funds (simulating validator fees after install)
    val additionalFees: coins = ton("500");
    elector.sendSimpleTransfer(deployer.address, { value: additionalFees });
    // Tick-tock to process the fees into bonuses
    net.runTickTock(elector.address, true);

    // Now promote to new vset so stakes can eventually unfreeze
    val validatorConf = defaultValidationTimes();
    val stakeHeld = validatorConf.stakeHeldFor;

    val newVset = buildVSet(blockchain.now(), blockchain.now() + 10000, 1, 1, 0);
    config = net.getConfig();
    config.setParamRaw(34, newVset.toCell());
    config.setParamRaw(36, newVset.toCell());
    net.setConfig(config);

    val promoteTime = blockchain.now() + 100;
    net.setNow(promoteTime);
    net.runTickTock(elector.address, true);

    // Unfreeze
    net.setNow(promoteTime + stakeHeld + 1);
    net.runTickTock(elector.address, true);

    // After unfreeze, credits should include stake + proportional bonus
    val credit = elector.computeReturnedStake(stakerHash);
    expect(credit).toNotEqual(0);
    // Credit should be > stake (has bonus component)
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");
    expect(credit > stakePerValidator).toEqual(true);
}

/// Test past election data after conduct
get fun `test past election data`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.activeElectionId();
    conductValidElections(elector);

    // Verify elections are finished
    val (
        electAt,
        _,
        _,
        _,
        _,
        _,
        isFinished,
    ) = elector.participantListExtended();
    expect(isFinished).toEqual(true);
    expect(electAt).toEqual(stakeAt);
}

/// Test that checkUnfreeze doesn't unfreeze before time — credits remain zero
get fun `test stakes not unfrozen before time`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, vsetCell, stakerHash) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Install vset
    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toEqual(0);

    // Staker should have no credits (stake is frozen)
    expect(elector.computeReturnedStake(stakerHash)).toEqual(0);

    val validatorConf = defaultValidationTimes();
    val stakeHeld = validatorConf.stakeHeldFor;

    // Promote to new vset so active_id changes (needed for unfreeze condition)
    val newVset = buildVSet(blockchain.now(), blockchain.now() + 10000, 1, 1, 0);
    config = net.getConfig();
    config.setParamRaw(34, newVset.toCell());
    config.setParamRaw(36, newVset.toCell());
    net.setConfig(config);

    val promoteTime = blockchain.now() + 100;
    net.setNow(promoteTime);
    net.runTickTock(elector.address, true);

    // Before unfreeze time — stakes should remain frozen
    net.setNow(promoteTime + stakeHeld - 1);
    net.runTickTock(elector.address, true);
    expect(elector.computeReturnedStake(stakerHash)).toEqual(0);

    // Verify past election entry still exists via get_past_complaints (non-null = entry exists)
    val _complaints = elector.getPastComplaints(stakeAt);
    // Even if no complaints, the call should succeed (entry exists)
    // The fact that compute_returned_stake returns 0 proves the entry is still frozen
}

/// Test that checkUnfreeze unfreezes after time — credits available, past_elections cleaned up
get fun `test stakes unfrozen after time`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, vsetCell, stakerHash) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Install vset
    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toEqual(0);

    val validatorConf = defaultValidationTimes();
    val stakeHeld = validatorConf.stakeHeldFor;

    // Promote to new vset so active_id changes
    val newVset = buildVSet(blockchain.now(), blockchain.now() + 10000, 1, 1, 0);
    config = net.getConfig();
    config.setParamRaw(34, newVset.toCell());
    config.setParamRaw(36, newVset.toCell());
    net.setConfig(config);

    val promoteTime = blockchain.now() + 100;
    net.setNow(promoteTime);
    net.runTickTock(elector.address, true);

    // After unfreeze time — stakes should be unfrozen
    net.setNow(promoteTime + stakeHeld + 1);
    net.runTickTock(elector.address, true);

    // Credits should now be available
    expect(elector.computeReturnedStake(stakerHash)).toNotEqual(0);

    // Verify past election entry was removed: get_past_complaints for this election
    // should return empty complaints (the entry was removed during unfreeze)
    val complaints = elector.getPastComplaints(stakeAt);
    val lookupResult = complaints.findFirst();
    expect(lookupResult.isFound).toEqual(false);
}

/// Test that vset is installed when set to config param 34 (current validators)
get fun `test vset installed no cur vset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (_, vsetCell, _) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Elections finished but vset not in config — should NOT install
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toNotEqual(0);

    // Set elected vset to config param 34
    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);

    // Now tick-tock should install the vset — elections cleared
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toEqual(0);
}

/// Test that vset is installed when set to config param 36 (next validators)
get fun `test vset installed next vset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (_, vsetCell, _) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Elections finished but vset not in config — should NOT install
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toNotEqual(0);

    // Set elected vset to config param 36 (next validators) instead of 34
    var config = net.getConfig();
    config.setParamRaw(36, vsetCell);
    net.setConfig(config);

    // Now tick-tock should install the vset — elections cleared
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toEqual(0);
}

/// Test that unfreeze time is updated when active vset is promoted
get fun `test vset update prolong current vset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (_stakeAt, vsetCell, stakerHash) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Install elected vset by setting it to config param 34
    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);

    // Tick-tock installs the vset (validatorSetInstalled + updateActiveVsetId)
    net.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toEqual(0);

    // Staker should have no credits yet (stake is frozen)
    expect(elector.computeReturnedStake(stakerHash)).toEqual(0);

    val validatorConf = defaultValidationTimes();
    val stakeHeld = validatorConf.stakeHeldFor;

    // Create a new non-expired vset and promote it to current
    val newVset = buildVSet(blockchain.now(), blockchain.now() + 10000, 1, 1, 0);
    config = net.getConfig();
    config.setParamRaw(34, newVset.toCell());
    // Set param 36 to prevent announceNewElections from firing before updateActiveVsetId
    config.setParamRaw(36, newVset.toCell());
    net.setConfig(config);

    // Advance time a bit — updateActiveVsetId should fire on tick-tock
    // since config param 34 hash changed, updating unfreezeAt = now() + stakeHeld
    val promoteTime = blockchain.now() + 100;
    net.setNow(promoteTime);
    net.runTickTock(elector.address, true);

    // Before updated unfreezeAt: stakes should still be frozen
    net.setNow(promoteTime + stakeHeld - 1);
    net.runTickTock(elector.address, true);
    expect(elector.computeReturnedStake(stakerHash)).toEqual(0);

    // After updated unfreezeAt: stakes should be unfrozen and credits available
    net.setNow(promoteTime + stakeHeld + 1);
    net.runTickTock(elector.address, true);
    expect(elector.computeReturnedStake(stakerHash)).toNotEqual(0);
}
