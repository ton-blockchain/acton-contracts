import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/types/transaction"
import "@acton/vm/vm"
import "wrappers/MultisigV2"
import "wrappers/MultisigV2Order"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/types"

const DEFAULT_ORDER_CREATE_VALUE = ton("2")
const DEFAULT_APPROVE_VALUE = ton("0.1")
const DEFAULT_TRANSFER_VALUE = ton("0.015")
const DEFAULT_ORDER_TTL = 1000
const LARGE_ORDER_CHAIN_HEAD_SIZE = 253
const LARGE_ORDER_MAX_INLINE = 254

struct MultisigTestContext {
    multisig: MultisigV2
    deployer: Treasury
    proposer: Treasury
    outsider: Treasury
    signers: array<address>
    proposers: array<address>
    threshold: int
}

type GenericOrderAction = SendMessageAction | UpdateMultisigParamsAction

fun createFundedAddress(): address {
    val addr = net.randomAddress(null);
    net.topUp(addr, ton("100"));
    return addr;
}

fun createSignerAddresses(signerCount: int, first: address): array<address> {
    assert (signerCount >= 1) throw 7101;

    var signers = array<address> [];
    signers.push(first);

    var i = 1;
    while (i < signerCount) {
        signers.push(createFundedAddress());
        i += 1;
    }
    return signers;
}

fun createProposerAddresses(proposerCount: int, first: address): array<address> {
    assert (proposerCount >= 1) throw 7102;

    var proposers = array<address> [];
    proposers.push(first);

    var i = 1;
    while (i < proposerCount) {
        proposers.push(createFundedAddress());
        i += 1;
    }
    return proposers;
}

