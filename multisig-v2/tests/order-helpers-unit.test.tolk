import "@stdlib/gas-payments"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/message"
import "@acton/types/out_actions"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/order-helpers"
import "../contracts/storage"
import "../contracts/types"

/// SAFETY: helper
fun setC5OutsideContract(value: cell): void
    asm "c5 POPCTR"

fun clearOutActions() {
    setC5OutsideContract(beginCell().endCell());
}

fun toSignerMap(signers: array<address>): DirectIndexedAddressMap {
    var m: DirectIndexedAddressMap = [];
    var i = 0;
    while (i < signers.size()) {
        m.set(i, signers.get(i));
        i += 1;
    }
    return m;
}

fun makeSingleActionOrder(marker: int = 777): DirectOrderActionsMap {
    val outbound = createMessage({
        bounce: true,
        value: ton("0.01"),
        dest: randomAddress("order_unit_dest"),
        body: beginCell().storeUint(marker, 32).endCell(),
    });
    val action = SendMessageAction {
        mode: SEND_MODE_PAY_FEES_SEPARATELY,
        message: outbound.messageCell,
    };

    var actions: DirectOrderActionsMap = [];
    actions.set(0, action.toCell());
    return actions;
}

fun makeOrderWithActions(count: int): DirectOrderActionsMap {
    var actions: DirectOrderActionsMap = [];
    var i = 0;
    while (i < count) {
        actions.set(i, makeSingleActionOrder(1000 + i).get(0).loadValue());
        i += 1;
    }
    return actions;
}

fun buildStorage(signers: DirectIndexedAddressMap, threshold: uint8 = 2): OrderStorageInitialized {
    return {
        multisigAddress: randomAddress("helpers_multisig"),
        orderSeqno: 1,
        remaining: {
            threshold,
            sentForExecution: false,
            signers,
            approvalsMask: 0,
            approvalsNum: 0,
            expirationDate: 2000000000,
            order: makeSingleActionOrder(),
        },
    };
}

fun approvalBit(mask: uint256, idx: int): bool {
    return (((mask >> idx)) & 1) == 1;
}

fun getSingleMessageAction(actions: OutActionList): TlbOutActionSendMessage {
    expect(actions.size()).toEqual(1);
    val action = actions.getSendMessageAt(0);
    expect(action).toBeNotNull();
    return action!;
}

fun containsMessageWithOpcode(actions: OutActionList, opcode: int): bool {
    var i = 0;
    while (i < actions.size()) {
        val sendAction = actions.getSendMessageAt(i);
        if (sendAction != null) {
            val op = sendAction!.loadGenericMessage().loadOpcode();
            if (op != null && op! == opcode) {
                return true;
            }
        }
        i += 1;
    }
    return false;
}

fun manualOrderProcessingCost(
    orderBody: DirectOrderActionsMap,
    signers: DirectIndexedAddressMap,
    duration: int,
): coins {
    val orderDict = orderBody.toLowLevelDict()!;
    val signersDict = signers.toLowLevelDict()!;

    val gasBefore = getGasConsumedAtTheMoment();
    val (orderCells, orderBits, _) = orderDict.calculateSizeStrict(8192);
    val (signersCells, signersBits, _) = signersDict.calculateSizeStrict(512);
    val sizeCountingGas = getGasConsumedAtTheMoment() - gasBefore;

    val gasFees = calculateGasFee(BASECHAIN, MULTISIG_INIT_ORDER_GAS + sizeCountingGas) +
    calculateGasFee(BASECHAIN, ORDER_INIT_GAS) +
    calculateGasFee(BASECHAIN, ORDER_EXECUTE_GAS) +
    calculateGasFee(BASECHAIN, MULTISIG_EXECUTE_GAS);

    val forwardFees = calculateForwardFee(
        BASECHAIN,
        INIT_ORDER_BIT_OVERHEAD + orderBits + signersBits,
        INIT_ORDER_CELL_OVERHEAD + orderCells + signersCells,
    ) +
    calculateForwardFee(
        BASECHAIN,
        EXECUTE_ORDER_BIT_OVERHEAD + orderBits,
        EXECUTE_ORDER_CELL_OVERHEAD + orderCells,
    );

    val storageFees = calculateStorageFee(
        BASECHAIN,
        duration,
        ORDER_STATE_BIT_OVERHEAD + orderBits + signersBits,
        ORDER_STATE_CELL_OVERHEAD + orderCells + signersCells,
    );

    return gasFees + forwardFees + storageFees;
}

get fun `test helpers: getTextComment should flatten comment chain in refs`() {
    val plainBody = beginCell().storeUint(0, 32).storeSlice("approve".beginParse()).endCell();
    val plain = TextComment.fromCell(plainBody);
    expect(getTextComment(plain.comment).bitsEqual(COMMENT_APPROVE)).toEqual(true);

    val chained = beginCell()
        .storeSlice("a".beginParse())
        .storeRef(
            beginCell()
                .storeSlice("p".beginParse())
                .storeRef(beginCell().storeSlice("prove".beginParse()).endCell())
                .endCell(),
        )
        .endCell();
    val chainedBody = beginCell().storeUint(0, 32).storeSlice(chained.beginParse()).endCell();
    val withRefs = TextComment.fromCell(chainedBody);
    expect(getTextComment(withRefs.comment).bitsEqual(COMMENT_APPROVE)).toEqual(true);

    val emptyInMiddle = beginCell()
        .storeUint(0, 32)
        .storeSlice("ap".beginParse())
        .storeRef(
            beginCell().storeRef(beginCell().storeSlice("prove".beginParse()).endCell()).endCell(),
        )
        .endCell();
    val withEmptyRefs = TextComment.fromCell(emptyInMiddle);
    expect(getTextComment(withEmptyRefs.comment).bitsEqual(COMMENT_APPROVE)).toEqual(true);
}

