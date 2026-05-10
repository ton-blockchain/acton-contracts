import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/out_actions"
import "test-utils"
import "../contracts/messages"
import "../wrappers/HighloadWalletV3.gen"
import "../wrappers/utils"

const HIGHLOAD_E2E_DIRECT_SEND_VALUE = ton("1")
const HIGHLOAD_E2E_BATCH_SEND_VALUE = ton("0.015")
const HIGHLOAD_E2E_INLINE_BATCH_COUNT = 254
const HIGHLOAD_E2E_CHAINED_BATCH_COUNT = 300
const HIGHLOAD_E2E_CHAIN_CUT = 253
const HIGHLOAD_E2E_CLEANUP_NOW = 1260

const HIGHLOAD_E2E_SINGLE_MARKER = 101
const HIGHLOAD_E2E_INLINE_MARKER_BASE = 100000
const HIGHLOAD_E2E_CHAINED_MARKER_BASE = 200000

fun benchmarkMarkerBody(marker: int): cell {
    return beginCell().storeUint(marker, 32).endCell();
}

fun buildBenchmarkActionListCellRange(
    startIndex: int,
    count: int,
    markerBase: int,
    actionMode: int = SEND_MODE_PAY_FEES_SEPARATELY,
): Cell<TlbOutList> {
    var actionsCell = createEmptyCell() as Cell<TlbOutList>;
    var i = 0;
    while (i < count) {
        val action = sendAction(
            randomAddress(null),
            HIGHLOAD_E2E_BATCH_SEND_VALUE,
            benchmarkMarkerBody(markerBase + startIndex + i),
            actionMode,
        );
        actionsCell = TlbOutList {
            prev: actionsCell,
            action: action as TlbOutAction,
        }.toCell();
        i += 1;
    }
    return actionsCell;
}

fun deployHighloadWalletStage(): (TestContext, HighloadQueryId) {
    val ctx = setupHighloadTest();

    expect(ctx.wallet.getPublicKey()).toEqual(ctx.keyPair.publicKey);
    expect(ctx.wallet.getSubwalletId()).toEqual(SUBWALLET_ID);
    expect(ctx.wallet.getTimeout()).toEqual(DEFAULT_TIMEOUT);
    expect(ctx.wallet.getLastCleanTime()).toEqual(0);

    return (ctx, queryIdZero());
}

fun processSingleTransferStage(
    ctx: TestContext,
    queryCursor: HighloadQueryId,
): (HighloadQueryId, int) {
    val queryId = queryCursor.toInt();
    val recipient = randomAddress("highload-e2e-single");
    val body = benchmarkMarkerBody(HIGHLOAD_E2E_SINGLE_MARKER);

    val outMsg = createMessage({
        bounce: false,
        value: HIGHLOAD_E2E_DIRECT_SEND_VALUE,
        dest: recipient,
        body,
    }).messageCell;

    val res = sendSignedExternal(
        ctx.wallet,
        ctx.keyPair,
        outMsg,
        SEND_MODE_PAY_FEES_SEPARATELY,
        queryId,
        testing.getNow(),
    );

    expect(res).toHaveTx({
        from: ctx.wallet.address,
        to: recipient,
        value: HIGHLOAD_E2E_DIRECT_SEND_VALUE,
        body,
    });
    expect(ctx.wallet.isProcessed(queryId, false)).toBeTrue();

    return (queryCursor.getNext(), queryId);
}

fun assertBatchStageSuccess(
    res: SendResultList,
    wallet: HighloadWalletV3,
    queryId: int,
    markerBase: int,
    actionCount: int,
) {
    expect(res).toHaveSuccessfulTx<InternalTransfer>({ from: wallet.address, to: wallet.address });
    expect(res).toHaveTx({ from: wallet.address, body: benchmarkMarkerBody(markerBase) });
    expect(res).toHaveTx({
        from: wallet.address,
        body: benchmarkMarkerBody(markerBase + actionCount - 1),
    });
    expect(wallet.isProcessed(queryId, false)).toBeTrue();
}

