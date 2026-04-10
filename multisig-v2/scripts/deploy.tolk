import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../wrappers/MultisigV2"

const DEFAULT_DEPLOY_VALUE = ton("0.1")

// Important: before deploying multisig contract, check that
// order library is deployed and available:
//
// "acton library publish Order"

fun main() {
    val deployer = net.wallet("deployer");
    val deployValue: int = env("MSIG_DEPLOY_VALUE") ?? DEFAULT_DEPLOY_VALUE;
    val allowArbitraryOrderSeqno: bool = false;

    var signers = array<address> [];
    signers.push(deployer.address);

    var proposers = array<address> [];
    proposers.push(deployer.address);

    val multisig = MultisigV2.fromConfig(1, signers, proposers, allowArbitraryOrderSeqno);

    println("Using wallet: deployer");
    println("Prepared multisig address: {}", multisig.address);

    if (net.isDeployed(multisig.address)) {
        println(
            "Multisig is already deployed in the current execution context: {}",
            multisig.address,
        );
    } else {
        val deployResult = multisig.deploy(deployer.address, { value: deployValue, bounce: false });
        if (!deployResult.wait()) {
            println("Multisig deployment was not confirmed");
            return;
        }
        println("Multisig deployed at {}", multisig.address);
    }

    val data = multisig.getData();
    val signersMap = data.signersMap();
    val proposersMap = data.proposersMap();

    var signerCount = 0;
    var signerItems = signersMap.findFirst();
    while (signerItems.isFound) {
        signerCount += 1;
        signerItems = signersMap.iterateNext(signerItems);
    }

    var proposerCount = 0;
    var proposerItems = proposersMap.findFirst();
    while (proposerItems.isFound) {
        proposerCount += 1;
        proposerItems = proposersMap.iterateNext(proposerItems);
    }

    println("MSIG_ADDRESS={}", multisig.address);
    println("Threshold: {}", data.threshold);
    println("Signers: {}", signerCount);
    println("Proposers: {}", proposerCount);

    if (data.nextOrderSeqno == -1) {
        println("Order seqno mode: arbitrary");
    } else {
        println("Next order seqno: {}", data.nextOrderSeqno);
        println("Next order address: {}", multisig.getOrderAddress(data.nextOrderSeqno));
    }
}
