import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = net.wallet("deployer");
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
