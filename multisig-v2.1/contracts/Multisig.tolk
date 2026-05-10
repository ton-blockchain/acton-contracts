import "@stdlib/gas-payments"
import "errors"
import "messages"
import "order-helpers"
import "order-state"
import "storage"
import "types"

contract Multisig {
    author: "The Tolk Team"
    version: "2.1"
    description: "Multisig V2.1. Multi-signature wallet with order-based approval"
    incomingMessages: AllowedMessageToMultisig
    storage: MultisigStorage
}

type AllowedOrderAction = SendMessageAction | UpdateMultisigParamsAction

@inline
fun executeOrder(mutate storage: MultisigStorage, orderBody: DirectOrderActionsMap): bool {
    // rare use of ACCEPT outside of external msg,
    // goal is to assure we have exactly max gas amount to process actions
    setGasLimitToMaximum();

    var isStorageUpdated = false;

    var actionLookup = orderBody.findFirst();
    while (actionLookup.isFound) {
        val actionCell = actionLookup.loadValue();
        val action = lazy AllowedOrderAction.fromCell(actionCell);

        match (action) {
            SendMessageAction => {
                sendRawMessage(action.message, action.mode);
            }

            UpdateMultisigParamsAction => {
                val signersNum = validateDictionarySequence(action.signers);

                assert (signersNum >= 1) throw ERROR_INVALID_SIGNERS;
                assert (action.threshold > 0) throw ERROR_INVALID_THRESHOLD;
                assert (action.threshold <= signersNum) throw ERROR_INVALID_THRESHOLD;

                validateDictionarySequence(action.proposers);

                storage.threshold = action.threshold;
                storage.signers = action.signers;
                storage.signersNum = signersNum;
                storage.proposers = action.proposers;
                isStorageUpdated = true;
            }

            else => {
                // keep FunC behavior: ignore unknown action opcodes
            }
        }

        actionLookup = orderBody.iterateNext(actionLookup);
    }

    return isStorageUpdated;
}

type AllowedMessageToMultisig =
    | NewOrderRequest
    | ExecuteOrderRequest
    | ExecuteInternalRequest
    | TextComment

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessageToMultisig.fromSlice(in.body);

    match (msg) {
        NewOrderRequest => {
            var storage = lazy MultisigStorage.load();
            var orderSeqno = msg.orderSeqno;

            if (!storage.allowArbitraryOrderSeqno) {
                if (orderSeqno == MAX_ORDER_SEQNO) {
                    orderSeqno = storage.nextOrderSeqno;
                } else {
                    assert (orderSeqno == storage.nextOrderSeqno) throw ERROR_INVALID_NEW_ORDER;
                }
                storage.nextOrderSeqno += 1;
            }

            val signerOrProposer = msg.isAutoApprove ? storage.signers : storage.proposers;
            val expectedSender = signerOrProposer.get(msg.index);

            assert (expectedSender.isFound) throw ERROR_UNAUTHORIZED_NEW_ORDER;
            assert (
                in.senderAddress == expectedSender.loadValue()
            ) throw ERROR_UNAUTHORIZED_NEW_ORDER;

            val now = blockchain.now();

            assert (msg.expirationDate >= now) throw ERROR_EXPIRED;

            val minimalValue = calculateOrderProcessingCost(
                msg.order,
                storage.signers,
                msg.expirationDate - now,
            );
            assert (in.valueCoins >= minimalValue) throw ERROR_NOT_ENOUGH_TON;

            val signerIndexOnInit: SignerIndexOnInit = msg.isAutoApprove ? msg.index : null;

            val deployOrderMsg = createMessage({
                bounce: true,
                dest: calculateOrderStateInit(contract.getAddress(), orderSeqno),
                value: 0,
                body: InitOrderRequest {
                    queryId: msg.queryId,
                    threshold: storage.threshold,
                    signers: storage.signers,
                    expirationDate: msg.expirationDate,
                    order: msg.order,
                    signerIndexOnInit,
                },
            });
            deployOrderMsg.send(
                SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL,
            );

            storage.save();
        }

        ExecuteOrderRequest => {
            var storage = lazy MultisigStorage.load();
            val expectedOrderAddress = calculateOrderAddress(contract.getAddress(), msg.orderSeqno);

            assert (in.senderAddress == expectedOrderAddress) throw ERROR_UNAUTHORIZED_EXECUTE;
            assert (
                msg.signersHash == storage.signers.hashCell() &&
                msg.approvalsNum >= storage.threshold
            ) throw ERROR_SIGNERS_OUTDATED;
            assert (msg.expirationDate >= blockchain.now()) throw ERROR_EXPIRED;

            if (executeOrder(mutate storage, msg.order)) {
                storage.save();
            }
        }

        ExecuteInternalRequest => {
            var storage = lazy MultisigStorage.load();
            assert (in.senderAddress == contract.getAddress()) throw ERROR_UNAUTHORIZED_EXECUTE;
            if (executeOrder(mutate storage, msg.order)) {
                storage.save();
            }
        }

        TextComment => {}

        else => {}
    }
}

get fun get_multisig_data(): MultisigDataReply {
    val storage = lazy MultisigStorage.load();

    val signersNum = validateDictionarySequence(storage.signers);
    assert (signersNum == storage.signersNum) throw ERROR_INCONSISTENT_DATA;

    validateDictionarySequence(storage.proposers);

    assert (signersNum >= 1) throw ERROR_INVALID_SIGNERS;
    assert (storage.threshold > 0) throw ERROR_INVALID_THRESHOLD;
    assert (storage.threshold <= signersNum) throw ERROR_INVALID_THRESHOLD;

    return {
        nextOrderSeqno: storage.allowArbitraryOrderSeqno ? -1 : storage.nextOrderSeqno,
        threshold: storage.threshold,
        signers: storage.signers.toLowLevelDict()!,
        proposers: storage.proposers.toLowLevelDict(),
    };
}

get fun get_order_estimate(order: cell, expirationDate: int): int {
    val storage = lazy MultisigStorage.load();
    val orderBody = createMapFromLowLevelDict<uint8, cell>(order);

    return calculateOrderProcessingCost(
        orderBody,
        storage.signers,
        expirationDate - blockchain.now(),
    );
}

get fun get_order_address(orderSeqno: int): address {
    return calculateOrderAddress(contract.getAddress(), orderSeqno);
}
