import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = deployerWallet();

    println1("Using wallet: {}", deployer.address);
    println1("Broadcast mode: {}", net.isBroadcasting());

    val multisig = deployBaselineMultisig(deployer);
    printMultisigData(multisig);
}
