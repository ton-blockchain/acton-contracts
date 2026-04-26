import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"
import "../wrappers/WalletV5Contract"

fun main() {
    val keyPair = w5KeyPair();
    val walletAddress = w5WalletAddress();
    if (walletAddress == null && net.isBroadcasting()) {
        println("Set W5_WALLET_ADDRESS to the deployed wallet before broadcasting transfers.");
        return;
    }
    val deployer = scripts.wallet("deployer");
    val wallet = w5DeployWallet(deployer.address);
    val seqno = wallet.getSeqno();
    val recipient = env<address>("W5_RECIPIENT") ?? deployer.address;
    val value = env<int>("W5_TRANSFER_VALUE") ?? w5ActionValue();

    var outActions: array<SendAction> = [];
    outActions.push(w5SendAction(recipient, value));

    val actions = ActionsList {
        outActions,
        extraActions: [],
    };
    val body = createExternalSignedBody(keyPair, w5SubwalletId(), seqno, actions);

    println("Sending signed transfer from wallet: {}", wallet.address);
    println("Recipient: {}", recipient);

    val res = wallet.sendExternalSigned(body);
    if (res == null) {
        println("Wallet v5 external transfer could not be submitted");
        return;
    }
    if (res.waitForFirstTransaction() == null) {
        println("Wallet v5 transfer was not confirmed");
        return;
    }

    if (net.isBroadcasting()) {
        println("Transfer confirmed. Re-run info to fetch updated on-chain seqno.");
        return;
    }

    println("Transfer confirmed, new seqno: {}", wallet.getSeqno());
    w5PrintInfo(wallet);
}
