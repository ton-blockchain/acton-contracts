import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "test-utils"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Multisig.gen"
import "../wrappers/Order.gen"
import "../wrappers/utils"

get fun `test multisig: should deploy`() {
    val ctx = setupMultisig();
    val data = ctx.multisig.getData();

    expect(data.threshold).toEqual(1);
    expect(data.nextOrderSeqno).toEqual(0);

    val signers = mapToAddressArray(data.signersMap());
    expect(equalAddressArrays(signers, ctx.signers)).toEqual(true);

    val proposers = mapToAddressArray(data.proposersMap());
    expect(equalAddressArrays(proposers, ctx.proposers)).toEqual(true);
}

get fun `test multisig: should support minimal one-of-one signer configuration`() {
    val ctx = setupMultisig(1, 1, 1, false);
    val data = ctx.multisig.getData();

    expect(data.threshold).toEqual(1);
    expect(data.nextOrderSeqno).toEqual(0);
    expect(equalAddressArrays(mapToAddressArray(data.signersMap()), ctx.signers)).toEqual(true);
    expect(equalAddressArrays(mapToAddressArray(data.proposersMap()), ctx.proposers)).toEqual(true);
}

get fun `test multisig: only signers and proposers should be able to create order`() {
    val ctx = setupMultisig();
    val order = singleActionOrder(makeTransferAction(randomAddress("create_order_target")));

    val seqnoBefore = ctx.multisig.getData().nextOrderSeqno;
    val expectedOrderAddress = ctx.multisig.getOrderAddress(seqnoBefore);

    val outsiderSigner = ctx
        .multisig
        .sendNewOrder(
            ctx.outsider.address,
            order,
            nowPlus(1000),
            true,
            0,
            MAX_ORDER_SEQNO,
            0,
            { value: DEFAULT_ORDER_CREATE_VALUE, bounce: true },
        );
    expect(outsiderSigner).toHaveFailedTx<NewOrderRequest>({
        from: ctx.outsider.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_NEW_ORDER,
    });
    expect(outsiderSigner).toNotHaveTx({
        from: ctx.multisig.address,
        to: expectedOrderAddress,
        deploy: true,
    });

    val outsiderProposer = ctx
        .multisig
        .sendNewOrder(
            ctx.outsider.address,
            order,
            nowPlus(1000),
            false,
            0,
            MAX_ORDER_SEQNO,
            1,
            { value: DEFAULT_ORDER_CREATE_VALUE, bounce: true },
        );
    expect(outsiderProposer).toHaveFailedTx<NewOrderRequest>({
        from: ctx.outsider.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_NEW_ORDER,
    });

    val proposerOrder = sendOrderByProposer(ctx, order, nowPlus(1000), 0);
    expect(proposerOrder).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.proposer.address,
        to: ctx.multisig.address,
    });
    expect(proposerOrder).toHaveSuccessfulDeploy({
        from: ctx.multisig.address,
        to: expectedOrderAddress,
    });
    expect(proposerOrder).toNotHaveTx<ExecuteOrderRequest>({
        from: expectedOrderAddress,
        to: ctx.multisig.address,
    });

    val seqnoAfterProposer = ctx.multisig.getData().nextOrderSeqno;
    val signerOrderAddress = ctx.multisig.getOrderAddress(seqnoAfterProposer);

    val proposerAsSigner = ctx
        .multisig
        .sendNewOrder(
            ctx.proposer.address,
            order,
            nowPlus(1000),
            true,
            0,
            MAX_ORDER_SEQNO,
            2,
            { value: DEFAULT_ORDER_CREATE_VALUE, bounce: true },
        );
    expect(proposerAsSigner).toHaveFailedTx<NewOrderRequest>({
        from: ctx.proposer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_NEW_ORDER,
    });

    val signerAsProposer = ctx
        .multisig
        .sendNewOrder(
            ctx.deployer.address,
            order,
            nowPlus(1000),
            false,
            0,
            MAX_ORDER_SEQNO,
            3,
            { value: DEFAULT_ORDER_CREATE_VALUE, bounce: true },
        );
    expect(signerAsProposer).toHaveFailedTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_NEW_ORDER,
    });

    val signerOrder = sendOrderBySigner(ctx, order, nowPlus(1000), 0);
    expect(signerOrder).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
    });
    expect(signerOrder).toHaveSuccessfulDeploy({
        from: ctx.multisig.address,
        to: signerOrderAddress,
    });
    expect(signerOrder).toHaveTx<ExecuteOrderRequest>({
        from: signerOrderAddress,
        to: ctx.multisig.address,
    });
}

