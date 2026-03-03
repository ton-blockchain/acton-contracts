import "errors"
import "messages"
import "storage"
import "types"

fun getTextComment(inMsgBody: RemainingBitsAndRefs): slice {
    if (inMsgBody.remainingRefsCount() == 0) {
        return inMsgBody;
    }

    var combined = beginCell();
    var current = inMsgBody;

    var needExit = false;
    while (!needExit) {
        combined.storeSlice(current.preloadBits(current.remainingBitsCount()));

        if (current.remainingRefsCount() > 0) {
            current = current.preloadRef().beginParse();
        } else {
            needExit = true;
        }
    }

    return combined.endCell().beginParse();
}

fun findSignerByAddress(signers: NonEmptyIndexedAddressMap, signerAddress: address): (uint8, bool) {
    var signerIndex: uint8 = 0;
    var foundSigner = false;

    var item = signers.findFirst();
    while (item.isFound && !foundSigner) {
        val currentAddress = item.loadValue();
        if (currentAddress == signerAddress) {
            signerIndex = item.getKey();
            foundSigner = true;
        } else {
            item = signers.iterateNext(item);
        }
    }

    return (signerIndex, foundSigner);
}

fun OrderStorageInitialized.addApproval(mutate self, signerIndex: uint8) {
    val mask = (1 << signerIndex) as uint256;

    assert ((self.approvalsMask & mask) == 0) throw ERROR_ALREADY_APPROVED;

    self.approvalsNum += 1;
    self.approvalsMask |= mask;
}

fun OrderStorageInitialized.tryExecute(mutate self, queryId: int) {
    if (self.approvalsNum == self.threshold) {
        val executeMsg = createMessage({
            bounce: false,
            dest: self.multisigAddress,
            value: 0,
            body: ExecuteOrderRequest {
                queryId,
                orderSeqno: self.orderSeqno,
                expirationDate: self.expirationDate,
                approvalsNum: self.approvalsNum,
                signersHash: self.signers.hashCell(),
                order: self.order,
            },
        });
        executeMsg.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

        self.sentForExecution = true;
    }
}

fun OrderStorageInitialized.approve(
    mutate self,
    signerIndex: uint8,
    responseAddress: address,
    queryId: int,
) {
    try {
        assert (!self.sentForExecution) throw ERROR_ALREADY_EXECUTED;

        self.addApproval(signerIndex);

        val acceptedMsg = createMessage({
            bounce: false,
            dest: responseAddress,
            value: 0,
            body: ApproveAccepted { queryId },
        });
        acceptedMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE |
        SEND_MODE_BOUNCE_ON_ACTION_FAIL);

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

fun onInternalMessage(in: InMessage) {
    val storageLoader = startLoadingOrderStorage();
    val msg = lazy AllowedMessageToOrder.fromSlice(in.body);

    match (msg) {
        Op0WithRemainder => {
            val textComment = getTextComment(msg.remainder);
            assert (textComment.bitsEqual(COMMENT_APPROVE)) throw ERROR_UNKNOWN_OP;

            var signerIndex: uint8 = 0;
            var foundSigner = false;

            if (storageLoader.isInitialized()) {
                var storage = storageLoader.parseInitialized();
                (signerIndex, foundSigner) = findSignerByAddress(storage.signers, in.senderAddress);
                assert (foundSigner) throw ERROR_UNAUTHORIZED_SIGN;

                storage.approve(signerIndex, in.senderAddress, blockchain.logicalTime());
                return;
            }

            assert (foundSigner) throw ERROR_UNAUTHORIZED_SIGN;
        }

        InitOrderRequest => {
            val (multisigAddress, orderSeqno, _) = storageLoader.parseBase();
            assert (in.senderAddress == multisigAddress) throw ERROR_UNAUTHORIZED_INIT;

            if (!storageLoader.isInitialized()) {
                var storage: OrderStorageInitialized = {
                    multisigAddress,
                    orderSeqno,
                    threshold: msg.threshold,
                    sentForExecution: false,
                    signers: msg.signers,
                    approvalsMask: 0,
                    approvalsNum: 0,
                    expirationDate: msg.expirationDate,
                    order: msg.order,
                };

                assert (storage.expirationDate >= blockchain.now()) throw ERROR_EXPIRED;

                if (msg.signerIndexOnInit != null) {
                    storage.addApproval(msg.signerIndexOnInit);
                    storage.tryExecute(msg.queryId);
                }

                storage.save();
                return;
            }

            var storage = storageLoader.parseInitialized();

            assert (msg.threshold == storage.threshold) throw ERROR_ALREADY_INITED;
            assert (
                msg.signers.hashCell() == storage.signers.hashCell()
            ) throw ERROR_ALREADY_INITED;
            assert (msg.expirationDate == storage.expirationDate) throw ERROR_ALREADY_INITED;
            assert (msg.order.hashCell() == storage.order.hashCell()) throw ERROR_ALREADY_INITED;

            assert (msg.signerIndexOnInit != null) throw ERROR_ALREADY_INITED;

            val signerIndex = msg.signerIndexOnInit!;
            val signerAddress = storage.signers.get(signerIndex);
            assert (signerAddress.isFound) throw ERROR_UNAUTHORIZED_SIGN;

            storage.approve(signerIndex, signerAddress.loadValue(), msg.queryId as int);
            return;
        }

        ApproveRequest => {
            if (!storageLoader.isInitialized()) {
                throw ERROR_UNAUTHORIZED_SIGN;
            }

            var storage = storageLoader.parseInitialized();

            val signerAddress = storage.signers.get(msg.signerIndex);
            assert (signerAddress.isFound) throw ERROR_UNAUTHORIZED_SIGN;
            assert (in.senderAddress == signerAddress.loadValue()) throw ERROR_UNAUTHORIZED_SIGN;

            storage.approve(msg.signerIndex, in.senderAddress, msg.queryId as int);
            return;
        }

        else => throw ERROR_UNKNOWN_OP,
    }
}

fun onBouncedMessage(_in: InMessageBounced) {
    // ignore bounced messages
}

struct OrderDataReply {
    multisigAddress: address
    orderSeqno: int
    threshold: int?
    sentForExecution: bool?
    signers: dict
    approvalsMask: int?
    approvalsNum: int?
    expirationDate: int?
    order: dict
}

get fun get_order_data(): OrderDataReply {
    val storageLoader = startLoadingOrderStorage();
    val (multisigAddress, orderSeqno, _) = storageLoader.parseBase();

    if (!storageLoader.isInitialized()) {
        return {
            multisigAddress,
            orderSeqno: orderSeqno as int,
            threshold: null,
            sentForExecution: null,
            signers: null,
            approvalsMask: null,
            approvalsNum: null,
            expirationDate: null,
            order: null,
        };
    }

    val storage = storageLoader.parseInitialized();
    return {
        multisigAddress: storage.multisigAddress,
        orderSeqno: storage.orderSeqno as int,
        threshold: storage.threshold as int,
        sentForExecution: storage.sentForExecution,
        signers: storage.signers.toLowLevelDict(),
        approvalsMask: storage.approvalsMask as int,
        approvalsNum: storage.approvalsNum as int,
        expirationDate: storage.expirationDate as int,
        order: storage.order.toLowLevelDict(),
    };
}
