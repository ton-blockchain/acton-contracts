import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@acton/prompts"
import "utils/common"
import "../wrappers/JettonMinter"

fun main() {
    val admin = promptJettonWallet("JETTON_ADMIN", "Select Jetton Admin ActonWallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");
    val metadata = promptJettonMetadata(JETTON_DEFAULT_UPDATED_DESCRIPTION);

    val res = minter.sendChangeMetadata(admin.address, buildJettonMetadataCell(metadata));
    res.wait();

    printJettonMinterInfo(minter, "JETTON");
}
