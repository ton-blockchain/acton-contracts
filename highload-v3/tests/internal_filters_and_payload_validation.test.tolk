import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/types/message"
import "@acton/types/out_actions"
import "@acton/types/transaction"
import "test_utils"
import "wrappers/HighloadWalletV3"
import "../contracts/messages"

fun messageWithInternalSource(src: address, dest: address): cell {
    var msg = (
        createMessage({
            bounce: false,
            value: ton("0.1"),
            dest,
        }).messageCell as Cell<MessageRelaxedGeneric>
    ).load();
    msg.info.src = src as any_address;
    return msg.toCell();
}

fun messageWithStateInit(stateInit: ContractState, value: coins = ton("0.1")): cell {
    return createMessage({
        bounce: false,
        value,
        dest: { stateInit },
    }).messageCell;
}

fun messageWithTrailingDataAfterBodyRef(dest: address, value: coins = ton("0.1")): cell {
    var msg = (
        createMessage({
            bounce: false,
            value,
            dest,
        }).messageCell as Cell<MessageRelaxedGeneric>
    ).load();
    val actualBody = beginCell().storeUint(0xabcdef01, 32).endCell();
    msg.body = beginCell()
        .storeBool(true)
        .storeRef(actualBody)
        .storeRef(createEmptyCell())
        .endCell()
        .beginParse();
    return msg.toCell();
}

fun expectPayloadRejectedButQueryProcessed(
    wallet: HighloadWalletV3,
    res: SendResultList,
    queryId: int,
): void {
    val tx = res.at(0).tx.load();
    expect(tx.getAccountAddress()).toEqual(wallet.address);
    expect(tx.outmsgCnt).toEqual(0);
    expect(wallet.isProcessed(queryId, false)).toBeTrue();
}

get fun `test ignore internal transfer from non-self address`() {
    val ctx = setupHighloadTest();
    val testAddr = net.randomAddress("internal-filter-target");
    val queryId = HighloadQueryId.fromShiftAndBitNumber(40, 300).toInt();

    var actions = array<OutAction> [];
    actions.push(
        sendAction(testAddr, ton("1000"), createEmptyCell(), SEND_MODE_PAY_FEES_SEPARATELY),
    );
    val transferBody = HighloadWalletV3.createInternalTransferBody(queryId, actions);

    val outsider = net.treasury("outsider");
    val res1 = net.send(
        outsider.address,
        createMessage({
            bounce: false,
            value: ton("1"),
            dest: ctx.wallet.address,
            body: transferBody,
        }),
    );
    expect(res1).toNotHaveTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("1000"),
    });

    val res2 = net.send(
        ctx.wallet.address,
        createMessage({
            bounce: false,
            value: ton("1"),
            dest: ctx.wallet.address,
            body: transferBody,
        }),
    );
    expect(res2).toHaveSuccessfulTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("1000"),
    });
}

get fun `test ignore malformed internal transfer body from self`() {
    val ctx = setupHighloadTest();
    val testAddr = net.randomAddress("internal-bad-shape-target");
    val queryId = HighloadQueryId.fromShiftAndBitNumber(40, 301).toInt();

    var actions = array<OutAction> [];
    actions.push(
        sendAction(testAddr, ton("1000"), createEmptyCell(), SEND_MODE_PAY_FEES_SEPARATELY),
    );
    val validBody = HighloadWalletV3.createInternalTransferBody(queryId, actions);
    var validSlice = validBody.beginParse();
    validSlice.skipBits(32);
    val storedQueryId = validSlice.loadUint(64);
    val actionsRef = validSlice.loadRef();

    val malformedBody = beginCell()
        .storeUint(OP_INTERNAL_TRANSFER, 32)
        .storeUint(storedQueryId, 64)
        .storeBool(false)
        .storeRef(actionsRef)
        .endCell();

    val res = net.send(
        ctx.wallet.address,
        createMessage({
            bounce: false,
            value: ton("1"),
            dest: ctx.wallet.address,
            body: malformedBody,
        }),
    );

    expect(res).toHaveSuccessfulTx({ from: ctx.wallet.address, to: ctx.wallet.address });
    expect(countTxsOnWithOutmsgCount(res, ctx.wallet.address, 0)).toBeGreater(0);
    expect(res).toNotHaveTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("1000"),
    });
}

