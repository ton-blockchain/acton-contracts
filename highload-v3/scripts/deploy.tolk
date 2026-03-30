import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = net.wallet("deployer-1");
    val keyPair = highloadKeyPair();
    val wallet = highloadDeployWallet(deployer.address);

    println1("Broadcast mode: {}", net.isBroadcasting());
    println1("Deployer wallet: {}", deployer.address);
    val targetAddress = highloadWalletAddress();
    if (targetAddress != null) {
        println1("Target wallet from env: {}", targetAddress!);
    }
    println1("Highload wallet: {}", wallet.address);
    println1("Highload public key: {}", keyPair.publicKey);
    printHighloadInfo(wallet);
}
