import "@stdlib/gas-payments"
import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/tlb/maybe"
import "@acton/types/transaction"
import "test-utils"
import "../contracts/messages"
import "../contracts/order-helpers"
import "../contracts/types"
import "../wrappers/Multisig.gen"
import "../wrappers/utils"

const PROBE_NOW = 1000

struct RuntimeFeeProbe {
    signersMap: DirectIndexedAddressMap
    order: DirectOrderActionsMap
    duration: int
    measuredMultisigInitBase: int
    measuredOrderInit: int
    measuredOrderExecute: int
    measuredMultisigExecute: int
    predictedInitFwd: coins
    actualInitFwd: coins
    predictedExecFwd: coins
    actualExecFwd: coins
    predictedStorage: coins
    actualStorage: coins
    estimatedTotal: coins
    actualTotal: coins
}

fun createFundedAddressLocal(): address {
    val addr = randomAddress("fee_probe_signer");
    testing.topUp(addr, ton("100"));
    return addr;
}

fun makeTransferActionLocal(to: address, marker: int): SendMessageAction {
    val transferMessage = createMessage({
        bounce: true,
        value: ton("0.01"),
        dest: to,
        body: beginCell().storeUint(marker, 32).endCell(),
    });
    return { mode: SEND_MODE_PAY_FEES_SEPARATELY, message: transferMessage.messageCell };
}

fun makeProbeOrder(): DirectOrderActionsMap {
    val action = makeTransferActionLocal(randomAddress("fee_probe_dest"), 424242);
    var order: DirectOrderActionsMap = [];
    order.set(0, action.toCell());
    return order;
}

fun getStorageCollected(tx: TlbTransaction): coins {
    val desc = tx.description.load();
    if (desc !is TlbTransOrd) {
        return 0;
    }

    if (desc.storagePh is TlbNone) {
        return 0;
    }

    return desc.storagePh.value.storageFeesCollected;
}

fun computeSizeCountingGas(order: DirectOrderActionsMap, signers: DirectIndexedAddressMap): int {
    val gasBefore = getGasConsumedAtTheMoment();
    order.toLowLevelDict()!.calculateSizeStrict(8192);
    signers.toLowLevelDict()!.calculateSizeStrict(512);
    return getGasConsumedAtTheMoment() - gasBefore;
}

fun buildRuntimeFeeProbe(signerCount: int, duration: int = 1000): RuntimeFeeProbe {
    assert (signerCount >= 2) throw 9401;

    testing.setNow(PROBE_NOW);
    testing.registerLibrary(build("Order"));

    val signer0 = signerCount > 10
        ? testing.treasury("fee-probe-s0-jumbo")
        : testing.treasury("fee-probe-s0-small");
    val signer1 = signerCount > 10
        ? testing.treasury("fee-probe-s1-jumbo")
        : testing.treasury("fee-probe-s1-small");
    val proposer = signerCount > 10
        ? testing.treasury("fee-probe-p-jumbo")
        : testing.treasury("fee-probe-p-small");

    var signers = array<address> [signer0.address, signer1.address];
    var i = 2;
    while (i < signerCount) {
        signers.push(createFundedAddressLocal());
        i += 1;
    }

    val multisig = Multisig.fromConfig(2, signers, array<address> [proposer.address], false);
    val deployValue = signerCount > 10 ? ton("200") : ton("20");
    val deploy = multisig.deployWithInitBody(
        signer0.address,
        { value: deployValue, bounce: false },
    );
    expect(deploy).toHaveSuccessfulDeploy({ to: multisig.address });

    val signersMap = toDirectIndexedAddressMap(signers);
    val order = makeProbeOrder();
    val expiration = testing.getNow() + duration;
    val orderSeqno = multisig.getData().nextOrderSeqno;

    val createValue = signerCount > 10 ? ton("20") : ton("5");
    val create = multisig.sendNewOrder(
        signer0.address,
        order,
        expiration,
        true,
        0,
        MAX_ORDER_SEQNO,
        0,
        { value: createValue, bounce: true },
    );

    val orderAddress = multisig.getOrderAddress(orderSeqno);
    testing.setNow(expiration);

    val approve = net.send(
        signer1.address,
        createMessage({
            bounce: true,
            value: ton("0.3"),
            dest: orderAddress,
            body: ApproveRequest {
                queryId: 1,
                signerIndex: 1,
            },
        }),
    );

    val multisigInitTx = create.findTransaction<NewOrderRequest>({
        from: signer0.address,
        to: multisig.address,
    });
    val orderInitTx = create.findTransaction<InitOrderRequest>({
        from: multisig.address,
        to: orderAddress,
    });
    val orderExecuteTx = approve.findTransaction<ApproveRequest>({
        from: signer1.address,
        to: orderAddress,
    });
    val multisigExecuteTx = approve.findTransaction<ExecuteOrderRequest>({
        from: orderAddress,
        to: multisig.address,
    });

    expect(multisigInitTx).toBeNotNull();
    expect(orderInitTx).toBeNotNull();
    expect(orderExecuteTx).toBeNotNull();
    expect(multisigExecuteTx).toBeNotNull();

    val multisigInit = multisigInitTx!;
    val orderInit = orderInitTx!;
    val orderExecute = orderExecuteTx!;
    val multisigExecute = multisigExecuteTx!;

    val sizeCountingGas = computeSizeCountingGas(order, signersMap);

    val measuredMultisigInit = multisigInit.getUsedGas();
    val measuredMultisigInitBase = measuredMultisigInit - sizeCountingGas;
    val measuredOrderInit = orderInit.getUsedGas();
    val measuredOrderExecute = orderExecute.getUsedGas();
    val measuredMultisigExecute = multisigExecute.getUsedGas();

    val orderDict = order.toLowLevelDict()!;
    val signersDict = signersMap.toLowLevelDict()!;
    val (orderCells, orderBits, _) = orderDict.calculateSizeStrict(8192);
    val (signersCells, signersBits, _) = signersDict.calculateSizeStrict(512);

    val predictedInitFwd = calculateForwardFee(
        BASECHAIN,
        INIT_ORDER_BIT_OVERHEAD + orderBits + signersBits,
        INIT_ORDER_CELL_OVERHEAD + orderCells + signersCells,
    );
    val predictedExecFwd = calculateForwardFee(
        BASECHAIN,
        EXECUTE_ORDER_BIT_OVERHEAD + orderBits,
        EXECUTE_ORDER_CELL_OVERHEAD + orderCells,
    );
    val predictedStorage = calculateStorageFee(
        BASECHAIN,
        duration,
        ORDER_STATE_BIT_OVERHEAD + orderBits + signersBits,
        ORDER_STATE_CELL_OVERHEAD + orderCells + signersCells,
    );

    val actualInitFwd = orderInit.loadInMsg<InitOrderRequest>().info.toInternal().forwardFee;
    val actualExecFwd = multisigExecute
        .loadInMsg<ExecuteOrderRequest>()
        .info
        .toInternal()
        .forwardFee;
    val actualStorage = getStorageCollected(orderExecute);

    val actualGasFee = calculateGasFee(BASECHAIN, measuredMultisigInit) +
    calculateGasFee(BASECHAIN, measuredOrderInit) +
    calculateGasFee(BASECHAIN, measuredOrderExecute) +
    calculateGasFee(BASECHAIN, measuredMultisigExecute);

    val actualTotal = actualGasFee + actualInitFwd + actualExecFwd + actualStorage;
    val estimatedTotal = calculateOrderProcessingCost(order, signersMap, duration);

    return {
        signersMap,
        order,
        duration,
        measuredMultisigInitBase,
        measuredOrderInit,
        measuredOrderExecute,
        measuredMultisigExecute,
        predictedInitFwd,
        actualInitFwd,
        predictedExecFwd,
        actualExecFwd,
        predictedStorage,
        actualStorage,
        estimatedTotal,
        actualTotal,
    };
}