get fun `test multisig: should reject new order with signer or proposer index outside configured range`() {
    val ctx = setupMultisig();
    val order = singleActionOrder(makeTransferAction(randomAddress("bad_index_target")));

    val signerSeqno = ctx.multisig.getData().nextOrderSeqno;
    val signerOrderAddress = ctx.multisig.getOrderAddress(signerSeqno);

    val badSignerIndex = ctx
        .multisig
        .sendNewOrder(
            ctx.deployer.address,
            order,
            nowPlus(1000),
            true,
            99,
            MAX_ORDER_SEQNO,
            0,
            { value: DEFAULT_ORDER_CREATE_VALUE, bounce: true },
        );
    expect(badSignerIndex).toHaveFailedTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_NEW_ORDER,
    });
    expect(badSignerIndex).toNotHaveTx({
        from: ctx.multisig.address,
        to: signerOrderAddress,
        deploy: true,
    });

    val proposerSeqno = ctx.multisig.getData().nextOrderSeqno;
    val proposerOrderAddress = ctx.multisig.getOrderAddress(proposerSeqno);

    val badProposerIndex = ctx
        .multisig
        .sendNewOrder(
            ctx.proposer.address,
            order,
            nowPlus(1000),
            false,
            99,
            MAX_ORDER_SEQNO,
            1,
            { value: DEFAULT_ORDER_CREATE_VALUE, bounce: true },
        );
    expect(badProposerIndex).toHaveFailedTx<NewOrderRequest>({
        from: ctx.proposer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_NEW_ORDER,
    });
    expect(badProposerIndex).toNotHaveTx({
        from: ctx.multisig.address,
        to: proposerOrderAddress,
        deploy: true,
    });
}

get fun `test multisig: order expiration time should exceed current time`() {
    val ctx = setupMultisig();
    val order = singleActionOrder(makeTransferAction(randomAddress("expired_target")));

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val res = sendOrderBySigner(ctx, order, testing.getNow() - 100, 0);
    expect(res).toHaveFailedTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_EXPIRED,
    });
    expect(res).toNotHaveTx({ from: ctx.multisig.address, to: orderAddress });
}

get fun `test multisig: should allow order creation when expiration equals current time`() {
    val ctx = setupMultisig();
    val target = randomAddress("expiration_now_target");
    val order = singleActionOrder(makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 0x414141));

    val expiration = testing.getNow();
    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val res = sendOrderBySigner(
        ctx,
        order,
        expiration,
        0,
        MAX_ORDER_SEQNO,
        ton("3"),
    );

    expect(res).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });
    expect(res).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
    });
    expect(res).toHaveTx({
        from: ctx.multisig.address,
        to: target,
        body: markerBody(0x414141),
        value: DEFAULT_TRANSFER_VALUE,
    });
}

get fun `test multisig: should reject order creation with insufficient incoming value`() {
    val ctx = setupMultisig();
    val order = singleActionOrder(makeTransferAction(randomAddress("value_target")));

    val expiration = 2000000000;
    val estimate = ctx.multisig.getOrderEstimateForOrder(order, expiration);

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val res = sendOrderBySigner(
        ctx,
        order,
        expiration,
        0,
        MAX_ORDER_SEQNO,
        (estimate / 2),
    );

    expect(res).toHaveFailedTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_NOT_ENOUGH_TON,
    });
    expect(res).toNotHaveTx({ from: ctx.multisig.address, to: orderAddress });
}

get fun `test multisig: should enforce the received-value boundary for order creation`() {
    val target = randomAddress("exact_boundary_target");
    val order = singleActionOrder(makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 0x515151));
    val expiration = 2000000000;
    // Freeze the known raw boundary for this deterministic fixture instead of
    // deriving it from the runtime under test, otherwise boundary mutants self-heal.
    val exactRawValue = 417465815;

    val failCtx = setupMultisig();
    val failSeqno = failCtx.multisig.getData().nextOrderSeqno;
    val failOrderAddress = failCtx.multisig.getOrderAddress(failSeqno);
    val fail = sendOrderBySigner(
        failCtx,
        order,
        expiration,
        0,
        MAX_ORDER_SEQNO,
        exactRawValue - 1,
    );

    expect(fail).toHaveFailedTx<NewOrderRequest>({
        from: failCtx.deployer.address,
        to: failCtx.multisig.address,
        exitCode: ERROR_NOT_ENOUGH_TON,
    });
    expect(fail).toNotHaveTx({ from: failCtx.multisig.address, to: failOrderAddress });

    val passCtx = setupMultisig();
    val passSeqno = passCtx.multisig.getData().nextOrderSeqno;
    val passOrderAddress = passCtx.multisig.getOrderAddress(passSeqno);
    val pass = sendOrderBySigner(
        passCtx,
        order,
        expiration,
        0,
        MAX_ORDER_SEQNO,
        exactRawValue,
    );

    expect(pass).toHaveSuccessfulDeploy({ from: passCtx.multisig.address, to: passOrderAddress });
    expect(pass).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: passOrderAddress,
        to: passCtx.multisig.address,
    });
    expect(pass).toHaveTx({
        from: passCtx.multisig.address,
        to: target,
        body: markerBody(0x515151),
        value: DEFAULT_TRANSFER_VALUE,
    });
}

