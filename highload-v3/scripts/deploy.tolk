import "@acton/env"
import "@acton/io"
import "@acton/crypto/crypto"
import "@acton/emulation/network"
import "../tests/wrappers/HighloadWalletV3"

const HIGHLOAD_DEFAULT_SUBWALLET_ID = 239
const HIGHLOAD_DEFAULT_TIMEOUT = 128
const HIGHLOAD_DEFAULT_DEPLOY_VALUE = ton("0.05")

fun main() {
    val seed: int? = env("HIGHLOAD_SEED") ?? random.range(100000);
    if (seed == null) {
        println("Set HIGHLOAD_SEED before running this script.");
        return;
    }

    val deployer = net.wallet("deployer-2");

    val subwalletId: int = env("HIGHLOAD_SUBWALLET_ID") ?? HIGHLOAD_DEFAULT_SUBWALLET_ID;
    val timeout: int = env("HIGHLOAD_TIMEOUT") ?? HIGHLOAD_DEFAULT_TIMEOUT;
    val deployValue: int = env("HIGHLOAD_DEPLOY_VALUE") ?? HIGHLOAD_DEFAULT_DEPLOY_VALUE;

    val keyPair = crypto.seedToKeyPair(seed!);
    val wallet = HighloadWalletV3.fromConfig(keyPair.publicKey, subwalletId, timeout);

    println("Using wallet: deployer");
    println1("Prepared highload wallet: {}", wallet.address);

    if (net.isDeployed(wallet.address)) {
        println1("Wallet is already deployed in the current execution context: {}", wallet.address);
    } else {
        val deployResult = wallet.deploy(deployer.address, { value: deployValue, bounce: false });
        if (!deployResult.wait()) {
            println("Highload wallet deployment was not confirmed");
            return;
        }
        println1("Highload wallet deployed at {}", wallet.address);
    }

    println1("HIGHLOAD_WALLET_ADDRESS={}", wallet.address);
    println1("Public key: {}", wallet.getPublicKey());
    println1("Subwallet id: {}", wallet.getSubwalletId());
    println1("Timeout: {}", wallet.getTimeout());
    println1("Last clean time: {}", wallet.getLastCleanTime());
}
