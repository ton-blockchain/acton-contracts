import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/tlb/maybe"
import "test-utils"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Multisig.gen"
import "../wrappers/Order.gen"
import "../wrappers/utils"

const MULTISIG_E2E_THRESHOLD = 2
const MULTISIG_E2E_SIGNER_COUNT = 5
const MULTISIG_E2E_ORDER_TTL = 1200
const MULTISIG_E2E_ACTION_MARKER = 424242
const MULTISIG_E2E_FIRST_APPROVE_QUERY_ID = 8101
const MULTISIG_E2E_FINAL_APPROVE_QUERY_ID = 8102

struct MultisigE2eFixture {
    ctx: MultisigTestContext
    order: Order
    orderSeqno: int
    recipient: address
    orderBody: DirectOrderActionsMap
}

fun deployMultisigStage(): MultisigTestContext {
    val ctx = setupMultisig(MULTISIG_E2E_THRESHOLD, MULTISIG_E2E_SIGNER_COUNT, 1, false);

    val data = ctx.multisig.getData();
    expect(data.threshold).toEqual(MULTISIG_E2E_THRESHOLD);
    expect(data.nextOrderSeqno).toEqual(0);

    return ctx;
}

fun createOrderStage(ctx: MultisigTestContext): MultisigE2eFixture {
    val recipient = randomAddress("multisig-e2e-recipient");
    val orderBody = singleActionOrder(
        makeTransferAction(recipient, DEFAULT_TRANSFER_VALUE, MULTISIG_E2E_ACTION_MARKER),
    );

    val orderSeqno = ctx.multisig.getData().nextOrderSeqno;
    val orderAddress = ctx.multisig.getOrderAddress(orderSeqno);

    val create = sendOrderByProposer(ctx, orderBody, nowPlus(MULTISIG_E2E_ORDER_TTL), 0);
    expect(create).toHaveSuccessfulTx<NewOrderRequest>({
        from: ctx.proposer.address,
        to: ctx.multisig.address,
    });
    expect(create).toHaveSuccessfulDeploy({ from: ctx.multisig.address, to: orderAddress });
    expect(create).toNotHaveTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: ctx.multisig.address,
    });

    val order = Order.fromAddress(orderAddress);
    val orderData = order.getData();
    expect(orderData.multisigAddress).toEqual(ctx.multisig.address);
    expect(orderData.orderSeqno).toEqual(orderSeqno);
    expect(orderData.threshold).toEqual(ctx.threshold);
    expect(orderData.approvalsNum).toEqual(0);
    expect(orderData.sentForExecution).toEqual(false);

    val multisigData = ctx.multisig.getData();
    expect(multisigData.nextOrderSeqno).toEqual(orderSeqno + 1);

    return {
        ctx,
        order,
        orderSeqno,
        recipient,
        orderBody,
    };
}

fun voteForOrderStage(fixture: MultisigE2eFixture) {
    val signerIndex = 0;
    val signerAddress = fixture.ctx.signers.get(signerIndex);

    val vote = fixture
        .order
        .sendApprove(
            signerAddress,
            signerIndex,
            MULTISIG_E2E_FIRST_APPROVE_QUERY_ID,
            { value: DEFAULT_APPROVE_VALUE, bounce: true },
        );

    expect(vote).toHaveTx<ApproveAccepted>({
        from: fixture.order.address,
        to: signerAddress,
    });
    expect(vote).toNotHaveTx<ExecuteOrderRequest>({
        from: fixture.order.address,
        to: fixture.ctx.multisig.address,
    });

    val acceptedTx = vote.findTransaction<ApproveAccepted>({
        from: fixture.order.address,
        to: signerAddress,
    });
    expect(acceptedTx).toBeNotNull();
    val acceptedBody = loadApproveAccepted(acceptedTx!);
    expect(acceptedBody.queryId).toEqual(MULTISIG_E2E_FIRST_APPROVE_QUERY_ID);

    val orderData = fixture.order.getData();
    expect(orderData.approvalsNum).toEqual(1);
    expect(approvalBit(orderData.approvalsMask, signerIndex)).toEqual(true);
    expect(orderData.sentForExecution).toEqual(false);
}

fun executeOrderStage(fixture: MultisigE2eFixture) {
    val signerIndex = 1;
    val signerAddress = fixture.ctx.signers.get(signerIndex);

    val vote = fixture
        .order
        .sendApprove(
            signerAddress,
            signerIndex,
            MULTISIG_E2E_FINAL_APPROVE_QUERY_ID,
            { value: DEFAULT_APPROVE_VALUE, bounce: true },
        );

    expect(vote).toHaveTx<ApproveAccepted>({
        from: fixture.order.address,
        to: signerAddress,
    });
    expect(vote).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: fixture.order.address,
        to: fixture.ctx.multisig.address,
    });
    expect(vote).toHaveTx({
        from: fixture.ctx.multisig.address,
        to: fixture.recipient,
        body: markerBody(MULTISIG_E2E_ACTION_MARKER),
        value: DEFAULT_TRANSFER_VALUE,
    });

    val acceptedTx = vote.findTransaction<ApproveAccepted>({
        from: fixture.order.address,
        to: signerAddress,
    });
    expect(acceptedTx).toBeNotNull();
    val acceptedBody = loadApproveAccepted(acceptedTx!);
    expect(acceptedBody.queryId).toEqual(MULTISIG_E2E_FINAL_APPROVE_QUERY_ID);

    val orderData = fixture.order.getData();
    expect(orderData.approvalsNum).toEqual(MULTISIG_E2E_THRESHOLD);
    expect(approvalBit(orderData.approvalsMask, 0)).toEqual(true);
    expect(approvalBit(orderData.approvalsMask, signerIndex)).toEqual(true);
    expect(orderData.sentForExecution).toEqual(true);

    val multisigData = fixture.ctx.multisig.getData();
    expect(multisigData.nextOrderSeqno).toEqual(fixture.orderSeqno + 1);
}

get fun `test multisig e2e bench: stage 1 create new order`() {
    val ctx = deployMultisigStage();
    createOrderStage(ctx);
}

get fun `test multisig e2e bench: stage 2 vote for order`() {
    val ctx = deployMultisigStage();
    val fixture = createOrderStage(ctx);
    voteForOrderStage(fixture);
}

get fun `test multisig e2e bench: stage 3 execute order`() {
    val ctx = deployMultisigStage();
    val fixture = createOrderStage(ctx);
    voteForOrderStage(fixture);
    executeOrderStage(fixture);
}
