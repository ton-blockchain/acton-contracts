import "@stdlib/gas-payments"
import "errors"
import "messages"
import "order-helpers"
import "storage"
import "types"

fun executeOrder(mutate storage: MultisigStorage, orderBody: NonEmptyOrderActionsMap) {
    setGasLimitToMaximum();

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
                storage.signersNum = signersNum as uint8;
                storage.proposers = action.proposers;
            }

            else => {
                // keep FunC behavior: ignore unknown action opcodes
            }
        }

        actionLookup = orderBody.iterateNext(actionLookup);
    }
}

fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) {
        return;
    }

    val msg = lazy AllowedMessageToMultisig.fromSlice(in.body);
    match (msg) {
        Op0WithRemainder => {
            // simple comment message: just accept tons
            return;
        }

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

            val signerOrProposer = msg.signer ? storage.signers : storage.proposers;
            val expectedSender = signerOrProposer.get(msg.index);

            assert (expectedSender.isFound) throw ERROR_UNAUTHORIZED_NEW_ORDER;
            assert (
                in.senderAddress == expectedSender.loadValue()
            ) throw ERROR_UNAUTHORIZED_NEW_ORDER;
            assert (msg.expirationDate >= blockchain.now()) throw ERROR_EXPIRED;

            val minimalValue = calculateOrderProcessingCost(
                msg.order,
                storage.signers,
                msg.expirationDate - blockchain.now()
            );
            assert (in.valueCoins >= minimalValue) throw ERROR_NOT_ENOUGH_TON;

            val signerIndexOnInit: SignerIndexOnInit = msg.signer ? msg.index : null;

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
            deployOrderMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE |
            SEND_MODE_BOUNCE_ON_ACTION_FAIL);
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

            executeOrder(mutate storage, msg.order);
            storage.save();
        }

        ExecuteInternalRequest => {
            var storage = lazy MultisigStorage.load();
            assert (in.senderAddress == contract.getAddress()) throw ERROR_UNAUTHORIZED_EXECUTE;
            executeOrder(mutate storage, msg.order);
            storage.save();
        }

        else => {
            // keep FunC behavior for unknown non-zero opcodes: accept and persist unchanged state
            val storage = lazy MultisigStorage.load();
            storage.save();
        }
    }
}

struct MultisigDataReply {
    nextOrderSeqno: int
    threshold: int
    signers: dict
    proposers: dict
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
        nextOrderSeqno: storage.allowArbitraryOrderSeqno ? -1 : storage.nextOrderSeqno as int,
        threshold: storage.threshold as int,
        signers: storage.signers.toLowLevelDict()!,
        proposers: storage.proposers.toLowLevelDict(),
    };
}

get fun get_order_estimate(order: cell, expirationDate: int): coins {
    val storage = lazy MultisigStorage.load();
    val orderBody = createMapFromLowLevelDict<uint8, cell>(order);

    return calculateOrderProcessingCost(
        orderBody,
        storage.signers,
        expirationDate - blockchain.now()
    );
}

get fun get_order_address(orderSeqno: int): address {
    return calculateOrderAddress(contract.getAddress(), orderSeqno);
}