get fun `test multisig: deployed order state should match requested`() {
    val ctx = setupMultisig(7, 12, 8, false);
    val recipient = randomAddress("order_state_target");
    val orderBody = singleActionOrder(makeTransferAction(recipient, DEFAULT_TRANSFER_VALUE, 9876));

    val signerIndex = 3;
    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val res = sendOrderBySigner(ctx, orderBody, nowPlus(1000), signerIndex);
    expect(res).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });

    val order = Order.fromAddress(orderAddress);
    val orderData = order.getData();

    expect(orderData.multisigAddress).toEqual(ctx.multisig.address);
    expect(orderData.threshold).toEqual(ctx.threshold);
    expect(orderData.sentForExecution).toEqual(false);
    expect(orderData.approvalsNum).toEqual(1);
    expect(orderData.expirationDate).toEqual(nowPlus(1000));

    val signers = mapToAddressArray(orderData.signersMap());
    expect(equalAddressArrays(signers, ctx.signers)).toEqual(true);
}

get fun `test multisig: should execute new message order`() {
    val ctx = setupMultisig();
    val target = randomAddress("execute_target");
    val marker = 12345;
    val action = makeTransferAction(target, DEFAULT_TRANSFER_VALUE, marker);
    val order = singleActionOrder(action);

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val res = sendOrderBySigner(ctx, order, nowPlus(100));

    expect(res).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
    });
    expect(res).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });
    expect(res).toHaveTx({
        from: ctx.multisig.address,
        to: target,
        body: markerBody(marker),
        value: DEFAULT_TRANSFER_VALUE,
    });
}

get fun `test multisig: expired order execution should be denied`() {
    val ctx = setupMultisig();
    val target = randomAddress("expired_exec_target");
    val action = makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 100500);
    val orderBody = singleActionOrder(action);

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val deploy = sendOrderByProposer(ctx, orderBody, nowPlus(1));
    expect(deploy).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });

    testing.setNow(testing.getNow() + 2);
    val order = Order.fromAddress(orderAddress);
    val approve = order.sendApprove(ctx.signers.get(0), 0, 1, { value: ton("1"), bounce: true });

    expect(approve).toHaveFailedTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
        exitCode: ERROR_EXPIRED,
    });

    val orderData = order.getData();
    expect(orderData.sentForExecution).toEqual(true);

    assertOrderNotExecuted(approve, ctx.multisig.address, target);
}

get fun `test multisig: order execution at exact expiration should succeed`() {
    val ctx = setupMultisig();
    val target = randomAddress("exact_exec_target");
    val orderBody = singleActionOrder(makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 0x616161));

    val expiration = nowPlus(10);
    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val deploy = sendOrderByProposer(ctx, orderBody, expiration);
    expect(deploy).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });

    testing.setNow(expiration);
    val order = Order.fromAddress(orderAddress);
    val approve = order.sendApprove(ctx.signers.get(0), 0, 77, { value: ton("1"), bounce: true });

    expect(approve).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
    });
    expect(approve).toHaveTx({
        from: ctx.multisig.address,
        to: target,
        body: markerBody(0x616161),
    });
}

get fun `test multisig: should be possible to execute order by post init approval`() {
    val ctx = setupMultisig();
    val target = randomAddress("post_approve_target");
    val action = makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 6789);
    val orderBody = singleActionOrder(action);

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val deploy = sendOrderByProposer(ctx, orderBody, nowPlus(1000));
    expect(deploy).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });

    val order = Order.fromAddress(orderAddress);
    val before = order.getData();
    expect(before.approvalsNum).toEqual(0);
    expect(before.sentForExecution).toEqual(false);

    val approve = order.sendApprove(ctx.signers.get(0), 0, 0, { value: ton("1"), bounce: true });

    expect(approve).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
    });
    expect(approve).toHaveTx({
        from: ctx.multisig.address,
        to: target,
        body: markerBody(6789),
    });
}

