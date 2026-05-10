import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Multisig.gen"
import "../wrappers/Order.gen"
import "../wrappers/utils"

const DEFAULT_ORDER_TTL = 1200
const DEFAULT_TRANSFER_VALUE = ton("0.01")
const DEFAULT_MARKER = 0x4d534947

fun main() {
    val multisigAddress: address? = env("MSIG_ADDRESS");
    val target: address? = env("MSIG_TARGET");

    if (multisigAddress == null || target == null) {
        println("Set MSIG_ADDRESS and MSIG_TARGET before running this script.");
        return;
    }

    val deployer = scripts.wallet("deployer");
    val multisig = Multisig.fromAddress(multisigAddress!);
    if (!scripts.isContractDeployed(multisig.address)) {
        println("Multisig is not deployed in the current execution context: {}", multisig.address);
        return;
    }

    val dataBefore = multisig.getData();
    val signerIndex: int = env("MSIG_SIGNER_INDEX") ?? 0;
    val isAutoApprove: bool = env("MSIG_AUTO_APPROVE") ?? true;
    val orderSeqnoEnv: int? = env("MSIG_ORDER_SEQNO");
    val transferValue: int = env("MSIG_TRANSFER_VALUE") ?? DEFAULT_TRANSFER_VALUE;
    val marker: int = env("MSIG_MARKER") ?? DEFAULT_MARKER;
    val expirationDate: int = env("MSIG_EXPIRATION_DATE") ?? (blockchain.now() + DEFAULT_ORDER_TTL);
    val queryId: int = env("MSIG_QUERY_ID") ?? 0;

    if (dataBefore.nextOrderSeqno == -1 && orderSeqnoEnv == null) {
        println("Set MSIG_ORDER_SEQNO before submitting an order to an arbitrary-seqno multisig.");
        return;
    }

    if (
        dataBefore.nextOrderSeqno != -1 && orderSeqnoEnv != null &&
        orderSeqnoEnv! != dataBefore.nextOrderSeqno
    ) {
        println(
            "Sequential multisig expects next order seqno {}, not {}",
            dataBefore.nextOrderSeqno,
            orderSeqnoEnv!,
        );
        return;
    }

    val requestedOrderSeqno: uint256 = orderSeqnoEnv == null
        ? MAX_ORDER_SEQNO
        : orderSeqnoEnv! as uint256;
    val expectedOrderSeqno = dataBefore.nextOrderSeqno == -1
        ? orderSeqnoEnv!
        : dataBefore.nextOrderSeqno;

    val action = SendMessageAction {
        mode: SEND_MODE_PAY_FEES_SEPARATELY as uint8,
        message: createMessage({
            bounce: true,
            value: transferValue,
            dest: target!,
            body: beginCell().storeUint(marker, 32).endCell(),
        }).messageCell,
    };
    var order: DirectOrderActionsMap = [];
    order.set(0, action.toCell());

    val estimatedOrderValue = multisig.getOrderEstimateForOrder(order, expirationDate);
    val orderValue: int = env("MSIG_ORDER_VALUE") ?? estimatedOrderValue;
    if (orderValue < estimatedOrderValue) {
        println(
            "MSIG_ORDER_VALUE {} is below estimated minimum {}",
            orderValue,
            estimatedOrderValue,
        );
        return;
    }

    val orderContract = Order.fromAddress(multisig.getOrderAddress(expectedOrderSeqno));

    println("Using wallet: deployer");
    println("Target multisig: {}", multisig.address);
    println("Transfer target: {}", target!);
    println("Expected order seqno: {}", expectedOrderSeqno);
    println("Expected order address: {}", orderContract.address);
    println("Estimated order funding value: {}", estimatedOrderValue);
    println("Order funding value: {}", orderValue);

    val result = multisig.sendNewOrder(
        deployer.address,
        order,
        expirationDate,
        isAutoApprove,
        signerIndex,
        requestedOrderSeqno,
        queryId as uint64,
        { value: orderValue, bounce: true },
    );
    if (result.waitForFirstTransaction() == null) {
        println("New order was not confirmed");
        return;
    }

    val dataAfter = multisig.getData();
    val orderData = orderContract.getData();

    println("New order submitted for {}", target!);
    println("Order initialized: {}", orderData.isInitialized());
    println("Order approvals: {}", orderData.approvalsNum);
    println("Order sent for execution: {}", orderData.sentForExecution);
    println("Order expiration date: {}", orderData.expirationDate);

    if (dataAfter.nextOrderSeqno == -1) {
        println("Order seqno mode: arbitrary");
    } else {
        println("Next order seqno: {}", dataAfter.nextOrderSeqno);
        println("Next order address: {}", multisig.getOrderAddress(dataAfter.nextOrderSeqno));
    }
}
