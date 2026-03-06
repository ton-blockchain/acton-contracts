import "test_utils"
import "wrappers/MultisigV2Order"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/types"

struct OrderFixture {
    multisig: Treasury
    notSigner: Treasury
    order: MultisigV2Order
    signers: array<address>
    orderBody: DirectOrderActionsMap
    threshold: int
    expirationDate: int
}

fun setupOrderFixture(threshold: int = 5, signerCount: int = 10): OrderFixture {
    net.setNow(1000);

    val multisig = net.treasury("order_multisig");
    val notSigner = net.treasury("order_not_signer");

    var signers = array<address> [];
    var i = 0;
    while (i < signerCount) {
        signers.push(createFundedAddress());
        i += 1;
    }

    val recipient = net.randomAddress("order_recipient");
    val orderBody = singleActionOrder(makeTransferAction(recipient, DEFAULT_TRANSFER_VALUE, 12345) as GenericOrderAction);

    val order = MultisigV2Order.fromConfig(multisig.address, 0);
    val expirationDate = nowPlus(1000);

    val deploy = order.deployWithInit(
        multisig.address,
        threshold,
        toAddressMap(signers),
        expirationDate,
        orderBody,
        null,
        0,
        { value: ton("2"), bounce: true }
    );
    expect(deploy).toHaveSuccessfulDeploy({ to: order.address });

    return {
        multisig,
        notSigner,
        order,
        signers,
        orderBody,
        threshold,
        expirationDate,
    };
}

fun assertApproveAccepted(
    res: SendResultList,
    orderAddress: address,
    signerAddress: address,
    queryId: uint64,
) {
    expect(res).toHaveSuccessfulTx<ApproveAccepted>({ from: orderAddress, to: signerAddress });
    val tx = res.findTransaction<ApproveAccepted>({ from: orderAddress, to: signerAddress });
    expect(tx).toBeDefined();
    val body = loadApproveAccepted(tx.unwrap());
    expect(body.queryId).toEqual(queryId);
}

fun assertApproveRejected(
    res: SendResultList,
    orderAddress: address,
    signerAddress: address,
    queryId: uint64,
    expectedExitCode: int,
) {
    expect(res).toHaveSuccessfulTx<ApproveRejected>({ from: orderAddress, to: signerAddress });
    val tx = res.findTransaction<ApproveRejected>({ from: orderAddress, to: signerAddress });
    expect(tx).toBeDefined();
    val body = loadApproveRejected(tx.unwrap());
    expect(body.queryId).toEqual(queryId);
    expect(body.exitCode).toEqual(expectedExitCode);
}

get fun `test order: should deploy`() {
    val fixture = setupOrderFixture();
    val data = fixture.order.getData();

    expect(data.multisigAddress).toEqual(fixture.multisig.address);
    expect(data.orderSeqno).toEqual(0);
    expect(data.threshold).toEqual(fixture.threshold);
    expect(data.sentForExecution).toEqual(false);
    expect(data.expirationDate).toEqual(fixture.expirationDate);
    expect(data.approvalsNum).toEqual(0);
    expect(data.approvalsMask).toEqual(0);

    val signers = mapToAddressArray(data.signersMap());
    expect(equalAddressArrays(signers, fixture.signers)).toEqual(true);
}

get fun `test order: should only accept init message from multisig`() {
    val fixture = setupOrderFixture();
    val nextOrder = MultisigV2Order.fromConfig(fixture.multisig.address, 1234);
    val outsider = net.treasury("order_outsider_init");

    val fail = nextOrder.deployWithInit(
        outsider.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        nowPlus(1000),
        fixture.orderBody,
        null,
        0,
        { value: ton("2"), bounce: true }
    );

    expect(fail).toHaveFailedTx<InitOrderRequest>({
        from: outsider.address,
        to: nextOrder.address,
        exitCode: ERROR_UNAUTHORIZED_INIT,
    });

    val before = nextOrder.getData();
    expect(before.isInitialized()).toEqual(false);
    expect(before.threshold).toBeNull();

    val ok = nextOrder.deployWithInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        nowPlus(1000),
        fixture.orderBody,
        null,
        0,
        { value: ton("2"), bounce: true }
    );
    expect(ok).toHaveSuccessfulTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: nextOrder.address,
    });

    val after = nextOrder.getData();
    expect(after.isInitialized()).toEqual(true);
    expect(after.threshold).toEqual(fixture.threshold);
}

