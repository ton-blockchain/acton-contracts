import "test_utils"
import "wrappers/HighloadWalletV3"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/types/out_actions"

get fun `test ignore internal transfer from non-self address`() {
    val ctx = setupHighloadTest();
    val testAddr = net.randomAddress("internal-filter-target");
    val queryId = HighloadQueryId.fromShiftAndBitNumber(40, 300).toInt();

    var actions = array<OutAction> [];
    actions.push(sendAction(testAddr, ton("1000"), createEmptyCell(), SEND_MODE_PAY_FEES_SEPARATELY) as OutAction);
    val transferBody = HighloadWalletV3.createInternalTransferBody(queryId, actions);

    val outsider = net.treasury("outsider");
    val res1 = net.send(outsider.address, createMessage({
        bounce: false,
        value: ton("1"),
        dest: ctx.wallet.address,
        body: transferBody,
    }));
    expect(res1).toNotHaveTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("1000"),
    });

    val res2 = net.send(ctx.wallet.address, createMessage({
        bounce: false,
        value: ton("1"),
        dest: ctx.wallet.address,
        body: transferBody,
    }));
    expect(res2).toHaveSuccessfulTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("1000"),
    });
}

get fun `test ignore bounced messages`() {
    val ctx = setupHighloadTest();
    val testAddr = net.randomAddress("bounced-target");
    val queryId = HighloadQueryId.fromShiftAndBitNumber(41, 301).toInt();

    var actions = array<OutAction> [];
    actions.push(sendAction(testAddr, ton("1000"), createEmptyCell(), SEND_MODE_PAY_FEES_SEPARATELY) as OutAction);
    val transferBody = HighloadWalletV3.createInternalTransferBody(queryId, actions);

    val bounced = createMessage({
        bounce: false,
        value: ton("1"),
        dest: ctx.wallet.address,
        body: transferBody,
    }).bounced();
    val res1 = net.send(ctx.wallet.address, bounced);
    expect(res1).toNotHaveTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("1000"),
    });

    val normal = createMessage({
        bounce: false,
        value: ton("1"),
        dest: ctx.wallet.address,
        body: transferBody,
    });
    val res2 = net.send(ctx.wallet.address, normal);
    expect(res2).toHaveSuccessfulTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("1000"),
    });
}

get fun `test ignore invalid message in payload`() {
    val ctx = setupHighloadTest();
    val badMsgs = badPayloadMessages();
    var queryIter = queryIdZero();

    var i = 0;
    while (i < badMsgs.size()) {
        val q = queryIter.toInt();
        val res = sendSignedExternal(
            ctx.wallet,
            ctx.keyPair,
            badMsgs.get(i),
            0,
            q,
            1000,
        );

        val tx = res.at(0).tx.load();
        expect(tx.getAccountAddress()).toEqual(ctx.wallet.address);
        expect(tx.outmsgCnt).toEqual(0);
        expect(ctx.wallet.isProcessed(q, false)).toBeTrue();

        queryIter = queryIter.getNext();
        i += 1;
    }
}

get fun `test replay protection but do not send message`() {
    val ctx = setupHighloadTest();
    val q = queryIdZero().toInt();
    val invalidPayload = beginCell().storeUint(239, 17).endCell();

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        invalidPayload,
        SEND_MODE_IGNORE_ERRORS,
        q,
        1000,
    );

    val tx = res.at(0).tx.load();
    expect(tx.getAccountAddress()).toEqual(ctx.wallet.address);
    expect(tx.outmsgCnt).toEqual(0);
    expect(ctx.wallet.isProcessed(q, false)).toBeTrue();
}