get fun `test ignore internal transfer with wrong opcode from self`() {
    val ctx = setupHighloadTest();
    val testAddr = net.randomAddress("internal-bad-opcode-target");
    val queryId = HighloadQueryId.fromShiftAndBitNumber(40, 302).toInt();

    var actions = array<OutAction> [];
    actions.push(
        sendAction(testAddr, ton("1000"), createEmptyCell(), SEND_MODE_PAY_FEES_SEPARATELY),
    );
    val validBody = HighloadWalletV3.createInternalTransferBody(queryId, actions);
    var validSlice = validBody.beginParse();
    validSlice.skipBits(32);
    val tail = validSlice;

    val wrongOpcodeBody = beginCell().storeUint(0x12345678, 32).storeSlice(tail).endCell();
    val res = net.send(
        ctx.wallet.address,
        createMessage({
            bounce: false,
            value: ton("1"),
            dest: ctx.wallet.address,
            body: wrongOpcodeBody,
        }),
    );

    expect(res).toHaveSuccessfulTx({ from: ctx.wallet.address, to: ctx.wallet.address });
    expect(countTxsOnWithOutmsgCount(res, ctx.wallet.address, 0)).toBeGreater(0);
    expect(res).toNotHaveTx({
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
    actions.push(
        sendAction(testAddr, ton("1000"), createEmptyCell(), SEND_MODE_PAY_FEES_SEPARATELY),
    );
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

get fun `test ignore outgoing message with internal source in payload`() {
    val ctx = setupHighloadTest();
    val recipient = net.randomAddress("semantic-invalid-payload-dest");
    val queryId = HighloadQueryId.fromShiftAndBitNumber(5, 500).toInt();
    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        messageWithInternalSource(ctx.deployer.address, recipient),
        0,
        queryId,
        1000,
    );

    expectPayloadRejectedButQueryProcessed(ctx.wallet, res, queryId);
    expect(res).toNotHaveTx({ from: ctx.wallet.address, to: recipient });
}

get fun `test ignore outgoing message with state init in payload`() {
    val ctx = setupHighloadTest();
    val queryId = HighloadQueryId.fromShiftAndBitNumber(5, 501).toInt();
    val otherWallet = HighloadWalletV3.fromConfig(ctx.keyPair.publicKey, SUBWALLET_ID + 1, DEFAULT_TIMEOUT);

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        messageWithStateInit(otherWallet.stateInit!),
        0,
        queryId,
        1000,
    );

    expectPayloadRejectedButQueryProcessed(ctx.wallet, res, queryId);
    expect(res).toNotHaveTx({ from: ctx.wallet.address, to: otherWallet.address });
}

get fun `test accept outgoing message with inline body payload`() {
    val ctx = setupHighloadTest();
    val queryId = HighloadQueryId.fromShiftAndBitNumber(5, 502).toInt();
    val recipient = net.randomAddress("inline-payload-dest");
    val inlineBody = beginCell().storeUint(0xfeedbeef, 32).endCell().beginParse();
    val payload = createMessage({
        bounce: false,
        value: ton("0.1"),
        dest: recipient,
        body: UnsafeBodyNoRef { forceInline: inlineBody },
    }).messageCell;

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        payload,
        0,
        queryId,
        1000,
    );

    expect(res).toHaveTx({
        from: ctx.wallet.address,
        to: recipient,
        body: beginCell().storeUint(0xfeedbeef, 32).endCell(),
    });
    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();
}

get fun `test ignore outgoing message with malformed ref body in payload`() {
    val ctx = setupHighloadTest();
    val recipient = net.randomAddress("malformed-ref-payload-dest");
    val queryId = HighloadQueryId.fromShiftAndBitNumber(5, 503).toInt();
    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        messageWithTrailingDataAfterBodyRef(recipient),
        0,
        queryId,
        1000,
    );

    expectPayloadRejectedButQueryProcessed(ctx.wallet, res, queryId);
    expect(res).toNotHaveTx({ from: ctx.wallet.address, to: recipient });
}

get fun `test ignore bounced outgoing message in payload`() {
    val ctx = setupHighloadTest();
    val queryId = HighloadQueryId.fromShiftAndBitNumber(5, 504).toInt();
    val bouncedPayload = createMessage({
        bounce: false,
        value: ton("0.1"),
        dest: net.randomAddress("bounced-outgoing-dest"),
    }).bounced().messageCell;

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        bouncedPayload,
        0,
        queryId,
        1000,
    );

    expectPayloadRejectedButQueryProcessed(ctx.wallet, res, queryId);
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
