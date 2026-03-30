import "@acton/env"
import "@acton/io"

import "@acton/crypto/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "../contracts/messages"
import "../contracts/storage"
import "../tests/wrappers/ConfigContract"

const SCRIPT_CONFIG_NOW = 1710000000

struct ScriptValidatorFixture {
    keyPair: KeyPair
    weight: int
}

fun buildScriptValidators(count: int = 1): array<ScriptValidatorFixture> {
    var validators = array<ScriptValidatorFixture> [];
    var i = 0;
    while (i < count) {
        validators.push(ScriptValidatorFixture {
            keyPair: crypto.seedToKeyPair((i + 1) as uint256),
            weight: 1,
        });
        i += 1;
    }
    return validators;
}

fun validatorsToRawDict(validators: array<ScriptValidatorFixture>): dict {
    var validatorMap: map<uint16, slice> = [];
    var i = 0;
    while (i < validators.size()) {
        val validator = validators.get(i);
        validatorMap.set(
            i as uint16,
            ValidatorDescrSimple {
                pubkeyTag: OP_ED25519_PUBKEY,
                publicKey: validator.keyPair.publicKey as uint256,
                weight: validator.weight as uint64,
            }.toCell()
                .beginParse(),
        );
        i += 1;
    }
    return validatorMap.toLowLevelDict();
}

fun buildScriptValidatorSetCell(validators: array<ScriptValidatorFixture>, round: int = 0): cell {
    val now = net.now() as int;
    val since = now + 100 + (round * 100);
    val until = since + 65536;

    return ValidatorSetExt {
        utimeSince: since as uint32,
        utimeUntil: until as uint32,
        total: validators.size() as uint16,
        main: validators.size() as uint16,
        totalWeight: validators.size() as uint64,
        validators: validatorsToRawDict(validators),
    }.toCell();
}

fun buildScriptVotingSetup(): cell {
    val normal = ConfigProposalSetup {
        minTotalRounds: 2,
        maxTotalRounds: 12,
        minWins: 2,
        maxLosses: 10,
        minStoreSec: 30,
        maxStoreSec: 3 * 86400,
        bitPrice: 1,
        cellPrice: 1,
    };

    val critical = ConfigProposalSetup {
        minTotalRounds: 3,
        maxTotalRounds: 16,
        minWins: 3,
        maxLosses: 14,
        minStoreSec: 30,
        maxStoreSec: 3 * 86400,
        bitPrice: 1,
        cellPrice: 1,
    };

    return ConfigVotingSetup {
        normalParams: normal.toCell(),
        criticalParams: critical.toCell(),
    }.toCell();
}

fun buildScriptCriticalParamsCell(): cell {
    var criticalMap: map<int32, slice> = [];
    criticalMap.set(-1000, beginCell().toSlice());
    return criticalMap.toLowLevelDict()!;
}

fun configDeployValue(): coins {
    return envOr<int>("CONFIG_DEPLOY_VALUE_NANOS", 1000000000) as coins;
}

fun configProposalValue(): coins {
    return envOr<int>("CONFIG_PROPOSAL_VALUE_NANOS", 1000000000) as coins;
}

fun configProposalText(): string {
    return envOr<string>("CONFIG_PROPOSAL_TEXT", "config-script");
}

fun configProposalParamId(): int32 {
    return envOr<int>("CONFIG_PROPOSAL_PARAM_ID", -42) as int32;
}

fun prepareConfigScriptContract(): ConfigContract {
    net.setNow(SCRIPT_CONFIG_NOW);

    var config = net.getConfig();
    config.setParamRaw(CONFIG_PARAM_VOTING_SETUP, buildScriptVotingSetup());
    config.setParamRaw(CONFIG_PARAM_CRITICAL_PARAMS, buildScriptCriticalParamsCell());
    config.setParamRaw(
        CONFIG_PARAM_CURRENT_VALIDATOR_SET,
        buildScriptValidatorSetCell(buildScriptValidators(), 0),
    );
    net.setConfig(config);

    return ConfigContract.fromStorage(Storage {
        config: createMapFromLowLevelDict<int32, cell>(config.toLowLevelDict()),
        storedSeqno: 0,
        publicKey: 0,
        voteDict: [],
    });
}

fun buildScriptProposal(): ConfigProposal {
    return ConfigProposal {
        paramId: configProposalParamId(),
        paramValue: beginCell().storeSlice(configProposalText().beginParse()).endCell(),
        ifHashEqual: null,
    };
}

fun printConfigSummary(contract: ConfigContract) {
    println1("Config address: {}", contract.address);
    println1("Seqno: {}", contract.seqno());
    println1("Open proposals: {}", contract.listProposals());
    println1("Sample storage price: {}", contract.proposalStoragePrice(0, 86400, 1024, 2));
}
