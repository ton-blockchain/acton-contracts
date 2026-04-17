import "@acton/emulation/network"
import "@acton/promts/prompts"
import "utils/common"
import "../wrappers/JettonMinter"
import "../wrappers/JettonWallet"

fun main() {
    val sender = promptJettonWallet("JETTON_SENDER", "Select Jetton Sender Wallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");
    val recipient = promptJettonAddressRequired(
        "JETTON_TRANSFER_RECIPIENT",
        "Enter transfer recipient",
    );
    val transferAmount = promptJettonCoins(
        "JETTON_TRANSFER_AMOUNT",
        "Enter transfer amount",
        JETTON_DEFAULT_TRANSFER_AMOUNT,
    );

    val senderWallet = JettonWallet { address: minter.getWalletAddress(sender.address) };
    val res = senderWallet.sendTransfer(
        sender.address,
        ton("0.08"),
        transferAmount,
        recipient,
        sender.address,
        null,
        1,
        null,
    );
    res.wait();

    printJettonMinterInfo(minter, "JETTON");
    printJettonWalletInfo(minter, sender.address, "JETTON_SENDER");
    printJettonWalletInfo(minter, recipient, "JETTON_RECIPIENT");
}
