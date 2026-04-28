import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/JettonMinter.gen"
import "../wrappers/utils"

fun main() {
    val admin = promptJettonWallet("JETTON_ADMIN", "Select Current Admin ActonWallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");
    val nextAdmin = promptJettonAddress(
        "JETTON_NEXT_ADMIN",
        "Enter next admin address",
        admin.address,
    );

    val res = minter.sendChangeAdmin(admin.address, nextAdmin);
    res.waitForFirstTransaction();

    println("JETTON NEXT_ADMIN_REQUESTED={}", nextAdmin);
    printJettonMinterInfo(minter, "JETTON");
}