get fun `test order: should reject already expired init message`() {
    val fixture = setupOrderFixture();
    val nextOrder = MultisigV2Order.fromConfig(fixture.multisig.address, 777);

    val fail = nextOrder.deployWithInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        net.now() - 1,
        fixture.orderBody,
        null,
        0,
        { value: ton("2"), bounce: true }
    );
    expect(fail).toHaveFailedTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: nextOrder.address,
        exitCode: ERROR_EXPIRED,
    });

    val dataBefore = nextOrder.getData();
    expect(dataBefore.isInitialized()).toEqual(false);

    val ok = nextOrder.deployWithInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        net.now(),
        fixture.orderBody,
        null,
        0,
        { value: ton("2"), bounce: true }
    );
    expect(ok).toHaveSuccessfulTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: nextOrder.address,
    });

    val dataAfter = nextOrder.getData();
    expect(dataAfter.isInitialized()).toEqual(true);
}

get fun `test order: order contract should accept init message only once if approve_on_init = false`() {
    val fixture = setupOrderFixture();

    val fail = fixture.order.sendInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        fixture.expirationDate,
        fixture.orderBody,
        null,
        0,
        { value: ton("2"), bounce: true }
    );

    expect(fail).toHaveFailedTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: fixture.order.address,
        exitCode: ERROR_ALREADY_INITED,
    });

    val data = fixture.order.getData();
    expect(data.approvalsNum).toEqual(0);
    expect(data.approvalsMask).toEqual(0);
}

get fun `test order: order contract should reject secondary init vote if any order info has changed`() {
    val fixture = setupOrderFixture();
    val signerIndex = 0 as uint8;

    val changedSigners = createSignerAddresses(fixture.signers.size(), createFundedAddress());

    val changedOrder = singleActionOrder(makeTransferAction(
        net.randomAddress("changed_order"),
        DEFAULT_TRANSFER_VALUE,
        777777
    ) as GenericOrderAction);

    val changedThreshold = fixture.threshold + 1;

    val failSigners = fixture.order.sendInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(changedSigners),
        fixture.expirationDate,
        fixture.orderBody,
        signerIndex,
        1,
        { value: ton("2"), bounce: true }
    );
    expect(failSigners).toHaveFailedTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: fixture.order.address,
        exitCode: ERROR_ALREADY_INITED,
    });

    val failExpiration = fixture.order.sendInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        fixture.expirationDate + 1,
        fixture.orderBody,
        signerIndex,
        2,
        { value: ton("2"), bounce: true }
    );
    expect(failExpiration).toHaveFailedTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: fixture.order.address,
        exitCode: ERROR_ALREADY_INITED,
    });

    val failOrder = fixture.order.sendInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        fixture.expirationDate,
        changedOrder,
        signerIndex,
        3,
        { value: ton("2"), bounce: true }
    );
    expect(failOrder).toHaveFailedTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: fixture.order.address,
        exitCode: ERROR_ALREADY_INITED,
    });

    val failThreshold = fixture.order.sendInit(
        fixture.multisig.address,
        changedThreshold,
        toAddressMap(fixture.signers),
        fixture.expirationDate,
        fixture.orderBody,
        signerIndex,
        4,
        { value: ton("2"), bounce: true }
    );
    expect(failThreshold).toHaveFailedTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: fixture.order.address,
        exitCode: ERROR_ALREADY_INITED,
    });

    val ok = fixture.order.sendInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        fixture.expirationDate,
        fixture.orderBody,
        signerIndex,
        5,
        { value: ton("2"), bounce: true }
    );
    expect(ok).toHaveSuccessfulTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: fixture.order.address,
    });

    val dataAfter = fixture.order.getData();
    expect(dataAfter.approvalsNum).toEqual(1);
    expect(approvalBit(dataAfter.approvalsMask, signerIndex)).toEqual(true);
}

