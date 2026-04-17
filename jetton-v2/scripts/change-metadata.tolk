import "@acton/emulation/network"
import "@acton/promts/prompts"
import "utils/common"
import "../wrappers/JettonMinter"

fun main() {
    val admin = promptJettonWallet("JETTON_ADMIN", "Select Jetton Admin Wallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");
    val metadata = promptJettonMetadata(JETTON_DEFAULT_UPDATED_DESCRIPTION);

    val res = minter.sendChangeMetadata(admin.address, buildJettonMetadataCell(metadata));
    res.wait();

    printJettonMinterInfo(minter, "JETTON");
}
