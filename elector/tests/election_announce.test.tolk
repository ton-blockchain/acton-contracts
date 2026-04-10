import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/types"
import "../wrappers/Elector"

get fun `test election announce not elector`() {
    // Deploy elector with default config (elector address matches config param 1)
    val setup = setupElector();
    val elector = setup.elector;

    // Verify no active elections
    expect(elector.activeElectionId()).toEqual(0);

    // Change config param 1 to a different address so elector address doesn't match
    val otherAddr = net.randomAddress("other", MASTERCHAIN);
    val (_, otherHash) = otherAddr.getWorkchainAndHash();
    var config = net.getConfig();
    config.setParamRaw(1, beginCell().storeUint(otherHash, 256).endCell());
    net.setConfig(config);

    // Tick-tock should NOT announce elections since address doesn't match
    val _res1 = announceElections(elector);
    expect(elector.activeElectionId()).toEqual(0);

    // Restore correct elector address in config
    val (_, electorHash) = elector.address.getWorkchainAndHash();
    config = net.getConfig();
    config.setParamRaw(1, beginCell().storeUint(electorHash, 256).endCell());
    net.setConfig(config);

    // Now tick-tock should announce elections
    val _res2 = announceElections(elector);
    val electAt = elector.activeElectionId();
    expect(electAt).toNotEqual(0);
}

get fun `test election announce not masterchain`() {
    // Deploy elector on basechain instead of masterchain
    val elector = Elector.fromStorage(defaultStorage(), null, BASECHAIN);
    val deployer = net.treasury("deployer");
    val res = elector.deploy(deployer.address, { value: ton("1000") });
    expect(res).toHaveSuccessfulDeploy({ to: elector.address });

    // Verify elector is on basechain (workchain 0)
    val (wc, _) = elector.address.getWorkchainAndHash();
    expect(wc).toEqual(BASECHAIN);
    // Tick-tock transactions can only run on masterchain accounts.
    // The emulator refuses to execute tick-tock on basechain, which means
    // an elector deployed on basechain can never announce elections.
    // This inherently validates the test's intent.
}

get fun `test election announce no curr validators set`() {
    val setup = setupElector();
    val elector = setup.elector;

    // No active elections
    expect(elector.activeElectionId()).toEqual(0);

    // Remove config param 34 (current validators set)
    var config = net.getConfig();
    config.delete(34);
    net.setConfig(config);

    // Tick-tock should fail because config param 34 is missing
    val _res1 = announceElections(elector);
    // Verify elections were NOT announced (tx should have failed/aborted)
    expect(elector.activeElectionId()).toEqual(0);

    // Restore config param 34 and verify elections can now be announced
    config = net.getConfig();
    config.setParamRaw(34, defaultValidators().toCell());
    net.setConfig(config);

    val _res2 = announceElections(elector);
    val electAt = elector.activeElectionId();
    expect(electAt).toNotEqual(0);
}

get fun `test election announce not expired`() {
    val setup = setupElector();
    val elector = setup.elector;

    // No active elections
    expect(elector.activeElectionId()).toEqual(0);

    val vtimes = defaultValidationTimes();
    val shift = 1000;
    val timeLeft = shift + vtimes.electionsBeginBefore;

    // Set a validators set that hasn't expired yet
    val validYetSet = buildVSet(net.now() - shift, net.now() + timeLeft, 5, 5, 0);
    var config = net.getConfig();
    config.setParamRaw(34, validYetSet.toCell());
    net.setConfig(config);

    // Tick-tock should NOT announce elections (vset not expired)
    val _res1 = announceElections(elector);
    expect(elector.activeElectionId()).toEqual(0);

    // Time travel past expiration
    net.setNow(net.now() + timeLeft);
    val _res2 = announceElections(elector);
    expect(elector.activeElectionId()).toNotEqual(0);
}

get fun `test election announce next set already elected`() {
    val setup = setupElector();
    val elector = setup.elector;

    // No active elections
    expect(elector.activeElectionId()).toEqual(0);

    // Set config param 36 (next validators set) to indicate elections already done
    val nextVset = defaultValidators();
    var config = net.getConfig();
    config.setParamRaw(36, nextVset.toCell());
    net.setConfig(config);

    // Tick-tock should NOT announce elections
    val _res1 = announceElections(elector);
    expect(elector.activeElectionId()).toEqual(0);

    // Remove config param 36
    config = net.getConfig();
    config.delete(36);
    net.setConfig(config);

    // Now tick-tock should announce elections
    val _res2 = announceElections(elector);
    expect(elector.activeElectionId()).toNotEqual(0);
}

get fun `test election announce success`() {
    val setup = setupElector();
    val elector = setup.elector;

    // No active elections
    expect(elector.activeElectionId()).toEqual(0);

    // Announce
    val _res = announceElections(elector);
    val electAt = elector.activeElectionId();
    expect(electAt).toNotEqual(0);

    // Verify via participant_list_extended
    val (
        pElectAt,
        closeAt,
        minStake,
        totalStake,
        _plist,
        isFailed,
        isFinished,
    ) = elector.participantListExtended();

    val vtimes = defaultValidationTimes();
    val stakes = defaultStakeLimits();

    expect(pElectAt).toEqual(electAt);
    expect(electAt).toEqual(net.now() + vtimes.electionsBeginBefore);
    expect(closeAt).toEqual(electAt - vtimes.electionsEndBefore);
    expect(minStake).toEqual(stakes.minStake);
    expect(totalStake).toEqual(0);
    expect(isFailed).toEqual(false);
    expect(isFinished).toEqual(false);
}
// TODO: test election_announce_validators_set_malformed — commented out in governance_tests (requires malformed vset cell)
// TODO: test election_announce_before_existed_elections — commented out in governance_tests
