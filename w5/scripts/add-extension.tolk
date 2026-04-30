import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../contracts/messages"
import "../wrappers/WalletV5Contract"

fun main() {
    val keyPair = promptW5KeyPair();
    val subwalletId = promptW5SubwalletId();
    val wallet = resolveW5Wallet(keyPair, subwalletId);

    if (!scripts.isContractDeployed(wallet.address)) {
        println("W5 wallet at {} is not deployed yet — run deploy.tolk first.", wallet.address);
        return;
    }

    val extension = promptW5AddressRequired("W5_EXTENSION", "Enter extension address to add");
    val seqno = wallet.getSeqno();

    val actions = ActionsList {
        outActions: [],
        extraActions: [AddExtensionExtraAction { addr: extension } as ExtraAction],
    };
    val body = createExternalSignedBody(keyPair, subwalletId, seqno, actions);

    val res = wallet.sendExternalSigned(body);
    if (res == null) {
        println("Add-extension external could not be submitted");
        return;
    }
    if (res.waitForFirstTransaction() == null) {
        println("Add-extension was not confirmed");
        return;
    }

    println("W5 EXTENSION_ADDED={}", extension);
    if (net.isBroadcasting()) {
        println("Extension add broadcast — re-run info to inspect updated state.");
        return;
    }
    printW5Info(wallet, "W5");
}
