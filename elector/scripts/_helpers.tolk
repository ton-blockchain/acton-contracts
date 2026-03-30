import "@acton/env"
import "@acton/io"

import "@acton/emulation/config"
import "@acton/emulation/network"
import "../contracts/messages"
import "../contracts/types"
import "../tests/wrappers/Elector"

const SCRIPT_ELECTOR_NOW = 1667388240
const ONECOIN: coins = 1000000000

fun defaultScriptStorage(): Storage {
    return Storage {
        currectElections: null,
        credits: [],
        pastElections: [],
        grams: 0,
        activeId: 0,
        activeHash: 0,
    };
}

fun defaultScriptValidationTimes(): ValidatorConfig {
    return ValidatorConfig {
        electedFor: 10000,
        electionsBeginBefore: 8000,
        electionsEndBefore: 2000,
        stakeHeldFor: 8000,
    };
}

fun defaultScriptValidatorLimits(): ValidatorLimits {
    return ValidatorLimits {
        maxValidators: 100,
        maxMainValidators: 100,
        minValidators: 5,
    };
}

fun defaultScriptStakeLimits(): StakeLimits {
    return StakeLimits {
        minStake: 10000 * ONECOIN,
        maxStake: 500000 * ONECOIN,
        minTotalStake: 2000000 * ONECOIN,
        maxStakeFactor: (27 << 16) / 10,
    };
}

fun defaultScriptValidators(): VSet {
    return VSet {
        utimeSince: SCRIPT_ELECTOR_NOW - 1000,
        utimeUntil: SCRIPT_ELECTOR_NOW - 100,
        _total: 1,
        _main: 1,
        totalWeight: 0,
        dict: [],
    };
}

fun electorDeployValue(): coins {
    return envOr<int>("ELECTOR_DEPLOY_VALUE_NANOS", 1000000000) as coins;
}

fun electorTransferValue(): coins {
    return envOr<int>("ELECTOR_TRANSFER_VALUE_NANOS", 100000000) as coins;
}

fun prepareElectorScriptContract(): Elector {
    net.setNow(SCRIPT_ELECTOR_NOW);

    val elector = Elector.fromStorage(defaultScriptStorage(), null, MASTERCHAIN);
    val deployer = net.wallet("deployer");
    elector.deploy(deployer.address, { value: electorDeployValue() }).wait();

    var config = net.getConfig();
    val configAddr = net.randomAddress("elector-config", MASTERCHAIN);
    val (_, electorHash) = elector.address.getWorkchainAndHash();
    val (_, configHash) = configAddr.getWorkchainAndHash();

    config.setParamRaw(0, beginCell().storeUint(configHash, 256).endCell());
    config.setParamRaw(1, beginCell().storeUint(electorHash, 256).endCell());
    config.setParamRaw(15, defaultScriptValidationTimes().toCell());
    config.setParamRaw(16, defaultScriptValidatorLimits().toCell());
    config.setParamRaw(17, defaultScriptStakeLimits().toCell());
    config.setParamRaw(34, defaultScriptValidators().toCell());
    net.setConfig(config);

    return elector;
}

fun printElectorSummary(contract: Elector) {
    val (
        electAt,
        closeAt,
        minStake,
        totalStake,
        participants,
        isFailed,
        isFinished,
    ) = contract.participantListExtended();

    println1("Elector address: {}", contract.address);
    println1("Active election id: {}", electAt);
    println1("Close at: {}", closeAt);
    println1("Min stake: {}", minStake);
    println1("Total stake: {}", totalStake);
    println1("Participants: {}", participants);
    println1("Past election ids: {}", contract.pastElectionIds());
    println1("Failed: {}", isFailed);
    println1("Finished: {}", isFinished);
}
