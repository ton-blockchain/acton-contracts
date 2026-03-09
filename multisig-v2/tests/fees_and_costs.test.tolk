import "@acton/build/build"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/vm/vm"
import "../contracts/messages"
import "../contracts/types"
import "test_utils"
import "wrappers/MultisigV2"
import "wrappers/MultisigV2Order"

const FEE_BASE_EXPIRATION = 2000000000
const FEE_TEST_NOW = 1760000000
const FEE_DEFAULT_CREATE_VALUE = ton("10")

struct FeeContext {
    wallet: MultisigV2
    jumboWallet: MultisigV2
    deployer: Treasury
    second: Treasury
    proposer: Treasury
    jumboSigners: array<address>
}

fun setupFeeContext(): FeeContext {
    net.setNow(FEE_TEST_NOW as uint32);
    vm.registerLibrary(build("multisig_v2_order"));

    val deployer = net.treasury("fee_deployer");
    val second = net.treasury("fee_second");
    val proposer = net.treasury("fee_proposer");

    val wallet = MultisigV2.fromConfig(
        2,
        array<address> [deployer.address, second.address],
        array<address> [proposer.address],
        false,
    );
    val walletDeploy = wallet.deploy(deployer.address, { value: ton("20"), bounce: false });
    expect(walletDeploy).toHaveSuccessfulDeploy({ to: wallet.address });

    var jumboSigners = array<address> [];
    jumboSigners.push(deployer.address);
    jumboSigners.push(second.address);

    var i = 0;
    while (i < 253) {
        jumboSigners.push(createFundedAddress());
        i += 1;
    }

    val jumboWallet = MultisigV2.fromConfig(
        2,
        jumboSigners,
        array<address> [proposer.address],
        false,
    );
    val jumboDeploy = jumboWallet.deploy(deployer.address, { value: ton("200"), bounce: false });
    expect(jumboDeploy).toHaveSuccessfulDeploy({ to: jumboWallet.address });

    return {
        wallet,
        jumboWallet,
        deployer,
        second,
        proposer,
        jumboSigners,
    };
}

fun buildTransferActions(count: int, markerBase: int = 1000): DirectOrderActionsMap {
    val sink = net.treasury("fee_sink").address;
    var actionCells = array<cell> [];
    var i = 0;
    while (i < count) {
        actionCells.push(
            makeTransferAction(
                sink,
                ton("0.015"),
                markerBase + i,
                SEND_MODE_PAY_FEES_SEPARATELY,
                false,
            ).toCell(),
        );
        i += 1;
    }
    return packActionCells(actionCells);
}

fun executeEstimatedOrder(
    wallet: MultisigV2,
    firstSigner: address,
    secondSigner: address,
    order: DirectOrderActionsMap,
    expirationDate: int,
    extraValue: coins = ton("1"),
): (coins, SendResultList, SendResultList) {
    val estimate = wallet.getOrderEstimate(order, expirationDate);
    val seqno = wallet.getData().nextOrderSeqno;

    val create = wallet.sendNewOrder(
        firstSigner,
        order,
        expirationDate,
        true,
        0,
        MAX_ORDER_SEQNO,
        0,
        { value: (estimate + extraValue) as coins, bounce: true },
    );

    expect(create).toHaveSuccessfulTx<NewOrderRequest>({ from: firstSigner, to: wallet.address });

    val orderAddress = wallet.getOrderAddress(seqno);
    val orderContract = MultisigV2Order.fromAddress(orderAddress);

    val approve = orderContract.sendApprove(
        secondSigner,
        1,
        1,
        { value: ton("0.2"), bounce: true },
    );

    expect(approve).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: orderAddress,
        to: wallet.address,
    });

    return (estimate as coins, create, approve);
}

get fun `test fee: should send new order with contract estimated message value`() {
    val ctx = setupFeeContext();
    val order = buildTransferActions(1, 2000);

    val (_, create, approve) = executeEstimatedOrder(
        ctx.wallet,
        ctx.deployer.address,
        ctx.second.address,
        order,
        FEE_BASE_EXPIRATION,
    );

    expect(create).toHaveSuccessfulDeploy({ from: ctx.wallet.address });
    expect(approve).toHaveSuccessfulTx({ from: ctx.wallet.address });
}

