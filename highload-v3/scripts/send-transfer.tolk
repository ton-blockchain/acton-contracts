import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/types/out_actions"
import "common"

fun main() {
    val deployer = net.wallet("deployer-1");
    val keyPair = highloadKeyPair();
    val subwalletId = highloadSubwalletId();
    val timeout = highloadTimeout();
    val wallet = highloadDeployWallet(deployer.address);
    val queryId = envOr<int>("HIGHLOAD_QUERY_ID", HIGHLOAD_DEFAULT_QUERY_ID);
    val createdAt = envOr<int>("HIGHLOAD_CREATED_AT", blockchain.now());
    val recipient1 = highloadRecipient("highload-recipient-1", "HIGHLOAD_RECIPIENT");
    val recipient2 = highloadRecipient("highload-recipient-2", "HIGHLOAD_RECIPIENT_2");
    val value1 = envOr<int>("HIGHLOAD_VALUE_1", HIGHLOAD_DEFAULT_ACTION_VALUE);
    val value2 = envOr<int>("HIGHLOAD_VALUE_2", HIGHLOAD_DEFAULT_RECIPIENT_2_VALUE);

    var actions: array<OutActionSendMessage> = [];
    actions.push(highloadMakeAction(recipient1, value1));
    actions.push(highloadMakeAction(recipient2, value2));

    println1("Sending highload batch from: {}", wallet.address);
    println1("Recipient 1: {}", recipient1);
    println1("Recipient 2: {}", recipient2);

    val res = wallet.sendBatch(
        keyPair,
        actions,
        subwalletId,
        queryId,
        timeout,
        createdAt,
        highloadBatchValue(),
    );

    if (!res.wait()) {
        println("Highload batch was not confirmed");
        return;
    }

    println1("Batch confirmed for query id {}", queryId);
    printHighloadInfo(wallet, queryId);
}
