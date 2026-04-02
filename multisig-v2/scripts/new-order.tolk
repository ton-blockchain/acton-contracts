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

    val transferTarget: address? = env("MSIG_TARGET");
    val target = transferTarget == null
        ? net.randomAddress("multisig-transfer-target")
        : transferTarget!;
    val marker = envOr("MSIG_MARKER", 0x4d534947);
    val expirationDate = currentBaselineExpiration();
    val order = oneActionOrder(makeTransferAction(target, DEFAULT_TRANSFER_VALUE, marker).toCell());

    println1("Using wallet: {}", deployer.address);
    println1("Broadcast mode: {}", net.isBroadcasting());
    println1("Target multisig: {}", multisig.address);
    println1("Transfer target: {}", target);

    printMultisigData(multisig);
    println1("Order funding value: {}", DEFAULT_ORDER_VALUE);

    val result = multisig.sendNewOrder(
        deployer.address,
        order,
        expirationDate,
        true,
        0,
        MAX_ORDER_SEQNO,
        envOr("MSIG_QUERY_ID", 0),
        { value: DEFAULT_ORDER_VALUE, bounce: true },
    );

    result.wait();
    println1("New order submitted for {}", target);
    printMultisigData(multisig);
}
