import "@stdlib/strings"
import "@stdlib/lisp-lists"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../../contracts/messages"
import "../../contracts/types"
import "../../wrappers/Elector.gen"
import "../../wrappers/utils"

// Well-known elector address used by both testnet and mainnet system contracts.
const ELECTOR_DEFAULT_ADDRESS = "-1:3333333333333333333333333333333333333333333333333333333333333333"

const ELECTOR_DEFAULT_TRANSFER_AMOUNT = "1000000000" // 1 TON
const ELECTOR_DEFAULT_DEPLOY_AMOUNT = "1000000000"   // 1 TON
const ELECTOR_DEFAULT_RECOVER_AMOUNT = "1000000000"  // 1 TON (carried, refunded)
const ELECTOR_DEFAULT_QUERY_ID = "0"

const WORKCHAIN_BASECHAIN = "basechain (0)"
const WORKCHAIN_MASTERCHAIN = "masterchain (-1)"

fun promptElectorString(envName: string, message: string, default: string): string {
    val fromEnv = env<string>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return prompt(message, "", default);
}

fun promptElectorAddress(envName: string, message: string, default: string): address {
    val fromEnv = env<address>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseAddress(prompt(message, "EQ... / kQ... / wc:hash", default));
}

fun promptElectorAddressRequired(envName: string, message: string): address {
    val fromEnv = env<address>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseAddress(prompt(message, "EQ... / kQ...", ""));
}

fun promptElectorCoins(envName: string, message: string, default: string): coins {
    val fromEnv = env<coins>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseInt(prompt(message, "in nanotons", default));
}

fun promptElectorInt(envName: string, message: string, default: string): int {
    val fromEnv = env<int>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseInt(prompt(message, "", default));
}

fun promptElectorWallet(envName: string, message: string): ActonWallet {
    val nameFromEnv = env<string>(envName);
    if (nameFromEnv != null) {
        return scripts.wallet(nameFromEnv);
    }
    return scripts.wallet(promptWallet(message));
}

fun promptElectorWorkchain(envName: string, message: string): int8 {
    val fromEnv = env<int>(envName);
    if (fromEnv != null) {
        return fromEnv as int8;
    }
    val choice = select(message, [WORKCHAIN_BASECHAIN, WORKCHAIN_MASTERCHAIN], 0);
    return choice.equalTo(WORKCHAIN_MASTERCHAIN) ? MASTERCHAIN : BASECHAIN;
}

fun promptElector(envName: string, message: string): Elector {
    val addr = promptElectorAddress(envName, message, ELECTOR_DEFAULT_ADDRESS);
    return Elector.fromAddress(addr);
}

fun defaultElectorStorage(): Storage {
    return Storage {
        currectElections: null,
        credits: [],
        pastElections: [],
        grams: 0,
        activeId: 0,
        activeHash: 0,
    };
}

fun deployElector(deployer: ActonWallet, storage: Storage, workchain: int8, value: coins): Elector {
    val elector = Elector.fromStorageInWorkchain(storage, null, workchain);
    val res = elector.deployInWorkchain(deployer.address, workchain, { value });
    res.waitForFirstTransaction();
    return elector;
}

fun printElectorAddress(elector: Elector, label: string) {
    println("{} ADDRESS={}", label, elector.address);
    val deployed = scripts.isContractDeployed(elector.address);
    println("{} DEPLOYED={}", label, deployed);
    if (deployed) {
        println("{} BALANCE={}", label, scripts.fetchAccountBalance(elector.address));
    } else {
        println("{} BALANCE=<unavailable>", label);
    }
}

fun printCurrentElections(elector: Elector, label: string) {
    val (
        electAt,
        closeAt,
        minStake,
        totalStake,
        members,
        isFailed,
        isFinished,
    ) = elector.participantListExtended();

    if (electAt == 0) {
        println("{} CURRENT_ELECTIONS=<none>", label);
        return;
    }
    println("{} CURRENT_ELECTIONS_AT={}", label, electAt);
    println("{} CURRENT_ELECTIONS_CLOSE_AT={}", label, closeAt);
    println("{} CURRENT_ELECTIONS_MIN_STAKE={}", label, minStake);
    println("{} CURRENT_ELECTIONS_TOTAL_STAKE={}", label, totalStake);
    println("{} CURRENT_ELECTIONS_PARTICIPANTS={}", label, members.calculateSize());
    println("{} CURRENT_ELECTIONS_FAILED={}", label, isFailed);
    println("{} CURRENT_ELECTIONS_FINISHED={}", label, isFinished);
}

fun printPastElections(elector: Elector, label: string) {
    val ids = elector.pastElectionIds();
    val count = ids.calculateSize();
    println("{} PAST_ELECTIONS_COUNT={}", label, count);

    var ptr = ids;
    var i = 0;
    while (!ptr.isEmpty() && i < 5) {
        val id = ptr.popHead();
        println("{} PAST_ELECTION_ID[{}]={}", label, i, id);
        i += 1;
    }
}

fun printElectorInfo(elector: Elector, label: string) {
    printElectorAddress(elector, label);
    if (!scripts.isContractDeployed(elector.address)) {
        return;
    }
    printCurrentElections(elector, label);
    printPastElections(elector, label);
}

fun printRecoverableStake(elector: Elector, ownerHash: uint256, label: string) {
    if (!scripts.isContractDeployed(elector.address)) {
        println("{} RECOVERABLE_STAKE=<elector-not-deployed>", label);
        return;
    }
    val amount = elector.computeReturnedStake(ownerHash);
    println("{} RECOVERABLE_STAKE={}", label, amount);
}