get fun `test fee: should estimate correctly with 255 signers multisig`() {
    val ctx = setupFeeContext();
    val order = buildTransferActions(1, 3000);

    val (_, create, approve) = executeEstimatedOrder(
        ctx.jumboWallet,
        ctx.deployer.address,
        ctx.second.address,
        order,
        FEE_BASE_EXPIRATION,
    );

    expect(create).toHaveSuccessfulDeploy({ from: ctx.jumboWallet.address });
    expect(approve).toHaveSuccessfulTx({ from: ctx.jumboWallet.address });
}

get fun `test fee: should estimate correctly with large order`() {
    val ctx = setupFeeContext();
    val order = buildTransferActions(100, 4000);

    val (_, create, approve) = executeEstimatedOrder(
        ctx.jumboWallet,
        ctx.deployer.address,
        ctx.second.address,
        order,
        FEE_BASE_EXPIRATION,
    );

    expect(create).toHaveSuccessfulDeploy({ from: ctx.jumboWallet.address });
    expect(approve).toHaveSuccessfulTx({ from: ctx.jumboWallet.address });
}

get fun `test fee: should estimate correctly on gas fees change`() {
    val ctx = setupFeeContext();
    val order = buildTransferActions(1, 5000);

    val oldConfig = net.getConfig();
    var newConfig = oldConfig;

    var gasPrices = newConfig.getGasPrices(BASECHAIN);
    gasPrices.other.gasPrice *= 3;
    newConfig.setGasPrices(gasPrices, BASECHAIN);

    val estBefore = ctx.jumboWallet.getOrderEstimate(order, FEE_BASE_EXPIRATION);
    expect(net.setConfig(newConfig)).toEqual(true);
    val estAfter = ctx.jumboWallet.getOrderEstimate(order, FEE_BASE_EXPIRATION);

    expect(estAfter).toBeGreater(estBefore);

    val (_, _, approve) = executeEstimatedOrder(
        ctx.jumboWallet,
        ctx.deployer.address,
        ctx.second.address,
        order,
        FEE_BASE_EXPIRATION,
    );
    expect(approve).toHaveSuccessfulTx({ from: ctx.jumboWallet.address });

    expect(net.setConfig(oldConfig)).toEqual(true);
}

get fun `test fee: should estimate correctly on forward fees change`() {
    val ctx = setupFeeContext();
    val order = buildTransferActions(1, 6000);

    val oldConfig = net.getConfig();
    var newConfig = oldConfig;

    var msgPrices = newConfig.getMsgForwardPrices(BASECHAIN);
    msgPrices.bitPrice *= 10;
    msgPrices.cellPrice *= 10;
    newConfig.setMsgForwardPrices(msgPrices, BASECHAIN);

    val estBefore = ctx.jumboWallet.getOrderEstimate(order, FEE_BASE_EXPIRATION);
    expect(net.setConfig(newConfig)).toEqual(true);
    val estAfter = ctx.jumboWallet.getOrderEstimate(order, FEE_BASE_EXPIRATION);

    expect(estAfter).toBeGreater(estBefore);

    val (_, _, approve) = executeEstimatedOrder(
        ctx.jumboWallet,
        ctx.deployer.address,
        ctx.second.address,
        order,
        FEE_BASE_EXPIRATION,
    );
    expect(approve).toHaveSuccessfulTx({ from: ctx.jumboWallet.address });

    expect(net.setConfig(oldConfig)).toEqual(true);
}

get fun `test fee: should estimate correctly on storage fees change`() {
    val ctx = setupFeeContext();
    val order = buildTransferActions(1, 7000);

    val oldConfig = net.getConfig();
    var newConfig = oldConfig;

    var storagePrices = newConfig.getStoragePrices();
    var initial = storagePrices.getInitial();
    initial.bitPrice *= 10;
    initial.cellPrice *= 10;
    storagePrices.setInitial(initial);
    newConfig.setStoragePrices(storagePrices);

    val estBefore = ctx.jumboWallet.getOrderEstimate(order, FEE_BASE_EXPIRATION);
    expect(net.setConfig(newConfig)).toEqual(true);
    val estAfter = ctx.jumboWallet.getOrderEstimate(order, FEE_BASE_EXPIRATION);

    expect(estAfter).toBeGreater(estBefore);

    val (_, _, approve) = executeEstimatedOrder(
        ctx.jumboWallet,
        ctx.deployer.address,
        ctx.second.address,
        order,
        FEE_BASE_EXPIRATION,
    );
    expect(approve).toHaveSuccessfulTx({ from: ctx.jumboWallet.address });

    expect(net.setConfig(oldConfig)).toEqual(true);
}