get fun `test multisig: multisig-created order should persist approvals and reject duplicates`() {
    val ctx = setupMultisig(2, 3, 1, false);
    val target = randomAddress("embedded_dup_target");
    val orderBody = singleActionOrder(makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 0x717171));

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val create = sendOrderByProposer(ctx, orderBody, nowPlus(1000));
    expect(create).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });

    val order = Order.fromAddress(orderAddress);
    val signer = ctx.signers.get(1);

    val first = order.sendApprove(signer, 1, 11, { value: ton("1"), bounce: true });
    expect(first).toHaveTx<ApproveAccepted>({ from: orderAddress, to: signer });
    expect(first).toNotHaveTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
    });

    val afterFirst = order.getData();
    expect(afterFirst.approvalsNum).toEqual(1);
    expect(approvalBit(afterFirst.approvalsMask, 1)).toEqual(true);
    expect(afterFirst.sentForExecution).toEqual(false);

    val duplicate = order.sendApprove(signer, 1, 12, { value: ton("1"), bounce: true });
    expect(duplicate).toHaveTx<ApproveRejected>({ from: orderAddress, to: signer });
    val duplicateTx = duplicate.findTransaction<ApproveRejected>({
        from: orderAddress,
        to: signer,
    });
    expect(duplicateTx).toBeNotNull();
    val duplicateBody = loadApproveRejected(duplicateTx!);
    expect(duplicateBody.queryId).toEqual(12);
    expect(duplicateBody.exitCode).toEqual(ERROR_ALREADY_APPROVED);

    val afterDuplicate = order.getData();
    expect(afterDuplicate.approvalsNum).toEqual(afterFirst.approvalsNum);
    expect(afterDuplicate.approvalsMask).toEqual(afterFirst.approvalsMask);
}

get fun `test multisig: multisig-created order should resolve comment approvals and reject late approvals`() {
    val ctx = setupMultisig(2, 3, 1, false);
    val target = randomAddress("embedded_comment_target");
    val orderBody = singleActionOrder(makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 0x727272));

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val create = sendOrderByProposer(ctx, orderBody, nowPlus(1000));
    expect(create).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });

    val order = Order.fromAddress(orderAddress);
    val before = order.getData();

    val outsider = order.sendAny(
        ctx.outsider.address,
        makeApproveCommentBody("approve"),
        { value: ton("1"), bounce: true },
    );
    expect(outsider).toHaveFailedTx<TextComment>({
        from: ctx.outsider.address,
        to: order.address,
        exitCode: ERROR_UNAUTHORIZED_SIGN,
    });

    val afterOutsider = order.getData();
    expect(afterOutsider.approvalsNum).toEqual(before.approvalsNum);
    expect(afterOutsider.approvalsMask).toEqual(before.approvalsMask);

    val first = order.sendAny(
        ctx.signers.get(0),
        makeApproveCommentBody("approve"),
        { value: ton("1"), bounce: true },
    );
    expect(first).toHaveTx<ApproveAccepted>({
        from: order.address,
        to: ctx.signers.get(0),
    });
    expect(first).toNotHaveTx<ExecuteOrderRequest>({
        from: order.address,
        to: ctx.multisig.address,
    });

    val afterFirst = order.getData();
    expect(afterFirst.approvalsNum).toEqual(1);
    expect(approvalBit(afterFirst.approvalsMask, 0)).toEqual(true);
    expect(afterFirst.sentForExecution).toEqual(false);

    val second = order.sendApprove(ctx.signers.get(1), 1, 21, { value: ton("1"), bounce: true });
    expect(second).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: order.address,
        to: ctx.multisig.address,
    });
    expect(second).toHaveTx({
        from: ctx.multisig.address,
        to: target,
        body: markerBody(0x727272),
    });

    val afterSecond = order.getData();
    expect(afterSecond.approvalsNum).toEqual(2);
    expect(approvalBit(afterSecond.approvalsMask, 1)).toEqual(true);
    expect(afterSecond.sentForExecution).toEqual(true);

    val late = order.sendApprove(ctx.signers.get(2), 2, 22, { value: ton("1"), bounce: true });
    expect(late).toHaveTx<ApproveRejected>({
        from: order.address,
        to: ctx.signers.get(2),
    });
    val lateTx = late.findTransaction<ApproveRejected>({
        from: order.address,
        to: ctx.signers.get(2),
    });
    expect(lateTx).toBeNotNull();
    val lateBody = loadApproveRejected(lateTx!);
    expect(lateBody.queryId).toEqual(22);
    expect(lateBody.exitCode).toEqual(ERROR_ALREADY_EXECUTED);
    expect(late).toNotHaveTx<ExecuteOrderRequest>({
        from: order.address,
        to: ctx.multisig.address,
    });
}

