import "@acton/env"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/vm/vm"
import "common"
import "../contracts/types"
import "../tests/wrappers/MultisigV2"

fun main() {
    val deployer = deployerWallet();
    vm.registerLibrary(build("multisig_v2_order"));

    val existingAddress: address? = env("MSIG_ADDRESS");
    val multisig = existingAddress == null
        ? deployBaselineMultisig(deployer)
        : MultisigV2.fromAddress(existingAddress!);

    val signerSeed: address? = env("MSIG_NEW_SIGNER");
    val proposerSeed: address? = env("MSIG_NEW_PROPOSER");
    val newSigner = signerSeed == null ? net.randomAddress("multisig-new-signer") : signerSeed!;
    val newProposer = proposerSeed == null
        ? net.randomAddress("multisig-new-proposer")
        : proposerSeed!;

    var updatedSigners = baselineSigners(deployer.address);
    updatedSigners.push(newSigner);
    var updatedProposers = baselineProposers(deployer.address);
    updatedProposers.push(newProposer);

    val order = oneActionOrder(
        makeUpdateParamsAction(1, updatedSigners, updatedProposers).toCell(),
    );
    val expirationDate = currentBaselineExpiration();

    println1("Using wallet: {}", deployer.address);
    println1("Broadcast mode: {}", net.isBroadcasting());
    println1("Target multisig: {}", multisig.address);
    println1("New signer: {}", newSigner);
    println1("New proposer: {}", newProposer);

    printMultisigData(multisig);
    println1("Order funding value: {}", DEFAULT_ORDER_VALUE);

    val result = multisig.sendNewOrder(
        deployer.address,
        order,
        expirationDate,
        true,
        0,
        MAX_ORDER_SEQNO,
        envOr("MSIG_QUERY_ID", 0) as uint64,
        { value: DEFAULT_ORDER_VALUE, bounce: true },
    );

    result.wait();
    println1("Multisig params update submitted for {}", multisig.address);
    printMultisigData(multisig);
}
