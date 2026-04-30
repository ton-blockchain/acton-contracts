import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/Elector.gen"

fun main() {
    val sender = promptElectorWallet("ELECTOR_SENDER", "Select Sender ActonWallet");
    val elector = promptElector("ELECTOR_ADDRESS", "Enter Elector address");
    val transferAmount = promptElectorCoins(
        "ELECTOR_TRANSFER_AMOUNT",
        "Enter transfer amount (nanotons)",
        ELECTOR_DEFAULT_TRANSFER_AMOUNT,
    );

    val res = elector.sendSimpleTransfer(sender.address, { value: transferAmount });
    res.waitForFirstTransaction();

    printElectorInfo(elector, "ELECTOR");
}
