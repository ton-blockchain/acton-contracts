import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"
import "../tests/wrappers/MultisigV2"

fun main() {
    val deployer = deployerWallet();
    val existingAddress: address? = env("MSIG_ADDRESS");
    val multisig = existingAddress == null
        ? deployBaselineMultisig(deployer)
        : MultisigV2.fromAddress(existingAddress!);

    println1("Using wallet: {}", deployer.address);
    println1("Broadcast mode: {}", net.isBroadcasting());
    println1("Target multisig: {}", multisig.address);

    printMultisigData(multisig);
}
