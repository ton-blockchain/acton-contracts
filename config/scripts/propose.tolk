import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../contracts/messages"
import "../wrappers/Config.gen"

fun main() {
    val sender = promptConfigWallet("CONFIG_PROPOSER", "Select Proposer ActonWallet");
    val contract = promptConfigContract("Enter Config contract address");

    val paramId = promptConfigInt(
        "CONFIG_PARAM_ID",
        "Enter param id (e.g. 1, 2, -1000)",
        CONFIG_DEFAULT_PARAM_ID,
    );

    val critical = promptConfigBool(
        "CONFIG_PROPOSAL_CRITICAL",
        "Propose as critical?",
        CONFIG_DEFAULT_CRITICAL,
        "Critical proposals require stricter quorum",
    );

    val expireInSec = promptConfigInt(
        "CONFIG_EXPIRE_IN_SEC",
        "Enter expiration (seconds from now)",
        CONFIG_DEFAULT_EXPIRE_IN_SEC,
    );

    val queryId = promptConfigInt(
        "CONFIG_QUERY_ID",
        "Enter query id",
        CONFIG_DEFAULT_QUERY_ID,
    );

    val paramValue = promptConfigCellOptional(
        "CONFIG_PARAM_VALUE",
        "BoC value for the parameter (skip to propose deletion)",
    );

    val expectedHashEnv = env<int>("CONFIG_PARAM_EXPECTED_HASH");
    val expectedHash: uint256? = expectedHashEnv == null ? null : (expectedHashEnv! as uint256);

    val proposal = ConfigProposal {
        paramId,
        paramValue,
        ifHashEqual: expectedHash,
    };
    val hash = proposalHashOf(proposal);

    val msgValue = promptConfigCoins(
        "CONFIG_PROPOSAL_VALUE",
        "Enter message value (must cover storage price)",
        CONFIG_DEFAULT_PROPOSAL_VALUE,
    );

    println("CONFIG PROPOSER_ADDRESS={}", sender.address);
    println("CONFIG SENDER_WORKCHAIN={}", sender.address.getWorkchain());
    println("CONFIG NEW_PROPOSAL_HASH={}", hash);

    if (sender.address.getWorkchain() != MASTERCHAIN) {
        println("CONFIG WARNING=sender is not on masterchain; the contract will silently drop the request");
    }

    val res = contract.sendNewVotingProposalRequest(
        sender.address,
        queryId,
        expireInSec,
        critical,
        proposal,
        { value: msgValue, bounce: true },
    );
    res.waitForFirstTransaction();

    printConfigInfo(contract, "CONFIG");

    val refreshed = contract.getProposal(hash);
    if (refreshed == null) {
        println("CONFIG PROPOSAL_REGISTERED=false");
    } else {
        println("CONFIG PROPOSAL_REGISTERED=true");
        printProposalTuple("CONFIG", hash, refreshed!);
    }
}
