import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../wrappers/HighloadWalletV3"

fun main() {
    val walletAddress: address? = env("HIGHLOAD_WALLET_ADDRESS");

    if (walletAddress == null) {
        println("Set HIGHLOAD_WALLET_ADDRESS before running this script.");
        return;
    }

    val queryId: int = env("HIGHLOAD_QUERY_ID") ?? 0;
    val wallet = HighloadWalletV3.fromAddress(walletAddress!);

    if (!net.isDeployed(wallet.address)) {
        println("Wallet is not deployed in the current execution context: {}", wallet.address);
        return;
    }

    println("Highload wallet address: {}", wallet.address);
    println("Public key: {}", wallet.getPublicKey());
    println("Subwallet id: {}", wallet.getSubwalletId());
    println("Timeout: {}", wallet.getTimeout());
    println("Last clean time: {}", wallet.getLastCleanTime());
    println(
        "processed?(queryId={}, needClean=false): {}",
        queryId,
        wallet.isProcessed(queryId, false),
    );
}