get fun `test multisig: order estimate should work`() {
    val ctx = setupMultisig();
    val order = singleActionOrder(makeTransferAction(randomAddress("estimate_target")));

    val oneHour = ctx.multisig.getOrderEstimateForOrder(order, 2000003600);
    val oneYear = ctx.multisig.getOrderEstimateForOrder(order, 2031536000);

    expect(oneHour).toBeGreater(0);
    expect(oneYear).toBeGreater(oneHour);
}

get fun `test multisig: should send new order with many actions in specified order`() {
    val ctx = setupMultisig();
    val target1 = randomAddress("ordered_target_1");
    val target2 = randomAddress("ordered_target_2");

    val action1 = makeTransferAction(target1, ton("0.015"), 12345);
    val action2 = makeTransferAction(target2, ton("0.016"), 12346);

    val order12 = pairActionsOrder(action1, action2);
    val res12 = sendOrderBySigner(ctx, order12, nowPlus(1000));

    val tx1Lt = getTxLt(
        res12,
        {
            from: ctx.multisig.address,
            to: target1,
            body: markerBody(12345),
        },
    );
    val tx2Lt = getTxLt(
        res12,
        {
            from: ctx.multisig.address,
            to: target2,
            body: markerBody(12346),
        },
    );
    expect(tx2Lt).toBeGreater(tx1Lt);

    val order21 = pairActionsOrder(action2, action1);
    val res21 = sendOrderBySigner(ctx, order21, nowPlus(1000));

    val tx1LtInv = getTxLt(
        res21,
        {
            from: ctx.multisig.address,
            to: target1,
            body: markerBody(12345),
        },
    );
    val tx2LtInv = getTxLt(
        res21,
        {
            from: ctx.multisig.address,
            to: target2,
            body: markerBody(12346),
        },
    );
    expect(tx2LtInv).toBeLess(tx1LtInv);
}

get fun `test multisig: should execute update multisig parameters correctly`() {
    val ctx = setupMultisig();

    var newSigners = array<address> [];
    var i = 0;
    while (i < 4) {
        newSigners.push(createFundedAddress());
        i += 1;
    }

    val update = makeUpdateAction(4, newSigners, []);
    val order = singleActionOrder(update);

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val res = sendOrderBySigner(ctx, order, nowPlus(1000));
    expect(res).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });
    expect(res).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
    });

    val data = ctx.multisig.getData();
    expect(data.threshold).toEqual(4);

    val signersAfter = mapToAddressArray(data.signersMap());
    expect(equalAddressArrays(signersAfter, newSigners)).toEqual(true);

    val proposersAfter = mapToAddressArray(data.proposersMap());
    expect(proposersAfter.size()).toEqual(0);
}

get fun `test multisig: should reject update multisig parameters when threshold exceeds signer count`() {
    val ctx = setupMultisig();
    val beforeTooHigh = ctx.multisig.getData();
    val orderAddrTooHigh = ctx.multisig.getOrderAddress(beforeTooHigh.nextOrderSeqno);
    val tooHighUpdate = makeUpdateAction(
        3,
        array<address> [ctx.signers.get(0), ctx.signers.get(1)],
        mapToAddressArray(beforeTooHigh.proposersMap()),
    );
    val tooHighOrder = singleActionOrder(tooHighUpdate);

    val failTooHigh = sendOrderBySigner(ctx, tooHighOrder, nowPlus(1000));
    expect(failTooHigh).toHaveFailedTx<ExecuteOrderRequest>({
        from: orderAddrTooHigh,
        to: ctx.multisig.address,
        exitCode: ERROR_INVALID_THRESHOLD,
    });

    val afterTooHigh = ctx.multisig.getData();
    expect(afterTooHigh.threshold).toEqual(beforeTooHigh.threshold);
    expect(
        equalAddressArrays(
            mapToAddressArray(afterTooHigh.signersMap()),
            mapToAddressArray(beforeTooHigh.signersMap()),
        ),
    ).toEqual(true);
}

