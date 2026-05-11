import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/WalletV5.gen"
import "../wrappers/utils"

fun main() {
    val keyPair = promptW5KeyPair();
    val subwalletId = promptW5SubwalletId();
    val wallet = resolveW5Wallet(keyPair, subwalletId);

    if (!scripts.isContractDeployed(wallet.address)) {
        println("W5 wallet at {} is not deployed yet — run deploy.tolk first.", wallet.address);
        return;
    }

    val recipient = promptW5AddressRequired("W5_RECIPIENT", "Enter recipient address");
    val value = promptW5Coins(
        "W5_TRANSFER_VALUE",
        "Enter transfer value",
        W5_DEFAULT_TRANSFER_VALUE,
    );

    val seqno = wallet.getSeqno();
    val actions = ActionsList {
        outActions: [buildSendAction(recipient, value)],
        extraActions: [],
    };
    val body = createExternalSignedBody(keyPair, subwalletId, seqno, actions);

    val res = wallet.sendExternalSigned(body);
    if (res == null) {
        println("W5 external transfer could not be submitted");
        return;
    }
    if (res.waitForFirstTransaction() == null) {
        println("W5 transfer was not confirmed");
        return;
    }

    println("W5 RECIPIENT={}", recipient);
    println("W5 TRANSFER_VALUE={}", value);
    if (net.isBroadcasting()) {
        println("Transfer broadcast — re-run info to fetch updated on-chain seqno.");
        return;
    }
    printW5Info(wallet, "W5");
}
