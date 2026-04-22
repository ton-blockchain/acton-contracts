import "@acton/io"
import "@acton/emulation/network"
import "@acton/promts/prompts"
import "utils/common"
import "../wrappers/WalletV5Contract"

fun main() {
    val wallet = promptW5Target();
    if (net.getDeployedCode(wallet.address) == null) {
        println("W5 wallet {} is not deployed", wallet.address);
        return;
    }

    val recipient = promptW5AddressRequired("W5_RECIPIENT", "Enter recipient address");
    val value = promptW5Coins(
        "W5_TRANSFER_VALUE",
        "Enter transfer value",
        W5_DEFAULT_TRANSFER_VALUE,
    );

    var outActions: array<SendAction> = [];
    outActions.push(w5BuildSendAction(recipient, value));

    val body = createExternalSignedBody(
        w5KeyPair(),
        w5SubwalletId(),
        wallet.getSeqno(),
        ActionsList {
            outActions,
            extraActions: [],
        },
    );

    println("W5 SENDER={}", wallet.address);
    println("W5 RECIPIENT={}", recipient);
    println("W5 TRANSFER_VALUE={}", value);

    val res = wallet.sendExternalSigned(body);
    if (res == null) {
        println("W5 external transfer could not be submitted");
        return;
    }
    // SendResultList.wait() parses inMsg as internal; it does not support external-in
    // messages, so we rely on a follow-up info.tolk query instead of calling res.wait().
    if (net.isBroadcasting()) {
        println("W5 external submitted; check new seqno via info.tolk");
        return;
    }
    res.wait();

    printW5Info(wallet, "W5");
}