get fun `test multisig: should reject multisig parameters with inconsistently ordered signers or proposers`() {
    val ctx = setupMultisig();

    var malformedSigners: DirectIndexedAddressMap = [];
    malformedSigners.set(0, createFundedAddress());
    malformedSigners.set(2, createFundedAddress());

    val malformedSignersAction = UpdateMultisigParamsAction {
        threshold: 1,
        signers: malformedSigners,
        proposers: [],
    };

    var actionCells = array<cell> [];
    actionCells.push(malformedSignersAction.toCell());
    val malformedSignersOrder = packActionCells(actionCells);

    val before1 = ctx.multisig.getData();
    val seqno1 = before1.nextOrderSeqno;
    val orderAddr1 = ctx.multisig.getOrderAddress(seqno1);

    val failSigners = sendOrderBySigner(ctx, malformedSignersOrder, nowPlus(100));
    expect(failSigners).toHaveFailedTx<ExecuteOrderRequest>({
        from: orderAddr1,
        to: ctx.multisig.address,
        exitCode: ERROR_INVALID_DICTIONARY_SEQUENCE,
    });

    val after1 = ctx.multisig.getData();
    expect(after1.nextOrderSeqno).toEqual(before1.nextOrderSeqno + 1);
    expect(after1.threshold).toEqual(before1.threshold);
    expect(
        equalAddressArrays(
            mapToAddressArray(after1.signersMap()),
            mapToAddressArray(before1.signersMap()),
        ),
    ).toEqual(true);

    var malformedProposers: IndexedAddressMap = [];
    malformedProposers.set(1, createFundedAddress());
    malformedProposers.set(2, createFundedAddress());

    val malformedProposersAction = UpdateMultisigParamsAction {
        threshold: after1.threshold,
        signers: after1.signersMap(),
        proposers: malformedProposers,
    };

    actionCells = [];
    actionCells.push(malformedProposersAction.toCell());
    val malformedProposersOrder = packActionCells(actionCells);

    val before2 = ctx.multisig.getData();
    val seqno2 = before2.nextOrderSeqno;
    val orderAddr2 = ctx.multisig.getOrderAddress(seqno2);

    val failProposers = sendOrderBySigner(ctx, malformedProposersOrder, nowPlus(100));
    expect(failProposers).toHaveFailedTx<ExecuteOrderRequest>({
        from: orderAddr2,
        to: ctx.multisig.address,
        exitCode: ERROR_INVALID_DICTIONARY_SEQUENCE,
    });

    val after2 = ctx.multisig.getData();
    expect(after2.nextOrderSeqno).toEqual(before2.nextOrderSeqno + 1);
    expect(after2.threshold).toEqual(before2.threshold);
    expect(
        equalAddressArrays(
            mapToAddressArray(after2.signersMap()),
            mapToAddressArray(before2.signersMap()),
        ),
    ).toEqual(true);
    expect(
        equalAddressArrays(
            mapToAddressArray(after2.proposersMap()),
            mapToAddressArray(before2.proposersMap()),
        ),
    ).toEqual(true);
}

get fun `test multisig: should accept execute internal only from self address`() {
    val ctx = setupMultisig();

    val recipient = randomAddress("execute_internal_recipient");
    val innerOrder = singleActionOrder(makeTransferAction(recipient, ton("0.01"), 0x12345));

    val resSigner = ctx
        .multisig
        .sendExecuteInternal(
            ctx.deployer.address,
            innerOrder,
            0,
            { value: ton("1"), bounce: true },
        );
    expect(resSigner).toHaveFailedTx<ExecuteInternalRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_EXECUTE,
    });

    val resProposer = ctx
        .multisig
        .sendExecuteInternal(
            ctx.proposer.address,
            innerOrder,
            0,
            { value: ton("1"), bounce: true },
        );
    expect(resProposer).toHaveFailedTx<ExecuteInternalRequest>({
        from: ctx.proposer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_EXECUTE,
    });

    val resOutsider = ctx
        .multisig
        .sendExecuteInternal(
            ctx.outsider.address,
            innerOrder,
            0,
            { value: ton("1"), bounce: true },
        );
    expect(resOutsider).toHaveFailedTx<ExecuteInternalRequest>({
        from: ctx.outsider.address,
        to: ctx.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_EXECUTE,
    });

    expect(resSigner).toNotHaveTx({ from: ctx.multisig.address, to: recipient });
    expect(resProposer).toNotHaveTx({ from: ctx.multisig.address, to: recipient });
    expect(resOutsider).toNotHaveTx({ from: ctx.multisig.address, to: recipient });
}

get fun `test multisig: chained execution should work`() {
    val ctx = setupMultisig();

    val chainedRecipient = randomAddress("chained_recipient");
    val innerOrder = singleActionOrder(makeTransferAction(chainedRecipient, ton("0.01"), 0x22222));

    val triggerBody = ExecuteInternalRequest {
        queryId: 0,
        order: innerOrder,
    }.toCell();
    val trigger = makeTransferActionWithBody(
        ctx.multisig.address,
        ton("0.01"),
        triggerBody,
        SEND_MODE_PAY_FEES_SEPARATELY,
        true,
    );

    val order = singleActionOrder(trigger);

    val res = sendOrderBySigner(
        ctx,
        order,
        nowPlus(1000),
        0,
        MAX_ORDER_SEQNO,
        ton("3"),
    );

    expect(res).toHaveSuccessfulTx<ExecuteInternalRequest>({
        from: ctx.multisig.address,
        to: ctx.multisig.address,
    });
    expect(res).toHaveTx({
        from: ctx.multisig.address,
        to: chainedRecipient,
        body: markerBody(0x22222),
    });
}