fun runCommonCase(
    threshold: int,
    totalSigners: int,
    transferCount: int,
    expirationDate: int,
    signerCreates: bool,
): SendResultList {
    net.setNow(FEE_TEST_NOW as uint32);
    vm.registerLibrary(build("multisig_v2_order"));

    val deployer = net.treasury("fee_case_deployer");
    val proposer = net.treasury("fee_case_proposer");

    var signers = array<address> [];
    signers.push(deployer.address);

    var i = 1;
    while (i < totalSigners) {
        signers.push(createFundedAddress());
        i += 1;
    }

    val wallet = MultisigV2.fromConfig(
        threshold,
        signers,
        array<address> [proposer.address],
        false,
    );
    val deployRes = wallet.deploy(deployer.address, { value: ton("100"), bounce: false });
    expect(deployRes).toHaveSuccessfulDeploy({ to: wallet.address });

    val actions = buildTransferActions(transferCount, 8000);
    val estimate = wallet.getOrderEstimate(actions, expirationDate);

    val creator = signerCreates ? signers.get(0) : proposer.address;
    val creatorIndex = 0;
    val isAutoApprove = signerCreates;

    val create = wallet.sendNewOrder(
        creator,
        actions,
        expirationDate,
        isAutoApprove,
        creatorIndex,
        MAX_ORDER_SEQNO,
        0,
        { value: (estimate + FEE_DEFAULT_CREATE_VALUE) as coins, bounce: true },
    );
    expect(create).toHaveSuccessfulTx<NewOrderRequest>({ from: creator, to: wallet.address });

    val seqno = wallet.getData().nextOrderSeqno - 1;
    val order = MultisigV2Order.fromAddress(wallet.getOrderAddress(seqno));

    var signerIdx = signerCreates ? 1 : 0;
    var approveRes = create;
    while (signerIdx < threshold) {
        approveRes = order.sendApprove(
            signers.get(signerIdx),
            signerIdx,
            signerIdx as uint64,
            { value: ton("0.2"), bounce: true },
        );
        signerIdx += 1;
    }

    expect(approveRes).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: order.address,
        to: wallet.address,
    });
    expect(approveRes).toHaveSuccessfulTx({
        from: wallet.address,
        to: net.treasury("fee_sink").address,
    });

    return approveRes;
}

get fun `test fee: common cases gas fees multisig`() {
    val weekExpiration = FEE_BASE_EXPIRATION;

    val c1 = runCommonCase(7, 10, 1, weekExpiration, false);
    val c2 = runCommonCase(2, 3, 1, weekExpiration, true);
    val c3 = runCommonCase(1, 3, 1, weekExpiration, true);
    val c4 = runCommonCase(7, 10, 100, weekExpiration, false);

    expect(c1.size()).toBeGreater(0);
    expect(c2.size()).toBeGreater(0);
    expect(c3.size()).toBeGreater(0);
    expect(c4.size()).toBeGreater(0);
}

get fun `test fee: should be enough for 75 years`() {
    val ctx = setupFeeContext();
    val order = buildTransferActions(1, 9000);

    val timeSpan = 365 * 24 * 3600 * 75;
    val expirationDate = net.now() + timeSpan;

    val estimate = ctx.wallet.getOrderEstimate(order, expirationDate);
    val seqno = ctx.wallet.getData().nextOrderSeqno;

    val create = ctx
        .wallet
        .sendNewOrder(
            ctx.deployer.address,
            order,
            expirationDate,
            true,
            0,
            MAX_ORDER_SEQNO,
            0,
            { value: (estimate + ton("5")) as coins, bounce: true },
        );

    val orderContract = MultisigV2Order.fromAddress(ctx.wallet.getOrderAddress(seqno));
    expect(create).toHaveSuccessfulDeploy({ to: orderContract.address });

    net.setNow((expirationDate - 10) as uint32);

    val approve = orderContract.sendApprove(
        ctx.second.address,
        1,
        1,
        { value: ton("0.2"), bounce: true },
    );

    expect(approve).toHaveSuccessfulTx<ExecuteOrderRequest>({
        from: orderContract.address,
        to: ctx.wallet.address,
    });
}
