import "@stdlib/lisp-lists"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@acton/testing/assert"
import "../../contracts/messages"
import "../../contracts/storage"
import "../../wrappers/Config.gen"

const CONFIG_DEFAULT_DEPLOY_VALUE = "1000000000"
const CONFIG_DEFAULT_PROPOSAL_VALUE = "2000000000"
const CONFIG_DEFAULT_CUSTOM_VALUE = "100000000"
const CONFIG_DEFAULT_VOTE_VALUE = "100000000"

const CONFIG_DEFAULT_QUERY_ID = "0"
const CONFIG_DEFAULT_PROPOSAL_PARAM_ID = "42"
const CONFIG_DEFAULT_CUSTOM_PARAM_ID = "-1024"
const CONFIG_DEFAULT_EXPIRE_IN_SEC = "86400"
const CONFIG_DEFAULT_CRITICAL = false
const CONFIG_DEFAULT_VALIDATOR_INDEX = "0"

fun promptConfigString(envName: string, message: string, default: string): string {
    val fromEnv = env<string>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return prompt(message, "", default);
}

fun promptConfigInt(envName: string, message: string, default: string): int {
    val fromEnv = env<int>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return promptInt(message, default, "");
}

fun promptConfigCoins(envName: string, message: string, default: string): coins {
    val fromEnv = env<coins>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseInt(prompt(message, "in nanotons", default));
}

fun promptConfigBool(envName: string, message: string, default: bool, hint: string): bool {
    val fromEnv = env<bool>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return confirm(message, default, hint);
}

fun promptConfigAddressRequired(envName: string, message: string): address {
    val fromEnv = env<address>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseAddress(prompt(message, "EQ... / kQ...", ""));
}

fun promptConfigAddress(envName: string, message: string, default: address): address {
    val fromEnv = env<address>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseAddress(prompt(message, "", format("{}", default)));
}

fun promptConfigCellOptional(envName: string, hint: string): cell? {
    val fromEnv = env<cell>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    println("    [hint] {} not set — {}", envName, hint);
    println(
        "    [hint] Pass {}=<base64-or-hex BoC> to provide a value (cells cannot be entered interactively)",
        envName,
    );
    val keep = confirm(
        format("Continue without {} (use empty cell)?", envName),
        true,
        "Pass an empty cell so the script can proceed",
    );
    if (!keep) {
        Assert.fail(format("{} required — re-run with the env var set", envName));
    }
    return null;
}

fun promptConfigCellRequired(envName: string, hint: string): cell {
    val fromEnv = env<cell>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    println("    [hint] {} not set — {}", envName, hint);
    Assert.fail(format("{} required — pass it as a base64/hex BoC env var", envName));
}

fun promptConfigWallet(envName: string, message: string): ActonWallet {
    val nameFromEnv = env<string>(envName);
    if (nameFromEnv != null) {
        return scripts.wallet(nameFromEnv);
    }
    return scripts.wallet(promptWallet(message));
}

fun promptConfigContract(message: string): Config {
    val addr = promptConfigAddressRequired("CONFIG_ADDRESS", message);
    return Config.fromAddress(addr);
}

fun defaultNormalProposalSetup(): ConfigProposalSetup {
    return ConfigProposalSetup {
        minTotalRounds: 2,
        maxTotalRounds: 12,
        minWins: 2,
        maxLosses: 10,
        minStoreSec: 30,
        maxStoreSec: 3 * 86400,
        bitPrice: 1,
        cellPrice: 1,
    };
}

fun defaultCriticalProposalSetup(): ConfigProposalSetup {
    return ConfigProposalSetup {
        minTotalRounds: 3,
        maxTotalRounds: 16,
        minWins: 3,
        maxLosses: 14,
        minStoreSec: 30,
        maxStoreSec: 3 * 86400,
        bitPrice: 1,
        cellPrice: 1,
    };
}

fun buildVotingSetupCell(): cell {
    return ConfigVotingSetup {
        normalParams: defaultNormalProposalSetup().toCell(),
        criticalParams: defaultCriticalProposalSetup().toCell(),
    }.toCell();
}

fun buildInitialConfigDict(): ConfigDict {
    var dict: ConfigDict = [];
    dict.setById(CONFIG_PARAM_VOTING_SETUP, buildVotingSetupCell());
    return dict;
}

fun buildConfigStorage(publicKey: uint256): Storage {
    return Storage {
        config: buildInitialConfigDict(),
        storedSeqno: 0,
        publicKey,
        voteDict: [],
    };
}

fun deployConfig(deployer: ActonWallet, storage: Storage, value: coins): Config {
    val contract = Config.fromStorage(storage);
    val res = contract.deploy(deployer.address, { value, bounce: false });
    res.waitForFirstTransaction();
    return contract;
}

fun proposalHashOf(proposal: ConfigProposal): uint256 {
    return proposal.toCell().hash();
}

fun printConfigInfo(contract: Config, label: string) {
    println("{} CONFIG_ADDRESS={}", label, contract.address);
    println("{} DEPLOYED={}", label, scripts.isContractDeployed(contract.address));
    if (!scripts.isContractDeployed(contract.address)) {
        println("{} SEQNO=<unavailable>", label);
        println("{} PROPOSAL_COUNT=<unavailable>", label);
        return;
    }
    println("{} SEQNO={}", label, contract.seqno());
    val proposals = contract.listProposals();
    println("{} PROPOSAL_COUNT={}", label, proposals.calculateSize());
}

fun printProposalTuple(label: string, hash: int, raw: tuple) {
    val paramTuple = raw.get(2) as tuple;
    println("{} PROPOSAL_HASH={}", label, hash);
    println("{} PROPOSAL_EXPIRES={}", label, raw.get(0) as int);
    println("{} PROPOSAL_CRITICAL={}", label, raw.get(1) as bool);
    println("{} PROPOSAL_PARAM_ID={}", label, paramTuple.get(0) as int);
    val paramValue = paramTuple.get(1) as cell?;
    if (paramValue == null) {
        println("{} PROPOSAL_PARAM_VALUE=<null>", label);
    } else {
        println("{} PROPOSAL_PARAM_VALUE_HASH={}", label, paramValue!.hash());
    }
    println("{} PROPOSAL_EXPECTED_HASH={}", label, paramTuple.get(2) as int);
    println("{} PROPOSAL_VALIDATOR_SET_ID={}", label, raw.get(3) as int);
    println("{} PROPOSAL_REMAINING_WEIGHT={}", label, raw.get(5) as int);
    println("{} PROPOSAL_ROUNDS_REMAINING={}", label, raw.get(6) as int);
    println("{} PROPOSAL_WINS={}", label, raw.get(7) as int);
    println("{} PROPOSAL_LOSSES={}", label, raw.get(8) as int);
}

fun printAllProposals(contract: Config, label: string) {
    var proposals = contract.listProposals();
    var index = 0;
    while (!proposals.isEmpty()) {
        val pair = proposals.popHead() as tuple;
        printProposalTuple(format("{}#{}", label, index), pair.get(0) as int, pair.get(1) as tuple);
        index += 1;
    }
}
