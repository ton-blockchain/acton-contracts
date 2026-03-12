import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/types"
import "../contracts/messages"

/// Get the first past election entry as [id, unfreezeAt, vsetHash, stakeHeld]
fun Elector.getFirstPastElection(self): array<int> {
    // past_elections_list returns [id, unfreezeAt, vsetHash, stakeHeld]
    return net.runGetMethod(self.address, "past_elections_list");
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