get fun `test order: order contract should treat multiple init messages as votes if approve_on_init = true`() {
    val fixture = setupOrderFixture();

    var i = 0;
    while (i < fixture.threshold) {
        val res = fixture.order.sendInit(
            fixture.multisig.address,
            fixture.threshold,
            toAddressMap(fixture.signers),
            fixture.expirationDate,
            fixture.orderBody,
            i as uint8,
            i as uint64,
            { value: ton("2"), bounce: true }
        );

        expect(res).toHaveSuccessfulTx<InitOrderRequest>({
            from: fixture.multisig.address,
            to: fixture.order.address,
        });

        val data = fixture.order.getData();
        expect(data.approvalsNum).toEqual(i + 1);
        expect(approvalBit(data.approvalsMask, i)).toEqual(true);

        if (i + 1 == fixture.threshold) {
            expect(res).toHaveTx<ExecuteOrderRequest>({
                from: fixture.order.address,
                to: fixture.multisig.address,
            });
        }

        i += 1;
    }
}

get fun `test order: should not be possible to use multiple init msg to approve same idx twice`() {
    val fixture = setupOrderFixture();
    val signerIndex = 3;

    val first = fixture.order.sendInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        fixture.expirationDate,
        fixture.orderBody,
        signerIndex as uint8,
        100,
        { value: ton("2"), bounce: true }
    );
    expect(first).toHaveSuccessfulTx<InitOrderRequest>({
        from: fixture.multisig.address,
        to: fixture.order.address,
    });

    val dataBefore = fixture.order.getData();
    expect(dataBefore.approvalsNum).toEqual(1);
    expect(approvalBit(dataBefore.approvalsMask, signerIndex)).toEqual(true);

    val second = fixture.order.sendInit(
        fixture.multisig.address,
        fixture.threshold,
        toAddressMap(fixture.signers),
        fixture.expirationDate,
        fixture.orderBody,
        signerIndex as uint8,
        101,
        { value: ton("2"), bounce: true }
    );

    assertApproveRejected(
        second,
        fixture.order.address,
        fixture.signers.get(signerIndex),
        101,
        ERROR_ALREADY_APPROVED
    );

    val dataAfter = fixture.order.getData();
    expect(dataAfter.approvalsNum).toEqual(dataBefore.approvalsNum);
    expect(dataAfter.approvalsMask).toEqual(dataBefore.approvalsMask);
}

get fun `test order: should approve order`() {
    val fixture = setupOrderFixture();

    var i = 0;
    while (i < fixture.threshold) {
        val queryId = (1000 + i) as uint64;
        val signer = fixture.signers.get(i);

        val res = fixture.order.sendApprove(
            signer,
            i,
            queryId,
            { value: DEFAULT_APPROVE_VALUE, bounce: true }
        );

        assertApproveAccepted(res, fixture.order.address, signer, queryId);

        val data = fixture.order.getData();
        expect(data.approvalsNum).toEqual(i + 1);
        expect(approvalBit(data.approvalsMask, i)).toEqual(true);

        if (i + 1 == fixture.threshold) {
            expect(data.sentForExecution).toEqual(true);
            expect(res).toHaveTx<ExecuteOrderRequest>({
                from: fixture.order.address,
                to: fixture.multisig.address,
            });
        } else {
            expect(data.sentForExecution).toEqual(false);
            expect(res).toNotHaveTx<ExecuteOrderRequest>({
                from: fixture.order.address,
                to: fixture.multisig.address,
            });
        }

        i += 1;
    }
}

get fun `test order: should approve order with plain approve comment`() {
    val fixture = setupOrderFixture();
    val signer = fixture.signers.get(0);

    val res = fixture.order.sendAny(
        signer,
        makeApproveCommentBody("approve"),
        { value: ton("1"), bounce: true }
    );
    expect(res).toHaveSuccessfulTx<ApproveAccepted>({ from: fixture.order.address, to: signer });
}

get fun `test order: should approve order with approve comment in first ref`() {
    val fixture = setupOrderFixture();
    val signer = fixture.signers.get(1);

    val body = beginCell().storeUint(0, 32).storeRef(beginCell().storeSlice("approve".beginParse())
        .endCell())
        .endCell();
    val res = fixture.order.sendAny(signer, body, { value: ton("1"), bounce: true });
    expect(res).toHaveSuccessfulTx<ApproveAccepted>({ from: fixture.order.address, to: signer });
}

