import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/tlb/maybe"
import "@acton/types/message"
import "@acton/types/out_actions"
import "test_utils"
import "wrappers/HighloadWalletV3"
import "../contracts/messages"

get fun `test send internal message`() {
    val ctx = setupHighloadTest();
    val testAddr = net.randomAddress("internal-recipient");
    val testBody = beginCell().storeUint(123456, 32).endCell();
    val queryId = HighloadQueryId.fromShiftAndBitNumber(33, 1022).toInt();

    val outMsg = createMessage({
        bounce: false,
        value: ton("123"),
        dest: testAddr,
        body: testBody,
    }).messageCell;

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        outMsg,
        SEND_MODE_PAY_FEES_SEPARATELY,
        queryId,
        1000,
    );

    expect(res).toHaveSuccessfulTx({
        from: ctx.wallet.address,
        to: testAddr,
        value: ton("123"),
        body: testBody,
    });
    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();

    val replay = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        outMsg,
        SEND_MODE_PAY_FEES_SEPARATELY,
        queryId,
        1000,
    );
    expect(replay).toBeNull();
}

get fun `test ignore set_code action`() {
    val ctx = setupHighloadTest();
    val mockCode = beginCell().storeUint(777, 32).endCell();
    val testBody = beginCell().storeUint(424242, 32).endCell();
    val testAddr = net.randomAddress("set-code-target");

    val extQueryId = HighloadQueryId.fromShiftAndBitNumber(20, 88).toInt();
    val nestedQueryId = 123;

    expect(activeCode(ctx.wallet.address)).toEqual(ctx.wallet.code());

    var actions = array<OutAction> [];
    actions.push(setCodeAction(mockCode));
    actions.push(sendAction(testAddr, ton("0.1"), testBody, SEND_MODE_PAY_FEES_SEPARATELY));

    val message = ctx.wallet.createInternalTransferMessage(nestedQueryId, actions, 0).messageCell;
    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        message,
        SEND_MODE_CARRY_ALL_BALANCE,
        extQueryId,
        1000,
    );

    expect(activeCode(ctx.wallet.address)).toEqual(ctx.wallet.code());
    expect(res).toHaveSuccessfulTx({
        from: ctx.wallet.address,
        to: testAddr,
        body: testBody,
        value: ton("0.1"),
    });
}

get fun `test send external message`() {
    val ctx = setupHighloadTest();
    val extQueryId = HighloadQueryId.fromShiftAndBitNumber(22, 111).toInt();
    val marker = 31337;

    var actions = array<OutAction> [];
    actions.push(externalOutAction(TestExternalOutBody { marker: marker as uint32 }));

    val message = ctx.wallet.createInternalTransferMessage(0, actions, 0).messageCell;
    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        message,
        SEND_MODE_CARRY_ALL_BALANCE,
        extQueryId,
        1000,
    );

    val ext = res.findExternalOutMessage<TestExternalOutBody>({ from: ctx.wallet.address });
    expect(ext).toBeDefined();
    val body = ext.unwrap().loadBody();
    expect(body.marker).toEqual(marker);
    expect(ctx.wallet.isProcessed(extQueryId, false)).toBeTrue();
}

get fun `test preserve ignore errors flag when outbound action fails`() {
    val ctx = setupHighloadTest();
    val queryId = HighloadQueryId.fromShiftAndBitNumber(22, 112).toInt();
    val target = net.randomAddress("ignore-errors-failure-target");
    var outMsg = (createMessage({
        bounce: false,
        value: ton("0.1"),
        dest: target,
    }).messageCell as Cell<MessageRelaxedGeneric>).load();
    outMsg.info.ihrDisabled = false;

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        outMsg.toCell(),
        SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS | SEND_MODE_BOUNCE_ON_ACTION_FAIL,
        queryId,
        1000,
    );

    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();
    expect(res).toHaveTx({
        bounce: false,
        from: ctx.wallet.address,
        to: target,
        success: false,
    });
}

get fun `test handle 254 actions in one go`() {
    val ctx = setupHighloadTest();
    val queryId = queryIdZero().toInt();

    var actionsCell = createEmptyCell() as Cell<OutList>;

    var i = 0;
    while (i < 254) {
        val body = beginCell().storeUint(i, 32).endCell();
        val action = sendAction(net.randomAddress(null), ton("0.015"), body, 0);
        actionsCell = OutList {
            prev: actionsCell,
            action: action as OutAction,
        }.toCell();
        i += 1;
    }

    val batchMessage = ctx
        .wallet
        .createInternalTransferMessageFromActionsCell(queryId, actionsCell, 0)
        .messageCell;
    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        batchMessage,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );

    expect(res).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    var j = 0;
    while (j < 254) {
        val expectedBody = beginCell().storeUint(j, 32).endCell();
        expect(res).toHaveSuccessfulTx({ from: ctx.wallet.address, body: expectedBody });
        j += 1;
    }
    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();
}

get fun `test go beyond 255 messages via chained internal_transfer`() {
    val ctx = setupHighloadTest();
    val msgCount = 300;
    val queryId = queryIdZero().toInt();

    var rootActionsCell = createEmptyCell() as Cell<OutList>;
    var tailActionsCell = createEmptyCell() as Cell<OutList>;

    var i = 0;
    while (i < msgCount) {
        val body = beginCell().storeUint(i, 32).endCell();
        val action = sendAction(
            net.randomAddress(null),
            ton("0.015"),
            body,
            SEND_MODE_PAY_FEES_SEPARATELY,
        );
        if (i < 253) {
            rootActionsCell = OutList {
                prev: rootActionsCell,
                action: action as OutAction,
            }.toCell();
        } else {
            tailActionsCell = OutList {
                prev: tailActionsCell,
                action: action as OutAction,
            }.toCell();
        }
        i += 1;
    }

    val tailTransfer = ctx
        .wallet
        .createInternalTransferMessageFromActionsCell(queryId, tailActionsCell, 0);
    val chainAction = OutActionSendMessage {
        mode: SEND_MODE_CARRY_ALL_BALANCE,
        outMsg: tailTransfer.messageCell,
    };
    rootActionsCell = OutList {
        prev: rootActionsCell,
        action: chainAction,
    }.toCell();

    val rootTransfer = ctx
        .wallet
        .createInternalTransferMessageFromActionsCell(queryId, rootActionsCell, 0)
        .messageCell;
    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        rootTransfer,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );

    expect(res).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    var j = 0;
    while (j < msgCount) {
        val expectedBody = beginCell().storeUint(j, 32).endCell();
        expect(res).toHaveSuccessfulTx({ from: ctx.wallet.address, body: expectedBody });
        j += 1;
    }
    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();
}
