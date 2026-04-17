import "@acton/io"
import "@acton/emulation/network"
import "@acton/promts/prompts"
import "utils/common"
import "../wrappers/JettonMinter"

fun main() {
    val admin = promptJettonWallet("JETTON_ADMIN", "Select Current Admin Wallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");
    val nextAdmin = promptJettonAddress(
        "JETTON_NEXT_ADMIN",
        "Enter next admin address",
        admin.address,
    );

    val res = minter.sendChangeAdmin(admin.address, nextAdmin);
    res.wait();

    println("JETTON NEXT_ADMIN_REQUESTED={}", nextAdmin);
    printJettonMinterInfo(minter, "JETTON");
}