get fun `test order: should approve order with approve comment split in refs`() {
    val fixture = setupOrderFixture();
    val signer = fixture.signers.get(2);

    val chain = beginCell().storeSlice("a".beginParse()).storeRef(beginCell().storeSlice("p"
        .beginParse())
        .storeRef(beginCell().storeSlice("p".beginParse()).storeRef(beginCell().storeSlice("r"
        .beginParse())
        .storeRef(beginCell().storeSlice("o".beginParse()).storeRef(beginCell().storeSlice("v"
        .beginParse())
        .storeRef(beginCell().storeSlice("e".beginParse()).endCell())
        .endCell())
        .endCell())
        .endCell())
        .endCell())
        .endCell())
        .endCell();

    val body = beginCell().storeUint(0, 32).storeSlice(chain.beginParse()).endCell();
    val res = fixture.order.sendAny(signer, body, { value: ton("1"), bounce: true });
    expect(res).toHaveSuccessfulTx<ApproveAccepted>({ from: fixture.order.address, to: signer });
}

get fun `test order: should approve order with approve comment and empty refs in between`() {
    val fixture = setupOrderFixture();
    val signer = fixture.signers.get(3);

    val body = beginCell().storeUint(0, 32).storeSlice("ap".beginParse()).storeRef(beginCell()
        .storeRef(beginCell().storeSlice("prove".beginParse()).endCell())
        .endCell())
        .endCell();

    val res = fixture.order.sendAny(signer, body, { value: ton("1"), bounce: true });
    expect(res).toHaveSuccessfulTx<ApproveAccepted>({ from: fixture.order.address, to: signer });
}

get fun `test order: should reject non-approve comment payload`() {
    val fixture = setupOrderFixture();
    val signer = fixture.signers.get(4);

    val res = fixture.order.sendAny(
        signer,
        makeApproveCommentBody("approve not given"),
        { value: ton("1"), bounce: true }
    );
    expect(res).toHaveFailedTx<TextComment>({
        from: signer,
        to: fixture.order.address,
        exitCode: ERROR_UNKNOWN_OP,
    });
}

get fun `test order: should reject order with comment from not signer`() {
    val fixture = setupOrderFixture();
    val before = fixture.order.getData();

    val res = fixture.order.sendAny(
        fixture.notSigner.address,
        makeApproveCommentBody("approve"),
        { value: ton("1"), bounce: true }
    );

    expect(res).toHaveFailedTx<TextComment>({
        from: fixture.notSigner.address,
        to: fixture.order.address,
        exitCode: ERROR_UNAUTHORIZED_SIGN,
    });

    val after = fixture.order.getData();
    expect(after.approvalsNum).toEqual(before.approvalsNum);
    expect(after.approvalsMask).toEqual(before.approvalsMask);
}

get fun `test order: should accept approval only from signers`() {
    val fixture = setupOrderFixture();

    val signerIndex = 0;
    val legitSigner = fixture.signers.get(signerIndex);
    val outsiderAddress = createFundedAddress();

    val before = fixture.order.getData();

    val wrongAddress = fixture.order.sendApprove(
        outsiderAddress,
        signerIndex,
        200,
        { value: DEFAULT_APPROVE_VALUE, bounce: true }
    );
    expect(wrongAddress).toHaveFailedTx<ApproveRequest>({
        from: outsiderAddress,
        to: fixture.order.address,
        exitCode: ERROR_UNAUTHORIZED_SIGN,
    });

    val wrongIndex = fixture.order.sendApprove(
        legitSigner,
        signerIndex + 1,
        201,
        { value: DEFAULT_APPROVE_VALUE, bounce: true }
    );
    expect(wrongIndex).toHaveFailedTx<ApproveRequest>({
        from: legitSigner,
        to: fixture.order.address,
        exitCode: ERROR_UNAUTHORIZED_SIGN,
    });

    val invalidIndex = fixture.order.sendApprove(
        legitSigner,
        fixture.signers.size() + 5,
        202,
        { value: DEFAULT_APPROVE_VALUE, bounce: true }
    );
    expect(invalidIndex).toHaveFailedTx<ApproveRequest>({
        from: legitSigner,
        to: fixture.order.address,
        exitCode: ERROR_UNAUTHORIZED_SIGN,
    });

    val after = fixture.order.getData();
    expect(after.approvalsNum).toEqual(before.approvalsNum);
    expect(after.approvalsMask).toEqual(before.approvalsMask);
}

