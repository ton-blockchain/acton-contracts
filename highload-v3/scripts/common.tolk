import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/build/build"
import "@acton/crypto/crypto"
import "@acton/emulation/network"
import "@acton/types/out_actions"
import "../tests/wrappers/HighloadWalletV3"

const HIGHLOAD_DEFAULT_SEED = 0x1111111111111111111111111111111111111111111111111111111111111111
const HIGHLOAD_DEFAULT_SUBWALLET_ID = 239
const HIGHLOAD_DEFAULT_TIMEOUT = 128
const HIGHLOAD_DEFAULT_DEPLOY_VALUE = ton("0.05")
const HIGHLOAD_DEFAULT_BATCH_VALUE = ton("0.03")
const HIGHLOAD_DEFAULT_ACTION_VALUE = ton("0.01")
const HIGHLOAD_DEFAULT_RECIPIENT_2_VALUE = ton("0.005")
const HIGHLOAD_DEFAULT_QUERY_ID = 0

fun highloadSeed(): int {
    return envOr<int>("HIGHLOAD_SEED", HIGHLOAD_DEFAULT_SEED);
}

fun highloadKeyPair(): KeyPair {
    return crypto.seedToKeyPair(highloadSeed());
}

fun highloadSubwalletId(): int {
    return envOr<int>("HIGHLOAD_SUBWALLET_ID", HIGHLOAD_DEFAULT_SUBWALLET_ID);
}

fun highloadTimeout(): int {
    return envOr<int>("HIGHLOAD_TIMEOUT", HIGHLOAD_DEFAULT_TIMEOUT);
}

fun highloadDeployValue(): int {
    return envOr<int>("HIGHLOAD_DEPLOY_VALUE", HIGHLOAD_DEFAULT_DEPLOY_VALUE);
}

fun highloadBatchValue(): int {
    return envOr<int>("HIGHLOAD_BATCH_VALUE", HIGHLOAD_DEFAULT_BATCH_VALUE);
}

fun highloadWalletAddress(): address? {
    return env<address>("HIGHLOAD_WALLET_ADDRESS");
}

fun highloadRecipient(name: string, envName: string): address {
    return envOr<address>(envName, net.treasury(name).address);
}

fun highloadBuildWallet(): HighloadWalletV3 {
    val keyPair = highloadKeyPair();
    val subwalletId = highloadSubwalletId();
    val timeout = highloadTimeout();
    val explicitAddress = highloadWalletAddress();

    if (net.isBroadcasting() && explicitAddress != null) {
        return HighloadWalletV3.fromAddress(explicitAddress!);
    }

    return HighloadWalletV3.fromConfig(keyPair.publicKey, subwalletId, timeout);
}

fun highloadDeployWallet(deployer: address): HighloadWalletV3 {
    val wallet = highloadBuildWallet();
    if (!net.isBroadcasting() || highloadWalletAddress() == null) {
        val res = wallet.deploy(deployer, { value: highloadDeployValue(), bounce: false });
        res.wait();
    }
    return wallet;
}

fun highloadMakeAction(
    dest: address,
    value: coins,
    body: cell? = null,
    mode: int = SEND_MODE_PAY_FEES_SEPARATELY,
    bounce: bool = false,
): OutActionSendMessage {
    var actionBody = body;
    if (actionBody == null) {
        actionBody = createEmptyCell();
    }
    return OutActionSendMessage {
        mode: mode as uint8,
        outMsg: createMessage({
            bounce,
            value,
            dest,
            body: actionBody!,
        }).messageCell,
    };
}

fun printHighloadInfo(wallet: HighloadWalletV3, queryId: int = HIGHLOAD_DEFAULT_QUERY_ID) {
    println1("Highload wallet address: {}", wallet.address);
    println1("Public key: {}", wallet.getPublicKey());
    println1("Subwallet id: {}", wallet.getSubwalletId());
    println1("Timeout: {}", wallet.getTimeout());
    println1("Last clean time: {}", wallet.getLastCleanTime());
    println(
        format2(
            "processed?(queryId={}, needClean=false): {}",
            queryId,
            wallet.isProcessed(queryId, false),
        ),
    );
}
