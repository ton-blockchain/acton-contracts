import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"

fun main() {
    val deployer = scripts.wallet("deployer");
    val wallet = w5DeployWallet(deployer.address);
    val targetAddress: address? = env("W5_WALLET_ADDRESS");

    println("Broadcast mode: {}", net.isBroadcasting());
    println("Deployer wallet: {}", deployer.address);
    if (targetAddress != null) {
        println("Target wallet from env: {}", targetAddress!);
    }
    w5PrintInfo(wallet);
}