get fun `test multisig: chained execution should persist storage updates`() {
    val ctx = setupMultisig();

    val updatedSigners = array<address> [ctx.deployer.address, ctx.outsider.address];
    val updatedProposers = ctx.proposers;
    val innerOrder = singleActionOrder(makeUpdateAction(2, updatedSigners, updatedProposers));

    val triggerBody = ExecuteInternalRequest {
        queryId: 0,
        order: innerOrder,
    }.toCell();
    val trigger = makeTransferActionWithBody(
        ctx.multisig.address,
        ton("0.01"),
        triggerBody,
        SEND_MODE_PAY_FEES_SEPARATELY,
        true,
    );

    val order = singleActionOrder(trigger);
    val res = sendOrderBySigner(
        ctx,
        order,
        nowPlus(1000),
        0,
        MAX_ORDER_SEQNO,
        ton("3"),
    );

    expect(res).toHaveSuccessfulTx<ExecuteInternalRequest>({
        from: ctx.multisig.address,
        to: ctx.multisig.address,
    });

    val data = ctx.multisig.getData();
    expect(data.threshold).toEqual(2);
    expect(equalAddressArrays(mapToAddressArray(data.signersMap()), updatedSigners)).toEqual(true);
    expect(equalAddressArrays(mapToAddressArray(data.proposersMap()), updatedProposers)).toEqual(
        true,
    );
}

get fun `test multisig: multisig should invalidate previous orders if signers change`() {
    val ctx = setupMultisig();

    val pendingOrder = singleActionOrder(
        makeTransferAction(ctx.multisig.address, DEFAULT_TRANSFER_VALUE, 11111),
    );

    val pendingSeqno = ctx.multisig.getData().nextOrderSeqno;
    val pendingOrderAddress = ctx.multisig.getOrderAddress(pendingSeqno);

    val deployed = sendOrderByProposer(ctx, pendingOrder, nowPlus(1000));
    expect(deployed).toHaveSuccessfulDeploy({
        from: ctx.multisig.address,
        to: pendingOrderAddress,
    });

    val oldData = ctx.multisig.getData();
    val updatedSigners = array<address> [createFundedAddress()];
    val update = makeUpdateAction(
        oldData.threshold,
        updatedSigners,
        mapToAddressArray(oldData.proposersMap()),
    );

    val updateOrder = singleActionOrder(update);
    val updateRes = sendOrderBySigner(ctx, updateOrder, nowPlus(1000));
    expect(updateRes).toHaveSuccessfulTx<ExecuteOrderRequest>({ to: ctx.multisig.address });

    val order = Order.fromAddress(pendingOrderAddress);
    val approveOld = order.sendApprove(ctx.signers.get(0), 0, 9, { value: ton("1"), bounce: true });

    expect(approveOld).toHaveFailedTx<ExecuteOrderRequest>({
        from: pendingOrderAddress,
        to: ctx.multisig.address,
        exitCode: ERROR_SIGNERS_OUTDATED,
    });
}

get fun `test multisig: multisig should invalidate previous orders if threshold increased`() {
    val ctx = setupMultisig(1, 3, 1, false);

    val pendingOrder = singleActionOrder(
        makeTransferAction(ctx.multisig.address, DEFAULT_TRANSFER_VALUE, 22222),
    );

    val pendingSeqno = ctx.multisig.getData().nextOrderSeqno;
    val pendingOrderAddress = ctx.multisig.getOrderAddress(pendingSeqno);

    val deployed = sendOrderByProposer(ctx, pendingOrder, nowPlus(1000));
    expect(deployed).toHaveSuccessfulDeploy({
        from: ctx.multisig.address,
        to: pendingOrderAddress,
    });

    val dataBefore = ctx.multisig.getData();
    val update = makeUpdateAction(2, ctx.signers, mapToAddressArray(dataBefore.proposersMap()));
    val updateOrder = singleActionOrder(update);
    sendOrderBySigner(ctx, updateOrder, nowPlus(1000));

    val order = Order.fromAddress(pendingOrderAddress);
    val approveOld = order.sendApprove(
        ctx.signers.get(0),
        0,
        10,
        { value: ton("1"), bounce: true },
    );

    expect(approveOld).toHaveFailedTx<ExecuteOrderRequest>({
        from: pendingOrderAddress,
        to: ctx.multisig.address,
        exitCode: ERROR_SIGNERS_OUTDATED,
    });
}

