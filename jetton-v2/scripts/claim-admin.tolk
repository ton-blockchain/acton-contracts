import "@acton/io"
import "@acton/emulation/network"
import "@acton/promts/prompts"
import "utils/common"
import "../wrappers/JettonMinter"

fun main() {
    val claimer = promptJettonWallet("JETTON_PENDING_ADMIN", "Select Pending Admin Wallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");

    val res = minter.sendClaimAdmin(claimer.address);
    res.wait();

    println("JETTON CLAIM_SENDER={}", claimer.address);
    printJettonMinterInfo(minter, "JETTON");
}
