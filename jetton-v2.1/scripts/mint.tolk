import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/utils"

fun main() {
    val admin = promptJettonWallet("JETTON_ADMIN", "Select Jetton Admin ActonWallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");
    val recipient = promptJettonAddress(
        "JETTON_MINT_RECIPIENT",
        "Enter mint recipient",
        admin.address,
    );
    val mintAmount = promptJettonCoins(
        "JETTON_MINT_AMOUNT",
        "Enter mint amount",
        JETTON_DEFAULT_MINT_AMOUNT,
    );

    val res = minter.sendMint(admin.address, recipient, mintAmount, 1, ton("0.08"));
    res.waitForFirstTransaction();

    printJettonMinterInfo(minter, "JETTON");
    printJettonWalletInfo(minter, recipient, "JETTON_RECIPIENT");
}
