import "@acton/env"
import "@acton/io"
import "@acton/crypto/crypto"
import "@acton/emulation/network"
import "@acton/types/out_actions"
import "../tests/wrappers/HighloadWalletV3"

const HIGHLOAD_DEFAULT_SUBWALLET_ID = 239
const HIGHLOAD_DEFAULT_TIMEOUT = 128
const HIGHLOAD_DEFAULT_BATCH_VALUE = ton("0.03")
const HIGHLOAD_DEFAULT_ACTION_VALUE = ton("0.01")
const HIGHLOAD_DEFAULT_RECIPIENT_2_VALUE = ton("0.005")

fun main() {
    val walletAddress: address? = env("HIGHLOAD_WALLET_ADDRESS");
    val seed: int? = env("HIGHLOAD_SEED");
    val queryId: int? = env("HIGHLOAD_QUERY_ID");
    val recipient1: address? = env("HIGHLOAD_RECIPIENT");

    if (walletAddress == null || seed == null || queryId == null || recipient1 == null) {
        println("Set HIGHLOAD_WALLET_ADDRESS, HIGHLOAD_SEED, HIGHLOAD_QUERY_ID, and HIGHLOAD_RECIPIENT before running this script.");
        return;
    }

    val subwalletId: int = env("HIGHLOAD_SUBWALLET_ID") ?? HIGHLOAD_DEFAULT_SUBWALLET_ID;
    val timeout: int = env("HIGHLOAD_TIMEOUT") ?? HIGHLOAD_DEFAULT_TIMEOUT;
    val createdAt: int = env("HIGHLOAD_CREATED_AT") ?? blockchain.now();
    val recipient2: address? = env("HIGHLOAD_RECIPIENT_2");
    val batchValue: int = env("HIGHLOAD_BATCH_VALUE") ?? HIGHLOAD_DEFAULT_BATCH_VALUE;
    val value1: int = env("HIGHLOAD_VALUE_1") ?? HIGHLOAD_DEFAULT_ACTION_VALUE;
    val value2: int = env("HIGHLOAD_VALUE_2") ?? HIGHLOAD_DEFAULT_RECIPIENT_2_VALUE;

    val keyPair = crypto.seedToKeyPair(seed!);
    val walletFromConfig = HighloadWalletV3.fromConfig(keyPair.publicKey, subwalletId, timeout);
    if (walletFromConfig.address != walletAddress!) {
        println1(
            "Configured wallet address does not match derived config: {}",
            walletFromConfig.address,
        );
        return;
    }

    val wallet = HighloadWalletV3.fromAddress(walletAddress!);
    if (!net.isDeployed(wallet.address)) {
        println1("Wallet is not deployed in the current execution context: {}", wallet.address);
        return;
    }

    if (wallet.isProcessed(queryId!, false)) {
        println2("Query id {} is already processed for wallet {}", queryId!, wallet.address);
        return;
    }

    var actions: array<OutActionSendMessage> = [];
    actions.push(OutActionSendMessage {
        mode: SEND_MODE_PAY_FEES_SEPARATELY as uint8,
        outMsg: createMessage({
            bounce: false,
            value: value1,
            dest: recipient1!,
            body: createEmptyCell(),
        }).messageCell,
    });
    if (recipient2 != null) {
        actions.push(OutActionSendMessage {
            mode: SEND_MODE_PAY_FEES_SEPARATELY as uint8,
            outMsg: createMessage({
                bounce: false,
                value: value2,
                dest: recipient2!,
                body: createEmptyCell(),
            }).messageCell,
        });
    }

    println1("Sending highload batch from {}", wallet.address);
    println1("Recipient 1: {}", recipient1!);
    if (recipient2 != null) {
        println1("Recipient 2: {}", recipient2!);
    }

    val sendResult = wallet.sendBatch(
        keyPair,
        actions,
        subwalletId,
        queryId!,
        timeout,
        createdAt,
        batchValue,
    );
    if (!sendResult.wait()) {
        println("Highload batch was not confirmed");
        return;
    }

    println1("Batch confirmed for query id {}", queryId!);
    println1("Last clean time: {}", wallet.getLastCleanTime());
    println2(
        "processed?(queryId={}, needClean=false): {}",
        queryId!,
        wallet.isProcessed(queryId!, false),
    );
}
