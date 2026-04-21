import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"

fun main() {
    val deployer = scripts.wallet("deployer");
    val wallet = w5DeployWallet(deployer.address);

    println("Broadcast mode: {}", net.isBroadcasting());
    println("Deployer wallet: {}", deployer.address);
    val targetAddress = w5WalletAddress();
    if (targetAddress != null) {
        println("Target wallet from env: {}", targetAddress!);
    }
    println("Wallet v5 address: {}", wallet.address);
    w5PrintInfo(wallet);
}
