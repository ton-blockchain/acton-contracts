import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/Elector.gen"

fun main() {
    val sender = promptElectorWallet(
        "ELECTOR_RECOVER_SENDER",
        "Select Sender ActonWallet (must be on masterchain to actually recover)",
    );
    val elector = promptElector("ELECTOR_ADDRESS", "Enter Elector address");
    val queryId = promptElectorInt(
        "ELECTOR_QUERY_ID",
        "Enter query id",
        ELECTOR_DEFAULT_QUERY_ID,
    );
    val value = promptElectorCoins(
        "ELECTOR_RECOVER_VALUE",
        "Enter message value (nanotons)",
        ELECTOR_DEFAULT_RECOVER_AMOUNT,
    );

    val (_, senderHash) = sender.address.getWorkchainAndHash();
    printRecoverableStake(elector, senderHash, "ELECTOR_BEFORE");

    val res = elector.sendRecoverStakeRequest(sender.address, queryId as uint64, { value });
    res.waitForFirstTransaction();

    printElectorInfo(elector, "ELECTOR");
    printRecoverableStake(elector, senderHash, "ELECTOR_AFTER");
}
