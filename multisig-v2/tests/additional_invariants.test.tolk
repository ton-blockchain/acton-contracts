import "test_utils"
import "wrappers/MultisigV2Order"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/errors"
import "../contracts/messages"

get fun `test invariants: multisig unknown opcode should keep state unchanged`() {
    val ctx = setupMultisig(2, 3, 1, false);
    val before = ctx.multisig.getData();

    val unknownBody = beginCell().storeUint(0xdeadbeef, 32).storeUint(123, 64).endCell();
    val res = ctx.multisig.sendAny(
        ctx.outsider.address,
        unknownBody,
        { value: ton("1"), bounce: true }
    );

    expect(res).toHaveSuccessfulTx({ from: ctx.outsider.address, to: ctx.multisig.address });

    val after = ctx.multisig.getData();
    expect(after.nextOrderSeqno).toEqual(before.nextOrderSeqno);
    expect(after.threshold).toEqual(before.threshold);
    expect(equalAddressArrays(
        mapToAddressArray(after.signersMap()),
        mapToAddressArray(before.signersMap())
    ))
        .toEqual(true);
    expect(equalAddressArrays(
        mapToAddressArray(after.proposersMap()),
        mapToAddressArray(before.proposersMap())
    ))
        .toEqual(true);
}

get fun `test invariants: order unknown opcode should fail with ERROR_UNKNOWN_OP`() {
    net.setNow(1000);
    val multisig = net.treasury("inv_order_multisig");

    var signers = array<address> [];
    signers.push(createFundedAddress());
    signers.push(createFundedAddress());

    val orderBody = singleActionOrder(makeTransferAction(
        net.randomAddress("inv_order_target"),
        DEFAULT_TRANSFER_VALUE,
        111
    ) as GenericOrderAction);

    val order = MultisigV2Order.fromConfig(multisig.address, 0);
    val deploy = order.deployWithInit(
        multisig.address,
        2,
        toAddressMap(signers),
        nowPlus(1000),
        orderBody,
        null,
        0,
        { value: ton("2"), bounce: true }
    );
    expect(deploy).toHaveSuccessfulDeploy({ to: order.address });

    val unknownBody = beginCell().storeUint(0xdeadbeef, 32).storeUint(0, 64).endCell();
    val res = order.sendAny(signers.get(0), unknownBody, { value: ton("1"), bounce: true });

    expect(res).toHaveFailedTx({
        from: signers.get(0),
        to: order.address,
        exitCode: ERROR_UNKNOWN_OP,
    });
}

get fun `test invariants: proposer compromise does not allow approvals`() {
    val ctx = setupMultisig(2, 2, 1, false);

    val target = net.randomAddress("proposer_compromise_target");
    val orderBody = singleActionOrder(makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 123123) as GenericOrderAction);

    val seqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(seqno);

    val create = sendOrderByProposer(ctx, orderBody, nowPlus(1000));
    expect(create).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });

    val order = MultisigV2Order.fromAddress(orderAddress);

    val proposerApprove = order.sendApprove(
        ctx.proposer.address,
        0,
        10,
        { value: ton("0.2"), bounce: true }
    );
    expect(proposerApprove).toHaveFailedTx<ApproveRequest>({
        from: ctx.proposer.address,
        to: orderAddress,
        exitCode: ERROR_UNAUTHORIZED_SIGN,
    });

    val approve0 = order.sendApprove(ctx.signers.get(0), 0, 11, { value: ton("0.2"), bounce: true });
    expect(approve0).toHaveSuccessfulTx<ApproveAccepted>({
        from: orderAddress,
        to: ctx.signers.get(0),
    });

    val approve1 = order.sendApprove(ctx.signers.get(1), 1, 12, { value: ton("0.2"), bounce: true });
    expect(approve1).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
    });
    expect(approve1).toHaveSuccessfulTx({
        from: ctx.multisig.address,
        to: target,
        body: markerBody(123123),
    });
}

get fun `test invariants: less than threshold compromised signers can be removed`() {
    val ctx = setupMultisig(2, 3, 1, false);

    val cleanSigners = array<address> [ctx.signers.get(1), ctx.signers.get(2)];
    val update = makeUpdateAction(2, cleanSigners, ctx.proposers);
    val orderBody = singleActionOrder(update as GenericOrderAction);

    val create = sendOrderBySigner(ctx, orderBody, nowPlus(1000), 1);
    expect(create).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.signers.get(1),
        to: ctx.multisig.address,
    });

    val seqno = ctx.multisig.getData().nextOrderSeqno - 1;
    val order = MultisigV2Order.fromAddress(ctx.multisig.getOrderAddress(seqno));

    val approve = order.sendApprove(ctx.signers.get(2), 2, 77, { value: ton("0.2"), bounce: true });
    expect(approve).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: order.address,
        to: ctx.multisig.address,
    });

    val dataAfter = ctx.multisig.getData();
    expect(dataAfter.threshold).toEqual(2);
    expect(equalAddressArrays(mapToAddressArray(dataAfter.signersMap()), cleanSigners)).toEqual(true);
}

get fun `test invariants: unknown action opcode is ignored and next action executes`() {
    val ctx = setupMultisig(1, 2, 1, false);
    val target = net.randomAddress("unknown_action_target");

    val unknownAction = beginCell().storeUint(0xabad1dea, 32).storeUint(0, 8).endCell();
    val transfer = makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 0x454545);

    var actionCells = array<cell> [];
    actionCells.push(unknownAction);
    actionCells.push(transfer.toCell());

    val orderBody = packActionCells(actionCells);

    val res = sendOrderBySigner(ctx, orderBody, nowPlus(1000));
    expect(res).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
    });
    expect(res).toHaveSuccessfulTx({
        from: ctx.multisig.address,
        to: target,
        body: markerBody(0x454545),
    });
}
