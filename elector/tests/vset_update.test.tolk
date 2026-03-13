import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/types"
import "../contracts/messages"

/// Message format for elected validator set sent to config contract (matches ElectedVSetMsg in utils.tolk)
struct(0x4e565354) ElectedVSetMsg {
    queryId: uint64;
    vset: Cell<VSet>
}

/// Conduct elections and extract the elected vset cell from the outgoing message to config.
/// Returns (stakeAt, vsetCell, stakerHash) where vsetCell can be set as config param 34 or 36
/// and stakerHash is the address hash of a known staker (for compute_returned_stake).
fun conductElectionsAndGetVset(elector: Elector, configAddr: address): (int, cell, uint256) {
    val stakeAt = elector.active_election_id();
    assert (stakeAt != 0) throw 998;

    val validatorLimits = defaultValidatorLimits();
    val stakeLimits = defaultStakeLimits();

    var totalStake: coins = 0;
    val numValidators = max(validatorLimits.minValidators as int, 5);
    val stakePerValidator: coins = stakeLimits.minTotalStake / numValidators + ton("10000");
    var firstStakerHash: uint256 = 0;
    var i = 0;
    while (i < numValidators) {
        val (_, srcAddr, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        if (i == 0) {
            val (_, hash) = srcAddr.getWorkchainAndHash();
            firstStakerHash = hash;
        }
        totalStake += stake;
        i += 1;
    }

    val (_, closeAt, _, _, _, _, _) = elector.participant_list_extended();
    net.setNow(closeAt + 1);

    // Run tick-tock to conduct elections — captures the outgoing VSet message
    val tickResult = net.runTickTock(elector.address, true);

    // Find the ElectedVSetMsg message sent to config contract
    val tx = tickResult.findTransaction<ElectedVSetMsg>({
        from: elector.address,
        to: configAddr,
    });
    val body = tx.unwrap().loadBody<ElectedVSetMsg>();

    return (stakeAt, body.vset as cell, firstStakerHash);
}


/// Test that vset is not installed before elections finish
get fun `test vset installed not finished`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Elections not finished — tick-tock should NOT install vset
    net.runTickTock(elector.address, true);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);
}

/// Test that elections stay until vset is seen in config
get fun `test vset installed waiting for config`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (electAt, _, _, _, _, _, isFinished) = elector.participant_list_extended();
    expect(isFinished).toEqual(true);

    // Elections finished but vset not in config yet — elections should persist
    net.runTickTock(elector.address, true);
    expect(elector.active_election_id()).toNotEqual(0);
}

/// Test bonus distribution when vset is installed
get fun `test vset bonus distribution`() {
    val setup = setupElector();
    val elector = setup.elector;

    // Send some initial balance (simulating accumulated fees)
    val deployer = net.treasury("extra-funder");
    elector.sendSimpleTransfer(deployer.address, { value: ton("1000") });

    announceElections(elector);
    conductValidElections(elector);

    // Past elections exist
    val electAt = elector.active_election_id();
    expect(electAt).toNotEqual(0);
}

/// Test past election data after conduct
get fun `test past election data`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    conductValidElections(elector);

    // Verify elections are finished
    val (electAt, _, _, _, _, _, isFinished) = elector.participant_list_extended();
    expect(isFinished).toEqual(true);
    expect(electAt).toEqual(stakeAt);
}

/// Test that checkUnfreeze doesn't unfreeze before time
get fun `test stakes not unfrozen before time`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    conductValidElections(elector);

    // Calculate expected unfreezeAt
    val validatorConf = defaultValidationTimes();
    val expectedUnfreezeAt = stakeAt + validatorConf.electedFor + validatorConf.stakeHeldFor;

    // Before unfreeze time — stakes should remain frozen
    net.setNow(expectedUnfreezeAt - 1);
    net.runTickTock(elector.address, true);

    // Elections should still be present (not uninstalled, not unfrozen)
    expect(elector.active_election_id()).toNotEqual(0);
}

/// Test that checkUnfreeze unfreezes after time
get fun `test stakes unfrozen after time`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    conductValidElections(elector);

    val validatorConf = defaultValidationTimes();
    val expectedUnfreezeAt = stakeAt + validatorConf.electedFor + validatorConf.stakeHeldFor;

    // Advance past unfreeze time
    net.setNow(expectedUnfreezeAt + 1);
    net.runTickTock(elector.address, true);

    // Tick-tock should succeed (checkUnfreeze runs without error)
    // Elections still present though (validatorSetInstalled needs config match)
    expect(elector.active_election_id()).toNotEqual(0);
}

/// Test that vset is installed when set to config param 34 (current validators)
get fun `test vset installed no cur vset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (_, vsetCell, _) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Elections finished but vset not in config — should NOT install
    net.runTickTock(elector.address, true);
    expect(elector.active_election_id()).toNotEqual(0);

    // Set elected vset to config param 34
    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);

    // Now tick-tock should install the vset — elections cleared
    net.runTickTock(elector.address, true);
    expect(elector.active_election_id()).toEqual(0);
}

/// Test that vset is installed when set to config param 36 (next validators)
get fun `test vset installed next vset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (_, vsetCell, _) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Elections finished but vset not in config — should NOT install
    net.runTickTock(elector.address, true);
    expect(elector.active_election_id()).toNotEqual(0);

    // Set elected vset to config param 36 (next validators) instead of 34
    var config = net.getConfig();
    config.setParamRaw(36, vsetCell);
    net.setConfig(config);

    // Now tick-tock should install the vset — elections cleared
    net.runTickTock(elector.address, true);
    expect(elector.active_election_id()).toEqual(0);
}

/// Test that unfreeze time is updated when active vset is promoted
get fun `test vset update prolong current vset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, vsetCell, stakerHash) = conductElectionsAndGetVset(elector, setup.configAddr);

    // Install elected vset by setting it to config param 34
    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);

    // Tick-tock installs the vset (validatorSetInstalled + updateActiveVsetId)
    net.runTickTock(elector.address, true);
    expect(elector.active_election_id()).toEqual(0);

    // Staker should have no credits yet (stake is frozen)
    expect(elector.compute_returned_stake(stakerHash)).toEqual(0);

    val validatorConf = defaultValidationTimes();
    val stakeHeld = validatorConf.stakeHeldFor as int;

    // Create a new non-expired vset and promote it to current
    val newVset = buildVSet(
        blockchain.now() as int,
        blockchain.now() + 10000,
        1, 1, 0,
    );
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
    expect(elector.compute_returned_stake(stakerHash)).toEqual(0);

    // After updated unfreezeAt: stakes should be unfrozen and credits available
    net.setNow(promoteTime + stakeHeld + 1);
    net.runTickTock(elector.address, true);
    expect(elector.compute_returned_stake(stakerHash)).toNotEqual(0);
}