get fun `test helpers: findSignerByAddress should return signer index when found`() {
    val s0 = randomAddress("find_signer_0");
    val s1 = randomAddress("find_signer_1");
    val s2 = randomAddress("find_signer_2");
    val signers = toSignerMap(array<address> [s0, s1, s2]);

    val (idx1, found1) = signers.findSignerByAddress(s1);
    expect(found1).toEqual(true);
    expect(idx1).toEqual(1);

    val missing = randomAddress("find_signer_missing");
    val (idx2, found2) = signers.findSignerByAddress(missing);
    expect(found2).toEqual(false);
    expect(idx2).toEqual(0);
}

get fun `test helpers: calculateOrderProcessingCost should match manual formula`() {
    val signers = toSignerMap(
        array<address> [
            randomAddress("calc_signer_0"),
            randomAddress("calc_signer_1"),
            randomAddress("calc_signer_2"),
        ],
    );
    val order = makeSingleActionOrder(9090);
    val duration = 7 * 24 * 3600;

    val actual = calculateOrderProcessingCost(order, signers, duration);
    val expected = manualOrderProcessingCost(order, signers, duration);

    expect(actual as int).toBeApproxEqRel(expected, 5);
}

get fun `test helpers: OrderStorageInitialized.approve should accept and then execute on threshold`() {
    val s0 = randomAddress("approve_direct_0");
    val s1 = randomAddress("approve_direct_1");
    val signers = toSignerMap(array<address> [s0, s1]);
    var storage = buildStorage(signers, 2);

    clearOutActions();
    storage.approve(0, s0, 101);
    expect(storage.remaining.approvalsNum).toEqual(1);
    expect(approvalBit(storage.remaining.approvalsMask, 0)).toEqual(true);
    expect(storage.remaining.sentForExecution).toEqual(false);
    expect(contract.getData().hash()).toEqual(storage.toCell().hash());

    val firstActions = testing.outActions();
    val acceptedBody = getSingleMessageAction(firstActions).loadBody<ApproveAccepted>();
    expect(acceptedBody.queryId).toEqual(101);

    clearOutActions();
    storage.approve(1, s1, 102);
    expect(storage.remaining.approvalsNum).toEqual(2);
    expect(approvalBit(storage.remaining.approvalsMask, 1)).toEqual(true);
    expect(storage.remaining.sentForExecution).toEqual(true);
    expect(contract.getData().hash()).toEqual(storage.toCell().hash());

    val secondActions = testing.outActions();
    expect(secondActions.size()).toEqual(2);
    expect(
        containsMessageWithOpcode(secondActions, ApproveAccepted.__getDeclaredPackPrefix()),
    ).toEqual(true);
    expect(
        containsMessageWithOpcode(secondActions, ExecuteOrderRequest.__getDeclaredPackPrefix()),
    ).toEqual(true);
}

get fun `test helpers: OrderStorageInitialized.approve should reject duplicate approval`() {
    val s0 = randomAddress("approve_dup_0");
    val s1 = randomAddress("approve_dup_1");
    val signers = toSignerMap(array<address> [s0, s1]);
    var storage = buildStorage(signers, 2);

    clearOutActions();
    storage.approve(0, s0, 201);

    val before = storage.toCell().hash();
    clearOutActions();
    storage.approve(0, s0, 202);
    val after = storage.toCell().hash();

    expect(after).toEqual(before);
    expect(contract.getData().hash()).toEqual(before);

    val rejectActions = testing.outActions();
    val rejected = getSingleMessageAction(rejectActions).loadBody<ApproveRejected>();
    expect(rejected.queryId).toEqual(202);
    expect(rejected.exitCode).toEqual(ERROR_ALREADY_APPROVED);
}

get fun `test helpers: OrderStorageInitialized.approve should reject once already executed`() {
    val s0 = randomAddress("approve_exec_0");
    val s1 = randomAddress("approve_exec_1");
    val signers = toSignerMap(array<address> [s0, s1]);
    var storage = buildStorage(signers, 1);

    clearOutActions();
    storage.approve(0, s0, 301);
    expect(storage.remaining.sentForExecution).toEqual(true);

    val before = storage.toCell().hash();
    clearOutActions();
    storage.approve(1, s1, 302);
    val after = storage.toCell().hash();

    expect(after).toEqual(before);
    expect(contract.getData().hash()).toEqual(before);

    val rejectActions = testing.outActions();
    val rejected = getSingleMessageAction(rejectActions).loadBody<ApproveRejected>();
    expect(rejected.queryId).toEqual(302);
    expect(rejected.exitCode).toEqual(ERROR_ALREADY_EXECUTED);
}
