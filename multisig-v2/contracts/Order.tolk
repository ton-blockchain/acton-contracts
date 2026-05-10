import "errors"
import "messages"
import "order-helpers"
import "storage"
import "types"

contract Order {
    author: "The Tolk Team"
    version: "1.0.0"
    description: "Multisig V2 Order. Collects approvals and executes actions"
    incomingMessages: AllowedMessageToOrder
    storage: OrderStorageInitialized
    storageAtDeployment: OrderStorageHeader
}

type AllowedMessageToOrder = InitOrderRequest | ApproveRequest | TextComment

fun onInternalMessage(in: InMessage) {
    val storageLoader = startLoadingOrderStorage();
    val msg = lazy AllowedMessageToOrder.fromSlice(in.body);

    match (msg) {
        TextComment => {
            val textComment = getTextComment(msg.comment);
            assert (textComment.bitsEqual(COMMENT_APPROVE)) throw ERROR_UNKNOWN_OP;

            val header = storageLoader.loadHeader();
            assert (header.isInitialized()) throw ERROR_UNAUTHORIZED_SIGN;

            var storage = header.loadInitialized();
            val (signerIndex, foundSigner) = storage
                .remaining
                .signers
                .findSignerByAddress(in.senderAddress);

            assert (foundSigner) throw ERROR_UNAUTHORIZED_SIGN;
            storage.approve(signerIndex, in.senderAddress, blockchain.logicalTime());
        }

        InitOrderRequest => {
            val header = storageLoader.loadHeader();
            assert (in.senderAddress == header.multisigAddress) throw ERROR_UNAUTHORIZED_INIT;

            if (!header.isInitialized()) {
                var storage: OrderStorageInitialized = {
                    multisigAddress: header.multisigAddress,
                    orderSeqno: header.orderSeqno,
                    remaining: {
                        threshold: msg.threshold,
                        sentForExecution: false,
                        signers: msg.signers,
                        approvalsMask: 0,
                        approvalsNum: 0,
                        expirationDate: msg.expirationDate,
                        order: msg.order,
                    },
                };

                assert (storage.remaining.expirationDate >= blockchain.now()) throw ERROR_EXPIRED;

                if (msg.signerIndexOnInit != null) {
                    storage.addApproval(msg.signerIndexOnInit);
                    storage.tryExecute(msg.queryId);
                }

                storage.save();
                return;
            }

            var storage = header.loadInitialized();

            assert (msg.threshold == storage.remaining.threshold) throw ERROR_ALREADY_INITED;

            assert (
                msg.signers.hashCell() == storage.remaining.signers.hashCell()
            ) throw ERROR_ALREADY_INITED;

            assert (
                msg.expirationDate == storage.remaining.expirationDate
            ) throw ERROR_ALREADY_INITED;

            assert (
                msg.order.hashCell() == storage.remaining.order.hashCell()
            ) throw ERROR_ALREADY_INITED;

            assert (msg.signerIndexOnInit != null) throw ERROR_ALREADY_INITED;

            val signerIndex = msg.signerIndexOnInit!;
            val signerAddress = storage.remaining.signers.get(signerIndex);

            assert (signerAddress.isFound) throw ERROR_UNAUTHORIZED_SIGN;

            storage.approve(signerIndex, signerAddress.loadValue(), msg.queryId);
        }

        ApproveRequest => {
            val header = storageLoader.loadHeader();

            assert (header.isInitialized()) throw ERROR_UNAUTHORIZED_SIGN;
            var storage = header.loadInitialized();

            val signerAddress = storage.remaining.signers.get(msg.signerIndex);
            assert (signerAddress.isFound) throw ERROR_UNAUTHORIZED_SIGN;
            assert (in.senderAddress == signerAddress.loadValue()) throw ERROR_UNAUTHORIZED_SIGN;

            storage.approve(msg.signerIndex, in.senderAddress, msg.queryId);
        }

        else => throw ERROR_UNKNOWN_OP,
    }
}

get fun get_order_data(): OrderDataReply {
    val storageLoader = startLoadingOrderStorage();
    val header = storageLoader.loadHeader();

    if (!header.isInitialized()) {
        return {
            multisigAddress: header.multisigAddress,
            orderSeqno: header.orderSeqno,
            threshold: null,
            sentForExecution: null,
            signers: null,
            approvalsMask: null,
            approvalsNum: null,
            expirationDate: null,
            order: null,
        };
    }

    val storage = header.loadInitialized();

    return {
        multisigAddress: storage.multisigAddress,
        orderSeqno: storage.orderSeqno,
        threshold: storage.remaining.threshold,
        sentForExecution: storage.remaining.sentForExecution,
        signers: storage.remaining.signers.toLowLevelDict(),
        approvalsMask: storage.remaining.approvalsMask,
        approvalsNum: storage.remaining.approvalsNum,
        expirationDate: storage.remaining.expirationDate,
        order: storage.remaining.order.toLowLevelDict(),
    };
}
