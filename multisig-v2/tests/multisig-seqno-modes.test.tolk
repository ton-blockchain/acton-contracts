import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test-utils"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/MultisigV2"
import "../wrappers/MultisigV2Order"

get fun `test multisig: multisig parameters update with threshold = 0 should fail`() {
    val ctx = setupMultisig(1, 4, 1, false);
    val target = net.randomAddress("threshold0_target");

    val dataBefore = ctx.multisig.getData();
    expect(dataBefore.threshold).toEqual(1);

    val update = makeUpdateAction(0, ctx.signers, mapToAddressArray(dataBefore.proposersMap()));
    val transfer = makeTransferAction(target, DEFAULT_TRANSFER_VALUE, 33333);

    val order = pairActionsOrder(update, transfer);

    val orderAddress = ctx.multisig.getOrderAddress(dataBefore.nextOrderSeqno);
    val res = sendOrderBySigner(ctx, order, nowPlus(1000));

    expect(res).toHaveFailedTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
        exitCode: ERROR_INVALID_THRESHOLD,
    });
    expect(res).toNotHaveTx({ from: ctx.multisig.address, to: target });

    val dataAfter = ctx.multisig.getData();
    expect(dataAfter.threshold).toEqual(dataBefore.threshold);
}

get fun `test multisig: should not allow to create order with seqno other than next order seqno`() {
    val ctx = setupMultisig();
    val order = singleActionOrder(makeTransferAction(net.randomAddress("seqno_fixed_target")));

    val before = ctx.multisig.getData();
    expect(before.nextOrderSeqno).toBeGreater(-1);

    val validSeqno = before.nextOrderSeqno;
    val validOrderAddress = ctx.multisig.getOrderAddress(before.nextOrderSeqno);

    val ok = sendOrderBySigner(
        ctx,
        order,
        nowPlus(100),
        0,
        validSeqno,
        ton("0.5"),
    );
    expect(ok).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
    });
    expect(ok).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: validOrderAddress });

    val afterOk = ctx.multisig.getData();

    val invalidSame = sendOrderBySigner(
        ctx,
        order,
        nowPlus(100),
        0,
        validSeqno,
        ton("0.5"),
    );
    expect(invalidSame).toHaveFailedTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_INVALID_NEW_ORDER,
    });

    val invalidHigherSeqno = (afterOk.nextOrderSeqno + 100);
    val invalidHigher = sendOrderBySigner(
        ctx,
        order,
        nowPlus(100),
        0,
        invalidHigherSeqno,
        ton("0.5"),
    );
    expect(invalidHigher).toHaveFailedTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_INVALID_NEW_ORDER,
    });

    val invalidLowerSeqno = (afterOk.nextOrderSeqno - 1);
    val invalidLower = sendOrderBySigner(
        ctx,
        order,
        nowPlus(100),
        0,
        invalidLowerSeqno,
        ton("0.5"),
    );
    expect(invalidLower).toHaveFailedTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
        exitCode: ERROR_INVALID_NEW_ORDER,
    });

    val afterAll = ctx.multisig.getData();
    expect(afterAll.nextOrderSeqno).toEqual(afterOk.nextOrderSeqno);
}

get fun `test multisig: should allow to create orders with arbitrary seqno`() {
    val ctx = setupMultisig(4, 6, 1, true);
    val order = singleActionOrder(makeTransferAction(net.randomAddress("seqno_arbitrary_target")));

    val data = ctx.multisig.getData();
    expect(data.nextOrderSeqno).toEqual(-1);

    val seqnos = array<int> [101, 707, 9999, 15000, 20001];

    var i = 0;
    while (i < seqnos.size()) {
        val signerIndex = i % ctx.signers.size();
        val seqno = seqnos.get(i);
        val expectedOrderAddress = ctx.multisig.getOrderAddress(seqnos.get(i));

        val res = sendOrderBySigner(
            ctx,
            order,
            nowPlus(1000),
            signerIndex,
            seqno,
            ton("0.5"),
        );

        expect(res).toHaveSuccessfulTx<NewOrderRequest>({
            from: ctx.signers.get(signerIndex),
            to: ctx.multisig.address,
        });
        expect(res).toHaveSuccessfulDeploy({
            from: ctx.multisig.address,
            to: expectedOrderAddress,
        });

        i += 1;
    }
}

get fun `test multisig: should allow to create order with maximum possible seqno`() {
    val ctx = setupMultisig(2, 3, 1, true);
    val order = singleActionOrder(makeTransferAction(net.randomAddress("max_seqno_target")));

    val orderAddress = ctx.multisig.getOrderAddress(MAX_ORDER_SEQNO);

    val res = sendOrderBySigner(
        ctx,
        order,
        nowPlus(100),
        0,
        MAX_ORDER_SEQNO,
        ton("0.5"),
    );

    expect(res).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.deployer.address,
        to: ctx.multisig.address,
    });
    expect(res).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });
}

get fun `test multisig: subsequent order creation with same seqno should result in vote`() {
    val ctx = setupMultisig(3, 5, 1, true);
    val order = singleActionOrder(makeTransferAction(net.randomAddress("same_seqno_vote_target")));

    val targetSeqno = 4242;
    val orderAddress = ctx.multisig.getOrderAddress(4242);
    val orderContract = MultisigV2Order.fromAddress(orderAddress);

    var i = 0;
    while (i < ctx.threshold) {
        val signerIndex = i;
        val signerAddress = ctx.signers.get(signerIndex);

        val res = sendOrderBySigner(
            ctx,
            order,
            nowPlus(1000),
            signerIndex,
            targetSeqno,
            ton("0.5"),
        );

        expect(res).toHaveSuccessfulTx<NewOrderRequest>({
            from: signerAddress,
            to: ctx.multisig.address,
        });
        expect(res).toHaveSuccessfulTx<InitOrderRequest>({
            from: ctx.multisig.address,
            to: orderAddress,
        });

        val dataAfter = orderContract.getData();
        expect(dataAfter.approvalsNum).toEqual(i + 1);
        expect(approvalBit(dataAfter.approvalsMask, signerIndex)).toEqual(true);

        if (i > 0) {
            expect(res).toHaveSuccessfulTx<ApproveAccepted>({
                from: orderAddress,
                to: signerAddress,
            });
        }

        if (i + 1 == ctx.threshold) {
            expect(res).toHaveTx<ExecuteOrderRequest>({
                from: orderAddress,
                to: ctx.multisig.address,
            });
        }

        i += 1;
    }
}