get fun `test multisig: multisig should not execute orders deployed by other multisig contract`() {
    val legit = setupMultisig();
    val hackerDeployer = testing.treasury("evil-msig-deployer");
    val hackerProposer = testing.treasury("evil-msig-proposer");
    val hackerSigners = array<address> [hackerDeployer.address, createFundedAddress()];
    val hackerProposers = array<address> [hackerProposer.address];
    val hackerMultisig = Multisig.fromConfig(1, hackerSigners, hackerProposers, false);

    val hackerDeploy = hackerMultisig.deployWithInitBody(
        hackerDeployer.address,
        { value: ton("10"), bounce: false },
    );
    expect(hackerDeploy).toHaveSuccessfulDeploy({ to: hackerMultisig.address });

    val hackerWallet = testing.treasury("cool-hacker");

    val legitData = legit.multisig.getData();
    val legitSignersHash = legitData.signersMap().hashCell();

    val evilPayload = singleActionOrder(
        makeTransferAction(hackerWallet.address, ton("100000"), 1337),
    );

    val execBody = ExecuteOrderRequest {
        queryId: 0,
        orderSeqno: legitData.nextOrderSeqno,
        expirationDate: 0xffffffffffff,
        approvalsNum: 255,
        signersHash: legitSignersHash,
        order: evilPayload,
    }.toCell();

    val trigger = makeTransferActionWithBody(
        legit.multisig.address,
        ton("0.01"),
        execBody,
        SEND_MODE_PAY_FEES_SEPARATELY,
        true,
    );

    val evilOrder = singleActionOrder(trigger);
    val _evilOrderAddress = hackerMultisig.getOrderAddress(0);

    val res = hackerMultisig.sendNewOrder(
        hackerSigners.get(0),
        evilOrder,
        nowPlus(1000),
        true,
        0,
        MAX_ORDER_SEQNO,
        0,
        { value: ton("3"), bounce: true },
    );

    expect(res).toHaveFailedTx<ExecuteOrderRequest>({
        from: hackerMultisig.address,
        to: legit.multisig.address,
        exitCode: ERROR_UNAUTHORIZED_EXECUTE,
    });
    expect(res).toNotHaveTx({ from: legit.multisig.address, to: hackerWallet.address });
}

get fun `test multisig: should handle more than 255 orders`() {
    val ctx = setupMultisig();

    val orderCount = 300;
    var rootOrder: DirectOrderActionsMap = [];
    var tailOrder: DirectOrderActionsMap = [];

    var i = 0;
    while (i < 253) {
        rootOrder.set(
            i,
            makeTransferAction(
                ctx.deployer.address,
                ton("0.01"),
                i,
                SEND_MODE_PAY_FEES_SEPARATELY,
                true,
            ).toCell(),
        );
        i += 1;
    }

    var marker = 253;
    var tailIdx = 0;
    while (marker < orderCount) {
        tailOrder.set(
            tailIdx,
            makeTransferAction(
                ctx.deployer.address,
                ton("0.01"),
                marker,
                SEND_MODE_PAY_FEES_SEPARATELY,
                true,
            ).toCell(),
        );
        marker += 1;
        tailIdx += 1;
    }

    val chainBody = ExecuteInternalRequest {
        queryId: 0,
        order: tailOrder,
    }.toCell();
    rootOrder.set(
        253,
        makeTransferActionWithBody(
            ctx.multisig.address,
            ton("0.01"),
            chainBody,
            SEND_MODE_PAY_FEES_SEPARATELY,
            true,
        ).toCell(),
    );

    val res = sendOrderBySigner(
        ctx,
        rootOrder,
        nowPlus(1000),
        0,
        MAX_ORDER_SEQNO,
        ton("500"),
    );

    expect(res).toHaveTx<ExecuteOrderRequest>({ to: ctx.multisig.address, success: true });
    expect(res).toHaveTx<ExecuteInternalRequest>({
        from: ctx.multisig.address,
        to: ctx.multisig.address,
    });

    var previousLt = 0;
    var idx = 0;
    while (idx < orderCount) {
        val currentLt = getTxLt(
            res,
            {
                from: ctx.multisig.address,
                to: ctx.deployer.address,
                body: markerBody(idx),
            },
        );
        expect(currentLt).toBeGreater(previousLt);
        previousLt = currentLt;
        idx += 1;
    }
}
