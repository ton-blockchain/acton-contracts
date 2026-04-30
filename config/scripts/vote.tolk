import "@acton/crypto"
import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@acton/testing/assert"
import "utils/common"
import "../contracts/messages"
import "../wrappers/Config.gen"

fun main() {
    val sender = promptConfigWallet("CONFIG_VOTE_SENDER", "Select Vote Sender ActonWallet");
    val contract = promptConfigContract("Enter Config contract address");

    val proposalHash = promptConfigInt(
        "CONFIG_PROPOSAL_HASH",
        "Enter proposal hash (decimal int256)",
        "0",
    );
    val validatorIndex = promptConfigInt(
        "CONFIG_VALIDATOR_INDEX",
        "Enter validator index",
        CONFIG_DEFAULT_VALIDATOR_INDEX,
    );
    val privateKey = env<int>("CONFIG_VALIDATOR_PRIVATE_KEY");
    if (privateKey == null) {
        Assert.fail("CONFIG_VALIDATOR_PRIVATE_KEY env required (32-byte ed25519 seed as decimal/hex)");
    }
    val queryId = promptConfigInt("CONFIG_QUERY_ID", "Enter query id", CONFIG_DEFAULT_QUERY_ID);
    val msgValue = promptConfigCoins(
        "CONFIG_VOTE_VALUE",
        "Enter message value",
        CONFIG_DEFAULT_VOTE_VALUE,
    );

    val payload = SignedVotePayload {
        validatorIndex: validatorIndex as uint16,
        proposalHash: proposalHash as uint256,
    }.toCell();

    val signature = crypto.rawSign(privateKey!, payload.beginParse().bitsHash()) as bits512;

    println("CONFIG VOTE_SENDER={}", sender.address);
    println("CONFIG SENDER_WORKCHAIN={}", sender.address.getWorkchain());
    println("CONFIG TARGET_PROPOSAL_HASH={}", proposalHash);

    if (sender.address.getWorkchain() != MASTERCHAIN) {
        println("CONFIG WARNING=sender is not on masterchain; the contract will silently drop the vote");
    }

    val res = contract.sendVoteForProposalRequest(
        sender.address,
        queryId,
        signature,
        payload.beginParse(),
        { value: msgValue, bounce: true },
    );
    res.waitForFirstTransaction();

    printConfigInfo(contract, "CONFIG");
    val raw = contract.getProposal(proposalHash);
    if (raw == null) {
        println("CONFIG PROPOSAL_AFTER_VOTE=<not found / accepted / expired>");
    } else {
        printProposalTuple("CONFIG", proposalHash, raw!);
    }
}