fun setupMultisig(
    threshold: int = 1,
    signerCount: int = 5,
    proposerCount: int = 1,
    allowArbitraryOrderSeqno: bool = false,
): MultisigTestContext {
    net.setNow(1000);
    vm.registerLibrary(build("multisig_v2_order"));

    val deployer = net.treasury("msig_deployer");
    val proposer = net.treasury("msig_proposer");
    val outsider = net.treasury("msig_outsider");

    val signers = createSignerAddresses(signerCount, deployer.address);
    val proposers = createProposerAddresses(proposerCount, proposer.address);

    val multisig = MultisigV2.fromConfig(threshold, signers, proposers, allowArbitraryOrderSeqno);

    val deploy = multisig.deploy(deployer.address, { value: ton("10"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: multisig.address });

    return {
        multisig,
        deployer,
        proposer,
        outsider,
        signers,
        proposers,
        threshold,
    };
}

fun toAddressMap(addresses: array<address>): DirectIndexedAddressMap {
    return toDirectIndexedAddressMap(addresses);
}

fun toAddressMapOptional(addresses: array<address>): IndexedAddressMap {
    return toIndexedAddressMap(addresses);
}

fun markerBody(marker: int): cell {
    return beginCell().storeUint(marker, 32).endCell();
}

fun makeTransferAction(
    to: address,
    value: coins = DEFAULT_TRANSFER_VALUE,
    marker: int = 0x12345,
    mode: int = SEND_MODE_PAY_FEES_SEPARATELY,
    bounce: bool = true,
): SendMessageAction {
    val transferMessage = createMessage({
        bounce,
        value,
        dest: to,
        body: markerBody(marker),
    });
    return { mode: mode as uint8, message: transferMessage.messageCell };
}

fun makeTransferActionWithBody(
    to: address,
    value: coins,
    body: cell,
    mode: int = SEND_MODE_PAY_FEES_SEPARATELY,
    bounce: bool = true,
): SendMessageAction {
    val transferMessage = createMessage({
        bounce,
        value,
        dest: to,
        body,
    });
    return { mode: mode as uint8, message: transferMessage.messageCell };
}

fun makeUpdateAction(
    threshold: int,
    signers: array<address>,
    proposers: array<address>,
): UpdateMultisigParamsAction {
    return {
        threshold: threshold as uint8,
        signers: toAddressMap(signers),
        proposers: toAddressMapOptional(proposers),
    };
}

fun packActionCells(actions: array<cell>): DirectOrderActionsMap {
    var result: DirectOrderActionsMap = [];
    var i = 0;
    while (i < actions.size()) {
        result.set(i as uint8, actions.get(i));
        i += 1;
    }
    return result;
}

fun packActions(actions: array<GenericOrderAction>): DirectOrderActionsMap {
    var actionCells = array<cell> [];
    var i = 0;
    while (i < actions.size()) {
        actionCells.push(actions.get(i).toCell());
        i += 1;
    }
    return packActionCells(actionCells);
}

fun singleActionOrder(action: GenericOrderAction): DirectOrderActionsMap {
    var actions = array<GenericOrderAction> [];
    actions.push(action);
    return packActions(actions);
}

fun pairActionsOrder(first: GenericOrderAction, second: GenericOrderAction): DirectOrderActionsMap {
    var actions = array<GenericOrderAction> [];
    actions.push(first);
    actions.push(second);
    return packActions(actions);
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

fun approvalBit(mask: int?, idx: int): bool {
    if (mask == null) {
        return false;
    }
    return ((mask! >> idx) & 1) == 1;
}

fun mapToAddressArray(m: map<uint8, address>): array<address> {
    var result = array<address> [];
    var item = m.findFirst();
    var expected = 0;

    while (item.isFound) {
        expect(item.getKey()).toEqual(expected);
        result.push(item.loadValue());
        expected += 1;
        item = m.iterateNext(item);
    }

    return result;
}

fun equalAddressArrays(left: array<address>, right: array<address>): bool {
    if (left.size() != right.size()) {
        return false;
    }

    var i = 0;
    while (i < left.size()) {
        if (left.get(i) != right.get(i)) {
            return false;
        }
        i += 1;
    }
    return true;
}

fun nowPlus(delta: int = DEFAULT_ORDER_TTL): int {
    return net.now() + delta;
}

fun deployOrderFor(multisigAddress: address, orderSeqno: int): MultisigV2Order {
    return MultisigV2Order.fromAddress(
        MultisigV2.fromAddress(multisigAddress).getOrderAddress(orderSeqno),
    );
}

fun nextOrder(multisig: MultisigV2): (MultisigV2Order, int) {
    val data = multisig.getData();
    val seqno = data.nextOrderSeqno;
    return (MultisigV2Order.fromAddress(multisig.getOrderAddress(seqno)), seqno);
}

fun sendOrderBySigner(
    ctx: MultisigTestContext,
    order: DirectOrderActionsMap,
    expirationDate: int,
    signerIndex: int = 0,
    orderSeqno: uint256 = MAX_ORDER_SEQNO,
    value: coins = DEFAULT_ORDER_CREATE_VALUE,
): SendResultList {
    return ctx
        .multisig
        .sendNewOrder(
            ctx.signers.get(signerIndex),
            order,
            expirationDate,
            true,
            signerIndex,
            orderSeqno,
            0,
            { value, bounce: true },
        );
}

fun sendOrderByProposer(
    ctx: MultisigTestContext,
    order: DirectOrderActionsMap,
    expirationDate: int,
    proposerIndex: int = 0,
    orderSeqno: uint256 = MAX_ORDER_SEQNO,
    value: coins = DEFAULT_ORDER_CREATE_VALUE,
): SendResultList {
    return ctx
        .multisig
        .sendNewOrder(
            ctx.proposers.get(proposerIndex),
            order,
            expirationDate,
            false,
            proposerIndex,
            orderSeqno,
            0,
            { value, bounce: true },
        );
}

fun buildLargeOrder(
    multisigAddress: address,
    actions: array<SendMessageAction>,
): DirectOrderActionsMap {
    return buildLargeOrderRange(multisigAddress, actions, 0, actions.size());
}

fun buildLargeOrderRange(
    multisigAddress: address,
    actions: array<SendMessageAction>,
    start: int,
    count: int,
): DirectOrderActionsMap {
    if (count <= LARGE_ORDER_MAX_INLINE) {
        var cells = array<cell> [];
        var i = 0;
        while (i < count) {
            cells.push(actions.get(start + i).toCell());
            i += 1;
        }
        return packActionCells(cells);
    }

    val headCount = LARGE_ORDER_CHAIN_HEAD_SIZE;
    val tail = buildLargeOrderRange(multisigAddress, actions, start + headCount, count - headCount);

    var headCells = array<cell> [];
    var i = 0;
    while (i < headCount) {
        headCells.push(actions.get(start + i).toCell());
        i += 1;
    }

    val chainBody = ExecuteInternalRequest { queryId: 0, order: tail }.toCell();

    val chainMsg = createMessage({
        bounce: true,
        value: ton("0.01"),
        dest: multisigAddress,
        body: chainBody,
    });

    headCells.push(
        SendMessageAction {
            mode: SEND_MODE_PAY_FEES_SEPARATELY as uint8,
            message: chainMsg.messageCell,
        }.toCell(),
    );

    return packActionCells(headCells);
}

fun getTxLt(res: SendResultList, params: SearchParams): int {
    val tx = res.findTransaction(params);
    expect(tx).toBeDefined();
    return tx.unwrap().lt;
}

fun makeApproveCommentBody(comment: string): cell {
    return beginCell().storeUint(0, 32).storeSlice(comment.beginParse()).endCell();
}

fun loadApproveAccepted(tx: Transaction): ApproveAccepted {
    return tx.loadBody<ApproveAccepted>();
}

fun loadApproveRejected(tx: Transaction): ApproveRejected {
    return tx.loadBody<ApproveRejected>();
}

fun assertOrderNotExecuted(res: SendResultList, multisigAddress: address, recipient: address) {
    expect(res).toNotHaveTx({ from: multisigAddress, to: recipient });
}
