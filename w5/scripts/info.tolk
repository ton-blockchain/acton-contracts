import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = net.wallet("deployer");
    val wallet = w5DeployWallet(deployer.address);
    val targetAddress: address? = env("W5_WALLET_ADDRESS");

    println1("Broadcast mode: {}", net.isBroadcasting());
    println1("Deployer wallet: {}", deployer.address);
    if (targetAddress != null) {
        println1("Target wallet from env: {}", targetAddress!);
    }
    w5PrintInfo(wallet);
}
