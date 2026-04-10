import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = net.wallet("deployer");
    val wallet = w5DeployWallet(deployer.address);
    val targetAddress: address? = env("W5_WALLET_ADDRESS");

    println("Broadcast mode: {}", net.isBroadcasting());
    println("Deployer wallet: {}", deployer.address);
    if (targetAddress != null) {
        println("Target wallet from env: {}", targetAddress!);
    }
    w5PrintInfo(wallet);
}
