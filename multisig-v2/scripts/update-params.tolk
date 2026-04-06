import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../contracts/messages"
import "../contracts/types"
import "../tests/wrappers/MultisigV2"
import "../tests/wrappers/MultisigV2Order"

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
        println1("Multisig is not deployed in the current execution context: {}", multisig.address);
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
        println1("Signer is already present: {}", newSigner!);
        return;
    }

    if (proposerAlreadyPresent) {
        println1("Proposer is already present: {}", newProposer!);
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
        println2("Threshold {} is invalid for {} signers", threshold, signerCount);
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
        println2(
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
        println2(
            "MSIG_ORDER_VALUE {} is below estimated minimum {}",
            orderValue,
            estimatedOrderValue,
        );
        return;
    }

    val orderContract = MultisigV2Order.fromAddress(multisig.getOrderAddress(expectedOrderSeqno));

    println("Using wallet: deployer");
    println1("Target multisig: {}", multisig.address);
    if (newSigner != null) {
        println1("Adding signer: {}", newSigner!);
    }
    if (newProposer != null) {
        println1("Adding proposer: {}", newProposer!);
    }
    println1("Threshold after update: {}", threshold);
    println1("Expected order seqno: {}", expectedOrderSeqno);
    println1("Expected order address: {}", orderContract.address);
    println1("Estimated order funding value: {}", estimatedOrderValue);
    println1("Order funding value: {}", orderValue);

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

    println1("Multisig params update submitted for {}", multisig.address);
    println1("Order initialized: {}", orderData.isInitialized());
    println1("Order approvals: {}", orderData.approvalsNum);
    println1("Order sent for execution: {}", orderData.sentForExecution);
    println1("Threshold: {}", dataAfter.threshold);
    println1("Signers: {}", signerCount);
    println1("Proposers: {}", proposerCount);

    if (dataAfter.nextOrderSeqno == -1) {
        println("Order seqno mode: arbitrary");
    } else {
        println1("Next order seqno: {}", dataAfter.nextOrderSeqno);
        println1("Next order address: {}", multisig.getOrderAddress(dataAfter.nextOrderSeqno));
    }
}
