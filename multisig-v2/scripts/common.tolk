import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/vm/vm"
import "../contracts/messages"
import "../contracts/types"
import "../tests/wrappers/MultisigV2"
import "../tests/wrappers/MultisigV2Order"

const DEFAULT_DEPLOY_VALUE = ton("0.1")
const DEFAULT_ORDER_VALUE = ton("0.25")
const DEFAULT_TRANSFER_VALUE = ton("0.01")
const DEFAULT_ORDER_TTL = 1200

fun deployerWallet(): Wallet {
    return net.wallet("deployer");
}

fun baselineSigners(deployer: address): array<address> {
    var signers = array<address> [];
    signers.push(deployer);
    return signers;
}

fun baselineProposers(deployer: address): array<address> {
    var proposers = array<address> [];
    proposers.push(deployer);
    return proposers;
}

fun addressArrayToIndexedMap(addresses: array<address>): map<uint8, address> {
    var result: map<uint8, address> = [];
    var i = 0;
    while (i < addresses.size()) {
        result.set(i, addresses.get(i));
        i += 1;
    }
    return result;
}

fun oneActionOrder(actionCell: cell): DirectOrderActionsMap {
    var order: DirectOrderActionsMap = [];
    order.set(0, actionCell);
    return order;
}

fun mapCount<T>(m: map<uint8, T>): int {
    var count = 0;
    var item = m.findFirst();
    while (item.isFound) {
        count += 1;
        item = m.iterateNext(item);
    }
    return count;
}

fun makeTransferAction(to: address, value: coins, marker: int): SendMessageAction {
    val transferMessage = createMessage({
        bounce: true,
        value,
        dest: to,
        body: beginCell().storeUint(marker, 32).endCell(),
    });

    return { mode: SEND_MODE_PAY_FEES_SEPARATELY, message: transferMessage.messageCell };
}

fun makeUpdateParamsAction(
    threshold: int,
    signers: array<address>,
    proposers: array<address>,
): UpdateMultisigParamsAction {
    return {
        threshold: threshold as uint8,
        signers: addressArrayToIndexedMap(signers),
        proposers: addressArrayToIndexedMap(proposers),
    };
}

fun buildBaselineMultisig(deployer: address): MultisigV2 {
    return MultisigV2.fromConfig(
        1,
        baselineSigners(deployer),
        baselineProposers(deployer),
        false,
        0,
    );
}

fun deployBaselineMultisig(deployer: Wallet): MultisigV2 {
    val multisig = buildBaselineMultisig(deployer.address);
    val deployRes = multisig.deploy(
        deployer.address,
        { value: DEFAULT_DEPLOY_VALUE, bounce: false },
    );
    deployRes.wait();
    return multisig;
}

fun printMultisigData(multisig: MultisigV2) {
    val data = multisig.getData();
    val signers = data.signersMap();
    val proposers = data.proposersMap();

    println1("Multisig address: {}", multisig.address);
    println1("next order seqno: {}", data.nextOrderSeqno);
    println1("threshold: {}", data.threshold);
    println1("signers: {}", mapCount(signers));
    println1("proposers: {}", mapCount(proposers));
    println1("next order address: {}", multisig.getOrderAddress(data.nextOrderSeqno));

    var signerItems = signers.findFirst();
    while (signerItems.isFound) {
        println2("  signer[{}]: {}", signerItems.getKey(), signerItems.loadValue());
        signerItems = signers.iterateNext(signerItems);
    }

    var proposerItems = proposers.findFirst();
    while (proposerItems.isFound) {
        println2("  proposer[{}]: {}", proposerItems.getKey(), proposerItems.loadValue());
        proposerItems = proposers.iterateNext(proposerItems);
    }
}

fun currentBaselineExpiration(): int {
    return net.now() + DEFAULT_ORDER_TTL;
}
