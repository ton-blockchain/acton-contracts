import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../wrappers/MultisigV2"

fun main() {
    val multisigAddress: address? = env("MSIG_ADDRESS");

    if (multisigAddress == null) {
        println("Set MSIG_ADDRESS before running this script.");
        return;
    }

    val multisig = MultisigV2.fromAddress(multisigAddress!);
    if (!net.isDeployed(multisig.address)) {
        println("Multisig is not deployed in the current execution context: {}", multisig.address);
        return;
    }

    val data = multisig.getData();
    val signers = data.signersMap();
    val proposers = data.proposersMap();

    var signerCount = 0;
    var signerItems = signers.findFirst();
    while (signerItems.isFound) {
        signerCount += 1;
        signerItems = signers.iterateNext(signerItems);
    }

    var proposerCount = 0;
    var proposerItems = proposers.findFirst();
    while (proposerItems.isFound) {
        proposerCount += 1;
        proposerItems = proposers.iterateNext(proposerItems);
    }

    println("Multisig address: {}", multisig.address);
    println("Threshold: {}", data.threshold);
    println("Signers: {}", signerCount);
    println("Proposers: {}", proposerCount);

    if (data.nextOrderSeqno == -1) {
        println("Order seqno mode: arbitrary");
    } else {
        println("Next order seqno: {}", data.nextOrderSeqno);
        println("Next order address: {}", multisig.getOrderAddress(data.nextOrderSeqno));
    }

    signerItems = signers.findFirst();
    while (signerItems.isFound) {
        println("signer[{}]: {}", signerItems.getKey(), signerItems.loadValue());
        signerItems = signers.iterateNext(signerItems);
    }

    proposerItems = proposers.findFirst();
    while (proposerItems.isFound) {
        println("proposer[{}]: {}", proposerItems.getKey(), proposerItems.loadValue());
        proposerItems = proposers.iterateNext(proposerItems);
    }
}
