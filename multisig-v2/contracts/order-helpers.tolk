import "@stdlib/exotic-cells"
import "@stdlib/gas-payments"
import "errors"
import "messages"
import "storage"
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
    orderBody: DirectOrderActionsMap,
    signers: DirectIndexedAddressMap,
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

// TODO: optimize short-return?
fun getTextComment(inMsgBody: RemainingBitsAndRefs): slice {
    var result = beginCell();

    result.storeSlice(inMsgBody.preloadBits(inMsgBody.remainingBitsCount()));

    repeat (inMsgBody.depth()) {
        inMsgBody = inMsgBody.preloadRef().beginParse();
        result.storeSlice(inMsgBody.preloadBits(inMsgBody.remainingBitsCount()));
    }

    return result.toSlice();
}

// TODO: remove while?
fun DirectIndexedAddressMap.findSignerByAddress(self, signerAddress: address): (uint8, bool) {
    var signerIndex: uint8 = 0;
    var foundSigner = false;

    var item = self.findFirst();
    while (item.isFound && !foundSigner) {
        val currentAddress = item.loadValue();
        if (currentAddress == signerAddress) {
            signerIndex = item.getKey();
            foundSigner = true;
        } else {
            item = self.iterateNext(item);
        }
    }

    return (signerIndex, foundSigner);
}

fun OrderStorageInitialized.addApproval(mutate self, signerIndex: uint8) {
    val mask = (1 << signerIndex);

    assert ((self.remaining.approvalsMask & mask) == 0) throw ERROR_ALREADY_APPROVED;

    self.remaining.approvalsNum += 1;
    self.remaining.approvalsMask |= mask;
}

fun OrderStorageInitialized.tryExecute(mutate self, queryId: uint64) {
    if (self.remaining.approvalsNum == self.remaining.threshold) {
        val executeMsg = createMessage({
            bounce: false,
            dest: self.multisigAddress,
            value: 0,
            body: ExecuteOrderRequest {
                queryId,
                orderSeqno: self.orderSeqno,
                expirationDate: self.remaining.expirationDate,
                approvalsNum: self.remaining.approvalsNum,
                signersHash: self.remaining.signers.hashCell(),
                order: self.remaining.order,
            },
        });
        // SAFETY: if we execute, we want order to be drained empty
        executeMsg.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

        self.remaining.sentForExecution = true;
    }
}

fun OrderStorageInitialized.approve(
    mutate self,
    signerIndex: uint8,
    responseAddress: address,
    queryId: uint64,
) {
    // TODO: can we remove try-catch?
    try {
        assert (!self.remaining.sentForExecution) throw ERROR_ALREADY_EXECUTED;

        self.addApproval(signerIndex);

        val acceptMsg = createMessage({
            bounce: false,
            dest: responseAddress,
            value: 0,
            body: ApproveAccepted { queryId },
        });
        acceptMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

        // we can throw only if this signer has already approved this order
        self.tryExecute(queryId);
        self.save();
    } catch (exitCode) {
        val rejectedMsg = createMessage({
            bounce: false,
            dest: responseAddress,
            value: 0,
            body: ApproveRejected { queryId, exitCode },
        });
        rejectedMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE |
        SEND_MODE_BOUNCE_ON_ACTION_FAIL);
    }
}
