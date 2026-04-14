import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test-utils"
import "../contracts/messages"
import "../wrappers/HighloadWalletV3"

get fun `test queries hashmaps are cleared`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(13, 77).toInt();

    val res1 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );
    expect(res1).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });
    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();

    net.setNow(1260);
    // Getter should account for expiration without mutating stored state.
    expect(ctx.wallet.isProcessed(queryId)).toBeFalse();

    val newQueryId = HighloadQueryId.fromShiftAndBitNumber(15, 99).toInt();
    val res2 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        newQueryId,
        1200,
    );
    expect(res2).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    expect(ctx.wallet.isProcessed(queryId)).toBeFalse();
    expect(ctx.wallet.isProcessed(newQueryId, false)).toBeTrue();

    val rootNow = res2.at(0).tx.load().now;
    expect(ctx.wallet.getLastCleanTime()).toEqual(rootNow);
}

get fun `test cleanup does not run at exact timeout boundary`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(14, 77).toInt();
    val timeout = ctx.wallet.getTimeout();

    val res1 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );
    expect(res1).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    net.setNow(1000 + timeout);
    val nextQueryId = HighloadQueryId.fromShiftAndBitNumber(14, 78).toInt();
    val res2 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        nextQueryId,
        1000 + timeout,
    );
    expect(res2).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    expect(storedIsProcessedInCurrentQueries(ctx.wallet, queryId)).toBeTrue();
    expect(storedIsProcessedInOldQueries(ctx.wallet, queryId)).toBeFalse();
    expect(storedIsProcessedInCurrentQueries(ctx.wallet, nextQueryId)).toBeTrue();
    expect(ctx.wallet.getLastCleanTime()).toEqual(1000);
}

get fun `test cleanup moves prior queries into old window and still blocks replay`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(16, 81).toInt();
    val timeout = ctx.wallet.getTimeout();

    val res1 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );
    expect(res1).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    net.setNow(1000 + timeout + 1);
    val nextQueryId = HighloadQueryId.fromShiftAndBitNumber(16, 82).toInt();
    val res2 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        nextQueryId,
        1000 + timeout + 1,
    );
    expect(res2).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    expect(storedIsProcessedInOldQueries(ctx.wallet, queryId)).toBeTrue();
    expect(storedIsProcessedInCurrentQueries(ctx.wallet, queryId)).toBeFalse();
    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();
    expect(storedIsProcessedInCurrentQueries(ctx.wallet, nextQueryId)).toBeTrue();

    val replay = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000 + timeout + 1,
    );
    expect(replay).toBeNull();
}

get fun `test cleanup keeps old window at exact double-timeout boundary`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(17, 83).toInt();
    val timeout = ctx.wallet.getTimeout();

    val res1 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );
    expect(res1).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    net.setNow(1000 + (timeout * 2));
    val nextQueryId = HighloadQueryId.fromShiftAndBitNumber(17, 84).toInt();
    val res2 = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        nextQueryId,
        1000 + (timeout * 2),
    );
    expect(res2).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });

    expect(storedIsProcessedInOldQueries(ctx.wallet, queryId)).toBeTrue();
    expect(storedIsProcessedInCurrentQueries(ctx.wallet, queryId)).toBeFalse();
    expect(storedIsProcessedInCurrentQueries(ctx.wallet, nextQueryId)).toBeTrue();

    val rootNow = res2.at(0).tx.load().now;
    expect(ctx.wallet.getLastCleanTime()).toEqual(rootNow);
}

get fun `test queries dictionary with max keys fits credit limit`() {
    val ctx = setupHighloadTest();
    preloadDenseQueryMaps(ctx.wallet, net.now());

    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(MAX_SHIFT, 700).toInt();

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );

    expect(res).toHaveSuccessfulTx({ to: ctx.wallet.address });
    expect(countTxsOnWithOutmsgCount(res, ctx.wallet.address, 1)).toBeGreater(0);
}
