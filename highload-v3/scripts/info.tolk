import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../tests/wrappers/HighloadWalletV3"

fun main() {
    val walletAddress: address? = env("HIGHLOAD_WALLET_ADDRESS");

    if (walletAddress == null) {
        println("Set HIGHLOAD_WALLET_ADDRESS before running this script.");
        return;
    }

    val queryId: int = env("HIGHLOAD_QUERY_ID") ?? 0;
    val wallet = HighloadWalletV3.fromAddress(walletAddress!);

    if (!net.isDeployed(wallet.address)) {
        println1("Wallet is not deployed in the current execution context: {}", wallet.address);
        return;
    }

    println1("Highload wallet address: {}", wallet.address);
    println1("Public key: {}", wallet.getPublicKey());
    println1("Subwallet id: {}", wallet.getSubwalletId());
    println1("Timeout: {}", wallet.getTimeout());
    println1("Last clean time: {}", wallet.getLastCleanTime());
    println2(
        "processed?(queryId={}, needClean=false): {}",
        queryId,
        wallet.isProcessed(queryId, false),
    );
}
