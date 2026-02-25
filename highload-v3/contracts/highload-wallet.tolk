import "@stdlib/gas-payments"
import "bitmap"
import "errors"
import "messages"
import "storage"

fun setActions(actions: cell): void
    asm "c5 POP"

fun validateMessageToSend(messageToSend: cell) {
    var messageSlice = messageToSend.beginParse();

    assert (messageSlice.loadUint(1) == 0) throw ERROR_INVALID_MESSAGE_TO_SEND; // int_msg_info$0

    val msgFlags = messageSlice.loadUint(3); // ihr_disabled, bounce, bounced
    if ((msgFlags & 1) != 0) {
        return;
    }

    val sourceAddress = messageSlice.loadAddressAny();
    assert (sourceAddress.isNone()) throw ERROR_INVALID_MESSAGE_TO_SEND;

    messageSlice.loadAddressAny(); // dest
    messageSlice.loadCoins(); // value.coins
    messageSlice.skipDict(); // value.other
    messageSlice.loadCoins(); // ihr_fee
    messageSlice.loadCoins(); // fwd_fee
    messageSlice.skipBits(64 + 32); // created_lt + created_at

    val maybeStateInit = messageSlice.loadUint(1);
    assert (maybeStateInit == 0) throw ERROR_INVALID_MESSAGE_TO_SEND;

    val eitherBody = messageSlice.loadUint(1);
    if (eitherBody != 0) {
        messageSlice.loadRef();
        messageSlice.assertEnd();
    }
}

fun onInternalMessage(in: InMessage) {
    val (bodyBits, bodyRefs) = in.body.remainingBitsAndRefsCount();
    if (bodyRefs != 1 || bodyBits != INTERNAL_TRANSFER_BODY_BITS) {
        return; // just accept tons
    }

    if (in.senderAddress != contract.getAddress()) {
        return; // just accept tons
    }

    // TODO: other way to do this?
    if (in.body.preloadUint(32) != OP_INTERNAL_TRANSFER) {
        return;
    }

    val msg = lazy InternalTransfer.fromSlice(in.body);

    val oldCode = contract.getCode();
    setActions(msg.actions);
    contract.setCodePostponed(oldCode); // prevent actions from changing code
}

fun onExternalMessage(in: InMessage) {
    val msg = lazy ExternalTransferRequest.fromSlice(in.body);

    val msgInner = msg.inner;
    val signature = msg.signature;

    var storage = lazy HighloadWalletStorage.load();
    val now = blockchain.now();
    storage.cleanupQueryWindows(now);

    // TODO: type alias
    assert (
        isSignatureValid(msgInner.hash(), signature as slice, storage.publicKey)
    ) throw ERROR_INVALID_SIGNATURE;

    val request = msgInner.load();

    val createdAt = request.createdAt;
    val timeout = storage.timeout;
    val shift = request.shift;
    val bitNumber = request.bitNumber;

    assert (request.subwalletId == storage.subwalletId) throw ERROR_INVALID_SUBWALLET_ID;
    assert (request.timeout == storage.timeout) throw ERROR_INVALID_TIMEOUT;
    assert (createdAt > (now - timeout)) throw ERROR_INVALID_CREATED_AT;
    assert (createdAt <= now) throw ERROR_INVALID_CREATED_AT;

    assert (
        !isProcessedInQueryMap(storage.oldQueries, shift, bitNumber)
    ) throw ERROR_ALREADY_EXECUTED;

    val (newQueries, wasMarked) = markProcessedInQueryMap(storage.queries, shift, bitNumber);
    assert (wasMarked) throw ERROR_ALREADY_EXECUTED;
    storage.queries = newQueries;

    acceptExternalMessage();

    storage.save();
    commitContractDataAndActions();

    validateMessageToSend(request.messageToSend);
    sendRawMessage(request.messageToSend, request.sendMode + SEND_MODE_IGNORE_ERRORS);
}

get fun get_public_key(): int {
    val storage = lazy HighloadWalletStorage.load();
    return storage.publicKey;
}

get fun get_subwallet_id(): int {
    val storage = lazy HighloadWalletStorage.load();
    return storage.subwalletId;
}

get fun get_last_clean_time(): int {
    val storage = lazy HighloadWalletStorage.load();
    return storage.lastCleanTime;
}

get fun get_timeout(): int {
    val storage = lazy HighloadWalletStorage.load();
    return storage.timeout;
}

fun queryIdShift(queryId: int): uint13 {
    return (queryId >> BIT_NUMBER_SIZE) as uint13;
}

fun queryIdBitNumber(queryId: int): int {
    return queryId & CELL_BITS_SIZE;
}

get fun `processed?`(queryId: int, needClean: int): bool {
    val shift = queryIdShift(queryId);
    val bitNumber = queryIdBitNumber(queryId);

    var storage = lazy HighloadWalletStorage.load();
    if (needClean != 0) {
        storage.cleanupQueryWindows(blockchain.now());
    }

    if (isProcessedInQueryMap(storage.oldQueries, shift, bitNumber)) {
        return true;
    }
    if (isProcessedInQueryMap(storage.queries, shift, bitNumber)) {
        return true;
    }

    return false;
}
