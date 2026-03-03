import "@stdlib/exotic-cells"
import "@stdlib/gas-payments"
import "types"
import "@gen/multisig_v2_order_code"

const MULTISIG_INIT_ORDER_GAS = 10232
const ORDER_INIT_GAS = 4614
const ORDER_EXECUTE_GAS = 11244
const MULTISIG_EXECUTE_GAS = 7576

const INIT_ORDER_BIT_OVERHEAD = 1337
const INIT_ORDER_CELL_OVERHEAD = 6
const ORDER_STATE_BIT_OVERHEAD = 1760
const ORDER_STATE_CELL_OVERHEAD = 6
const EXECUTE_ORDER_BIT_OVERHEAD = 664
const EXECUTE_ORDER_CELL_OVERHEAD = 1

struct OrderInitData {
    multisigAddress: address
    orderSeqno: uint256
}

fun getOrderCodeAsLibraryReference(): cell {
    return multisigV2OrderCompiledCode().toLibraryReference();
}

fun calculateOrderStateInit(multisigAddress: address, orderSeqno: uint256): AutoDeployAddress {
    return {
        stateInit: ContractState {
            code: getOrderCodeAsLibraryReference(),
            data: OrderInitData { multisigAddress, orderSeqno }.toCell(),
        },
        workchain: BASECHAIN,
    };
}

fun calculateOrderAddress(multisigAddress: address, orderSeqno: uint256): address {
    return calculateOrderStateInit(multisigAddress, orderSeqno).calculateAddress();
}

fun calculateOrderProcessingCost(
    orderBody: NonEmptyOrderActionsMap,
    signers: NonEmptyIndexedAddressMap,
    duration: int,
): coins {
    val orderDict = orderBody.toLowLevelDict()!;
    val signersDict = signers.toLowLevelDict()!;

    val gasBefore = getGasConsumedAtTheMoment();

    val (orderCells, orderBits, _) = orderDict.calculateSizeStrict(8192);
    val (signersCells, signersBits, _) = signersDict.calculateSizeStrict(512);

    val sizeCountingGas = getGasConsumedAtTheMoment() - gasBefore;

    val gasFees = calculateGasFee(BASECHAIN, MULTISIG_INIT_ORDER_GAS + sizeCountingGas) +
    calculateGasFee(BASECHAIN, ORDER_INIT_GAS) +
    calculateGasFee(BASECHAIN, ORDER_EXECUTE_GAS) +
    calculateGasFee(BASECHAIN, MULTISIG_EXECUTE_GAS);

    val forwardFees = calculateForwardFee(
        BASECHAIN,
        INIT_ORDER_BIT_OVERHEAD + orderBits + signersBits,
        INIT_ORDER_CELL_OVERHEAD + orderCells + signersCells
    ) +
    calculateForwardFee(
        BASECHAIN,
        EXECUTE_ORDER_BIT_OVERHEAD + orderBits,
        EXECUTE_ORDER_CELL_OVERHEAD + orderCells
    );

    val storageFees = calculateStorageFee(
        BASECHAIN,
        duration,
        ORDER_STATE_BIT_OVERHEAD + orderBits + signersBits,
        ORDER_STATE_CELL_OVERHEAD + orderCells + signersCells
    );

    return gasFees + forwardFees + storageFees;
}