fun assertGasConstantWindow(actual: int, configured: int) {
    expect(configured).toBeGreaterOrEqual(actual);
}

fun assertFeeConstantWindow(actual: coins, predicted: coins) {
    expect(predicted).toBeGreaterOrEqual(actual);
}

get fun `test constants: gas constants should be upper ceilings on small signer set`() {
    val probe = buildRuntimeFeeProbe(2);

    assertGasConstantWindow(probe.measuredMultisigInitBase, MULTISIG_INIT_ORDER_GAS);
    assertGasConstantWindow(probe.measuredOrderInit, ORDER_INIT_GAS);
    assertGasConstantWindow(probe.measuredOrderExecute, ORDER_EXECUTE_GAS);
    assertGasConstantWindow(probe.measuredMultisigExecute, MULTISIG_EXECUTE_GAS);
}

get fun `test constants: gas constants should be upper ceilings on jumbo signer set`() {
    val probe = buildRuntimeFeeProbe(255);

    assertGasConstantWindow(probe.measuredMultisigInitBase, MULTISIG_INIT_ORDER_GAS);
    assertGasConstantWindow(probe.measuredOrderInit, ORDER_INIT_GAS);
    assertGasConstantWindow(probe.measuredOrderExecute, ORDER_EXECUTE_GAS);
    assertGasConstantWindow(probe.measuredMultisigExecute, MULTISIG_EXECUTE_GAS);
}

get fun `test constants: forward and storage overhead constants should be upper ceilings`() {
    val small = buildRuntimeFeeProbe(2);
    val jumbo = buildRuntimeFeeProbe(255);

    assertFeeConstantWindow(small.actualInitFwd, small.predictedInitFwd);
    assertFeeConstantWindow(small.actualExecFwd, small.predictedExecFwd);
    assertFeeConstantWindow(small.actualStorage, small.predictedStorage);

    assertFeeConstantWindow(jumbo.actualInitFwd, jumbo.predictedInitFwd);
    assertFeeConstantWindow(jumbo.actualExecFwd, jumbo.predictedExecFwd);
    assertFeeConstantWindow(jumbo.actualStorage, jumbo.predictedStorage);
}

get fun `test helpers: calculateOrderProcessingCost should be upper ceiling for observed total fees`() {
    val small = buildRuntimeFeeProbe(2);
    val jumbo = buildRuntimeFeeProbe(255);

    expect(small.estimatedTotal).toBeGreaterOrEqual(small.actualTotal);

    expect(jumbo.estimatedTotal).toBeGreaterOrEqual(jumbo.actualTotal);
}
