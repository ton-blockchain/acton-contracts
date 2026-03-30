import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = net.wallet("deployer-1");
    val wallet = highloadDeployWallet(deployer.address);
    val queryId = envOr<int>("HIGHLOAD_QUERY_ID", HIGHLOAD_DEFAULT_QUERY_ID);

    println1("Broadcast mode: {}", net.isBroadcasting());
    println1("Deployer wallet: {}", deployer.address);
    val targetAddress = highloadWalletAddress();
    if (targetAddress != null) {
        println1("Target wallet from env: {}", targetAddress!);
    }
    printHighloadInfo(wallet, queryId);
}
