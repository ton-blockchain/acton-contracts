import "@stdlib/gas-payments"
import "bitmap"
import "errors"
import "messages"
import "storage"
import "validate-c5"

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
    setTvmRegisterC5(msg.actions);
    contract.setCodePostponed(oldCode); // prevent actions from changing code
}

fun onExternalMessage(inBody: slice) {
    val msg = lazy ExternalTransferRequest.fromSlice(inBody);

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
    // assert (bitNumber < CELL_BITS_SIZE) throw ERROR_INVALID_MESSAGE_TO_SEND;
    assert (createdAt > (now - timeout)) throw ERROR_INVALID_CREATED_AT;
    assert (createdAt <= now) throw ERROR_INVALID_CREATED_AT;

    assert (
        !storage.oldQueries.isProcessedInQueryMap(shift, bitNumber)
    ) throw ERROR_ALREADY_EXECUTED;

    assert (
        !storage.queries.isProcessedInQueryMap(shift, bitNumber)
    ) throw ERROR_ALREADY_EXECUTED;

    acceptExternalMessage();

    val (newQueries, wasMarked) = storage.queries.markProcessedInQueryMap(shift, bitNumber);
    assert (wasMarked) throw ERROR_ALREADY_EXECUTED;
    storage.queries = newQueries;

    storage.save();
    commitContractDataAndActions();

    if (!validateMessageToSend(request.messageToSend)) {
        return;
    }

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

    if (storage.oldQueries.isProcessedInQueryMap(shift, bitNumber)) {
        return true;
    }
    if (storage.queries.isProcessedInQueryMap(shift, bitNumber)) {
        return true;
    }

    return false;
}