fun processMaxInlineBatchStage(
    ctx: TestContext,
    queryCursor: HighloadQueryId,
): (HighloadQueryId, int) {
    val queryId = queryCursor.toInt();
    val actionsCell = buildBenchmarkActionListCellRange(
        0,
        HIGHLOAD_E2E_INLINE_BATCH_COUNT,
        HIGHLOAD_E2E_INLINE_MARKER_BASE,
        0,
    );
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
        testing.getNow(),
    );

    assertBatchStageSuccess(
        res,
        ctx.wallet,
        queryId,
        HIGHLOAD_E2E_INLINE_MARKER_BASE,
        HIGHLOAD_E2E_INLINE_BATCH_COUNT,
    );
    expect(res).toHaveTx({
        from: ctx.wallet.address,
        body: benchmarkMarkerBody(HIGHLOAD_E2E_INLINE_MARKER_BASE + 127),
    });

    return (queryCursor.getNext(), queryId);
}

fun processChainedBatchWithCleanupStage(
    ctx: TestContext,
    queryCursor: HighloadQueryId,
    expiredSingleQueryId: int,
    expiredInlineQueryId: int,
): (HighloadQueryId, int) {
    testing.setNow(HIGHLOAD_E2E_CLEANUP_NOW);

    // Getter applies timeout window logic without mutating stored state.
    expect(ctx.wallet.isProcessed(expiredSingleQueryId)).toBeFalse();
    expect(ctx.wallet.isProcessed(expiredInlineQueryId)).toBeFalse();

    val queryId = queryCursor.toInt();
    var rootActionsCell = buildBenchmarkActionListCellRange(
        0,
        HIGHLOAD_E2E_CHAIN_CUT,
        HIGHLOAD_E2E_CHAINED_MARKER_BASE,
    );
    val tailOutMsgCount = HIGHLOAD_E2E_CHAINED_BATCH_COUNT - HIGHLOAD_E2E_CHAIN_CUT;
    val tailActionsCell = buildBenchmarkActionListCellRange(
        HIGHLOAD_E2E_CHAIN_CUT,
        tailOutMsgCount,
        HIGHLOAD_E2E_CHAINED_MARKER_BASE,
    );

    val tailTransfer = ctx
        .wallet
        .createInternalTransferMessageFromActionsCell(queryId, tailActionsCell, 0);
    val chainAction = TlbOutActionSendMessage {
        mode: SEND_MODE_CARRY_ALL_BALANCE,
        outMsg: tailTransfer.messageCell,
    };
    rootActionsCell = TlbOutList {
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
        testing.getNow(),
    );

    assertBatchStageSuccess(
        res,
        ctx.wallet,
        queryId,
        HIGHLOAD_E2E_CHAINED_MARKER_BASE,
        HIGHLOAD_E2E_CHAINED_BATCH_COUNT,
    );
    expect(res).toHaveTx({
        from: ctx.wallet.address,
        body: benchmarkMarkerBody(HIGHLOAD_E2E_CHAINED_MARKER_BASE + HIGHLOAD_E2E_CHAIN_CUT),
    });

    val rootTx = res.findTransaction<InternalTransfer>({
        from: ctx.wallet.address,
        to: ctx.wallet.address,
    });
    expect(rootTx).toBeNotNull();
    val rootNow = rootTx!.now;
    expect(ctx.wallet.getLastCleanTime()).toEqual(rootNow);
    expect(ctx.wallet.isProcessed(expiredSingleQueryId)).toBeFalse();
    expect(ctx.wallet.isProcessed(expiredInlineQueryId)).toBeFalse();

    return (queryCursor.getNext(), queryId);
}

get fun `test highload e2e bench: stage 1 deploy wallet`() {
    deployHighloadWalletStage();
}

get fun `test highload e2e bench: stage 2 send single signed transfer`() {
    val (ctx, queryCursor) = deployHighloadWalletStage();
    processSingleTransferStage(ctx, queryCursor);
}

get fun `test highload e2e bench: stage 3 send max inline batch`() {
    val (ctx, queryCursor) = deployHighloadWalletStage();
    val (nextQueryCursor, _) = processSingleTransferStage(ctx, queryCursor);
    processMaxInlineBatchStage(ctx, nextQueryCursor);
}

get fun `test highload e2e bench: stage 4 full flow with chained batch and cleanup`() {
    val (ctx, queryCursor) = deployHighloadWalletStage();
    val (afterSingle, singleQueryId) = processSingleTransferStage(ctx, queryCursor);
    val (afterInline, inlineQueryId) = processMaxInlineBatchStage(ctx, afterSingle);
    processChainedBatchWithCleanupStage(ctx, afterInline, singleQueryId, inlineQueryId);
}
