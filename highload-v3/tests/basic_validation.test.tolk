import "@acton/crypto/crypto"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/types/big_array"
import "test_utils"
import "../contracts/messages"
import "../wrappers/HighloadWalletV3"

get fun `test deploy`() {
    val ctx = setupHighloadTest();
    expect(ctx.wallet.getPublicKey()).toEqual(ctx.keyPair.publicKey);
}

get fun `test pass check sign`() {
    val ctx = setupHighloadTest();
    val nestedQuery = queryIdZero().toInt();
    val msg = emptyInternalTransferMessage(ctx.wallet, nestedQuery, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(7, 17).toInt();

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );

    expect(res).toHaveSuccessfulTx<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });
}

get fun `test fail check sign`() {
    val ctx = setupHighloadTest();
    val badKey = crypto.generateKeyPair();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(5, 42).toInt();

    val res = trySendSignedExternalSingle(
        ctx.wallet,
        badKey,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );
    expect(res).toBeNull();
}

get fun `test fail subwallet check`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(2, 10).toInt();

    expect(ctx.wallet.getSubwalletId()).toEqual(SUBWALLET_ID);

    val res = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
        SUBWALLET_ID + 1,
    );
    expect(res).toBeNull();
}

get fun `test fail created time check`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(2, 11).toInt();
    val timeout = ctx.wallet.getTimeout();

    val res = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000 - timeout - 1,
    );
    expect(res).toBeNull();
}

get fun `test fail created time at lower boundary`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(2, 12).toInt();
    val timeout = ctx.wallet.getTimeout();

    val res = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000 - timeout,
    );
    expect(res).toBeNull();
}

get fun `test fail created time in future`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(2, 13).toInt();

    val res = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1001,
    );
    expect(res).toBeNull();
}

get fun `test fail query id in actual queries`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(10, 120).toInt();

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
    expect(storedIsProcessed(ctx.wallet, queryId)).toBeTrue();

    val res2 = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1000,
    );
    expect(res2).toBeNull();
}

get fun `test work with max bitNumber 1022`() {
    val ctx = setupHighloadTest();
    val queryId = HighloadQueryId.fromShiftAndBitNumber(17, 1022).toInt();
    val msg = createMessage({
        bounce: false,
        value: 0,
        dest: net.randomAddress("max-bit-ok"),
    }).messageCell;

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        0,
        queryId,
        1000,
    );
    expect(res.size()).toBeGreater(0);
}

get fun `test reject bitNumber 1023`() {
    val ctx = setupHighloadTest();
    val shift = 17;
    val queryId = (shift << 10) + 1023;
    val msg = createMessage({
        bounce: false,
        value: 0,
        dest: net.randomAddress("max-bit-fail"),
    }).messageCell;

    val res = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        0,
        queryId,
        1000,
    );
    expect(res).toBeNull();
}

get fun `test work with max shift`() {
    val ctx = setupHighloadTest();
    val queryId = HighloadQueryId.fromShiftAndBitNumber(MAX_SHIFT, 77).toInt();
    val msg = createMessage({
        bounce: false,
        value: 0,
        dest: net.randomAddress("max-shift-ok"),
    }).messageCell;

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        msg,
        0,
        queryId,
        1000,
    );
    expect(res.size()).toBeGreater(0);
}

get fun `test fail query id on replay after time change`() {
    val ctx = setupHighloadTest();
    val msg = emptyInternalTransferMessage(ctx.wallet, 0, 0);
    val queryId = HighloadQueryId.fromShiftAndBitNumber(100, 200).toInt();

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

    net.setNow(1100);
    expect(storedIsProcessed(ctx.wallet, queryId)).toBeTrue();

    val res2 = trySendSignedExternalSingle(
        ctx.wallet,
        ctx.keyPair,
        msg,
        SEND_MODE_CARRY_ALL_BALANCE,
        queryId,
        1050,
    );
    expect(res2).toBeNull();
}
