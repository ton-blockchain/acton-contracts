import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/MultisigV2"
import "../wrappers/MultisigV2Order"

const DEFAULT_ORDER_TTL = 1200

fun main() {
    val multisigAddress: address? = env("MSIG_ADDRESS");
    if (multisigAddress == null) {
        println("Set MSIG_ADDRESS before running this script.");
        return;
    }

    val deployer = net.wallet("deployer");
    val multisig = MultisigV2.fromAddress(multisigAddress!);
    if (!net.isDeployed(multisig.address)) {
        println("Multisig is not deployed in the current execution context: {}", multisig.address);
        return;
    }

    val newSigner: address? = env("MSIG_NEW_SIGNER");
    val newProposer: address? = env("MSIG_NEW_PROPOSER");
    val thresholdEnv: int? = env("MSIG_THRESHOLD");

    if (newSigner == null && newProposer == null && thresholdEnv == null) {
        println("Set MSIG_NEW_SIGNER, MSIG_NEW_PROPOSER, or MSIG_THRESHOLD before running this script.");
        return;
    }

    val dataBefore = multisig.getData();
    var signers = dataBefore.signersMap();
    var proposers = dataBefore.proposersMap();
    var signerCount = 0;
    var proposerCount = 0;
    var signerAlreadyPresent = false;
    var proposerAlreadyPresent = false;

    var signerItems = signers.findFirst();
    while (signerItems.isFound) {
        if (newSigner != null && signerItems.loadValue() == newSigner!) {
            signerAlreadyPresent = true;
        }
        signerCount += 1;
        signerItems = signers.iterateNext(signerItems);
    }

    var proposerItems = proposers.findFirst();
    while (proposerItems.isFound) {
        if (newProposer != null && proposerItems.loadValue() == newProposer!) {
            proposerAlreadyPresent = true;
        }
        proposerCount += 1;
        proposerItems = proposers.iterateNext(proposerItems);
    }

    if (signerAlreadyPresent) {
        println("Signer is already present: {}", newSigner!);
        return;
    }

    if (proposerAlreadyPresent) {
        println("Proposer is already present: {}", newProposer!);
        return;
    }

    var hasChange = false;
    if (newSigner != null) {
        signers.set(signerCount as uint8, newSigner!);
        signerCount += 1;
        hasChange = true;
    }

    if (newProposer != null) {
        proposers.set(proposerCount as uint8, newProposer!);
        proposerCount += 1;
        hasChange = true;
    }

    val threshold = thresholdEnv ?? dataBefore.threshold;
    if (threshold != dataBefore.threshold) {
        hasChange = true;
    }

    if (!hasChange) {
        println("No changes to submit.");
        return;
    }

    if (threshold <= 0 || threshold > signerCount) {
        println("Threshold {} is invalid for {} signers", threshold, signerCount);
        return;
    }

    val orderSeqnoEnv: int? = env("MSIG_ORDER_SEQNO");
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

    val expirationDate: int = env("MSIG_EXPIRATION_DATE") ?? (net.now() + DEFAULT_ORDER_TTL);
    val queryId: int = env("MSIG_QUERY_ID") ?? 0;
    val signerIndex: int = env("MSIG_SIGNER_INDEX") ?? 0;
    val isAutoApprove: bool = env("MSIG_AUTO_APPROVE") ?? true;
    val requestedOrderSeqno: uint256 = orderSeqnoEnv == null
        ? MAX_ORDER_SEQNO
        : orderSeqnoEnv! as uint256;
    val expectedOrderSeqno = dataBefore.nextOrderSeqno == -1
        ? orderSeqnoEnv!
        : dataBefore.nextOrderSeqno;

    val action = UpdateMultisigParamsAction {
        threshold: threshold as uint8,
        signers,
        proposers,
    };
    var order: DirectOrderActionsMap = [];
    order.set(0, action.toCell());

    val estimatedOrderValue = multisig.getOrderEstimate(order, expirationDate);
    val orderValue: int = env("MSIG_ORDER_VALUE") ?? estimatedOrderValue;
    if (orderValue < estimatedOrderValue) {
        println(
            "MSIG_ORDER_VALUE {} is below estimated minimum {}",
            orderValue,
            estimatedOrderValue,
        );
        return;
    }

    val orderContract = MultisigV2Order.fromAddress(multisig.getOrderAddress(expectedOrderSeqno));

    println("Using wallet: deployer");
    println("Target multisig: {}", multisig.address);
    if (newSigner != null) {
        println("Adding signer: {}", newSigner!);
    }
    if (newProposer != null) {
        println("Adding proposer: {}", newProposer!);
    }
    println("Threshold after update: {}", threshold);
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
    if (!result.wait()) {
        println("Multisig params update was not confirmed");
        return;
    }

    val dataAfter = multisig.getData();
    val orderData = orderContract.getData();

    println("Multisig params update submitted for {}", multisig.address);
    println("Order initialized: {}", orderData.isInitialized());
    println("Order approvals: {}", orderData.approvalsNum);
    println("Order sent for execution: {}", orderData.sentForExecution);
    println("Threshold: {}", dataAfter.threshold);
    println("Signers: {}", signerCount);
    println("Proposers: {}", proposerCount);

    if (dataAfter.nextOrderSeqno == -1) {
        println("Order seqno mode: arbitrary");
    } else {
        println("Next order seqno: {}", dataAfter.nextOrderSeqno);
        println("Next order address: {}", multisig.getOrderAddress(dataAfter.nextOrderSeqno));
    }
}