get fun `test order: should reject approval if already approved`() {
    val fixture = setupOrderFixture();

    var i = 0;
    while (i < 3) {
        val signer = fixture.signers.get(i);
        val firstQid = (3000 + i) as uint64;

        val accepted = fixture.order.sendApprove(
            signer,
            i,
            firstQid,
            { value: DEFAULT_APPROVE_VALUE, bounce: true }
        );
        assertApproveAccepted(accepted, fixture.order.address, signer, firstQid);

        val beforeRepeat = fixture.order.getData();

        val secondQid = (4000 + i) as uint64;
        val rejected = fixture.order.sendApprove(
            signer,
            i,
            secondQid,
            { value: DEFAULT_APPROVE_VALUE, bounce: true }
        );
        assertApproveRejected(
            rejected,
            fixture.order.address,
            signer,
            secondQid,
            ERROR_ALREADY_APPROVED
        );

        val afterRepeat = fixture.order.getData();
        expect(afterRepeat.approvalsNum).toEqual(beforeRepeat.approvalsNum);
        expect(afterRepeat.approvalsMask).toEqual(beforeRepeat.approvalsMask);

        i += 1;
    }
}

get fun `test order: should reject execution when executed once`() {
    val fixture = setupOrderFixture();

    var i = 0;
    while (i < fixture.threshold) {
        val signer = fixture.signers.get(i);
        val qid = (5000 + i) as uint64;

        val res = fixture.order.sendApprove(signer, i, qid, { value: ton("1"), bounce: true });
        assertApproveAccepted(res, fixture.order.address, signer, qid);

        if (i + 1 == fixture.threshold) {
            expect(res).toHaveTx<ExecuteOrderRequest>({
                from: fixture.order.address,
                to: fixture.multisig.address,
            });
        }

        i += 1;
    }

    val data = fixture.order.getData();
    expect(data.sentForExecution).toEqual(true);

    val lateSignerIndex = fixture.threshold;
    val lateSigner = fixture.signers.get(lateSignerIndex);

    val late = fixture.order.sendApprove(
        lateSigner,
        lateSignerIndex,
        6000,
        { value: ton("1"), bounce: true }
    );

    assertApproveRejected(late, fixture.order.address, lateSigner, 6000, ERROR_ALREADY_EXECUTED);
    expect(late).toNotHaveTx<ExecuteOrderRequest>({
        from: fixture.order.address,
        to: fixture.multisig.address,
    });
}

get fun `test order: should handle 255 signers`() {
    net.setNow(1000);

    val multisig = net.treasury("order_255_multisig");
    var signers = array<address> [];

    var i = 0;
    while (i < 255) {
        signers.push(createFundedAddress());
        i += 1;
    }

    val orderBody = singleActionOrder(makeTransferAction(
        net.randomAddress("order_255_target"),
        DEFAULT_TRANSFER_VALUE,
        42
    ) as GenericOrderAction);

    val jumboOrder = MultisigV2Order.fromConfig(multisig.address, 1);
    val deploy = jumboOrder.deployWithInit(
        multisig.address,
        255,
        toAddressMap(signers),
        nowPlus(1000),
        orderBody,
        null,
        0,
        { value: ton("20"), bounce: true }
    );

    expect(deploy).toHaveSuccessfulDeploy({ to: jumboOrder.address });

    var idx = 0;
    var lastRes = deploy;
    while (idx < signers.size()) {
        val signer = signers.get(idx);
        lastRes = jumboOrder.sendApprove(
            signer,
            idx,
            idx as uint64,
            { value: DEFAULT_APPROVE_VALUE, bounce: true }
        );

        assertApproveAccepted(lastRes, jumboOrder.address, signer, idx as uint64);

        val data = jumboOrder.getData();
        expect(data.approvalsNum).toEqual(idx + 1);
        expect(approvalBit(data.approvalsMask, idx)).toEqual(true);

        idx += 1;
    }

    expect(lastRes).toHaveTx<ExecuteOrderRequest>({ from: jumboOrder.address, to: multisig.address });
}
