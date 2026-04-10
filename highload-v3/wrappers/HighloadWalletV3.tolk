import "@acton/build/build"
import "@acton/crypto/crypto"
import "@acton/emulation/network"
import "@acton/ffi/ffi"
import "@acton/testing/assert"
import "@acton/types/out_actions"
import "../contracts/messages"
import "../contracts/storage"

const HIGHLOAD_BIT_NUMBER_SIZE = 10
const HIGHLOAD_MAX_INLINE_ACTIONS = 254
const HIGHLOAD_CHAIN_CUT = 253

struct HighloadWalletV3 {
    address: address
    stateInit: ContractState? = null
}

struct HighloadExternalRequest {
    messageToSend: cell
    mode: int
    queryId: int
    createdAt: int
    subwalletId: int
    timeout: int
}

fun HighloadWalletV3.fromStorage(
    storage: HighloadWalletStorage,
    toShard: AddressShardingOptions? = null,
) {
    val stateInit = ContractState {
        code: build("HighloadWalletV3"),
        data: storage.toCell(),
    };
    val cAddress = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return HighloadWalletV3 {
        address: cAddress,
        stateInit,
    };
}

fun HighloadWalletV3.fromConfig(
    publicKey: int,
    subwalletId: int,
    timeout: int,
    toShard: AddressShardingOptions? = null,
) {
    return HighloadWalletV3.fromStorage(
        HighloadWalletStorage {
            publicKey,
            subwalletId: subwalletId as uint32,
            oldQueries: [],
            queries: [],
            lastCleanTime: 0,
            timeout: timeout as uint22,
        },
        toShard,
    );
}

fun HighloadWalletV3.fromAddress(address: address) {
    return HighloadWalletV3 { address };
}

fun HighloadWalletV3.code(self): cell {
    if (self.stateInit == null) {
        Assert.fail("Wrapper has no stateInit code (created via fromAddress)");
    }
    return self.stateInit!.code;
}

fun HighloadWalletV3.initialData(self): cell {
    if (self.stateInit == null) {
        Assert.fail("Wrapper has no stateInit data (created via fromAddress)");
    }
    return self.stateInit!.data;
}

fun HighloadWalletV3.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy contract created from address only");
    }
    val deployMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit! },
    });
    return net.send(from, deployMessage);
}

fun HighloadWalletV3.getPublicKey(self): int {
    return net.runGetMethod(self.address, "get_public_key");
}

fun HighloadWalletV3.getSubwalletId(self): int {
    return net.runGetMethod(self.address, "get_subwallet_id");
}

fun HighloadWalletV3.getTimeout(self): int {
    return net.runGetMethod(self.address, "get_timeout");
}

fun HighloadWalletV3.getLastCleanTime(self): int {
    return net.runGetMethod(self.address, "get_last_clean_time");
}

fun HighloadWalletV3.isProcessed(self, queryId: int, needClean: bool = true): bool {
    val cleanFlag = needClean ? -1 : 0;
    val res: int = net.runGetMethod(self.address, "processed?", [queryId, cleanFlag]);
    return res != 0;
}

fun HighloadWalletV3.queryIdShift(queryId: int): uint13 {
    return (queryId >> HIGHLOAD_BIT_NUMBER_SIZE);
}

fun HighloadWalletV3.queryIdBitNumber(queryId: int): uint10 {
    return (queryId & 1023);
}

fun packOutActions(actions: array<OutAction>): cell {
    var head = createEmptyCell() as Cell<OutList>;
    var i = 0;
    while (i < actions.size()) {
        head = OutList {
            prev: head,
            action: actions.get(i),
        }.toCell();
        i += 1;
    }
    return head;
}

fun packSendActionsToCell(messages: array<OutActionSendMessage>, start: int, count: int): cell {
    var head = createEmptyCell() as Cell<OutList>;
    var i = 0;
    while (i < count) {
        val action = messages.get(start + i);
        head = OutList {
            prev: head,
            action: action as OutActionSendMessage,
        }.toCell();
        i += 1;
    }
    return head;
}

fun HighloadWalletV3.createInternalTransferBody(queryId: int, actions: array<OutAction>) {
    return InternalTransfer {
        queryId: queryId as uint64,
        actions: packOutActions(actions),
    }.toCell();
}

fun HighloadWalletV3.createInternalTransferBodyFromActionsCell(queryId: int, actionsCell: cell) {
    return InternalTransfer {
        queryId: queryId as uint64,
        actions: actionsCell,
    }.toCell();
}

fun HighloadWalletV3.createInternalTransferMessage(
    self,
    queryId: int,
    actions: array<OutAction>,
    value: coins = 0,
): OutMessage {
    val body = HighloadWalletV3.createInternalTransferBody(queryId, actions);
    return createMessage({
        bounce: false,
        value,
        dest: self.address,
        body,
    });
}

fun HighloadWalletV3.createInternalTransferMessageFromActionsCell(
    self,
    queryId: int,
    actionsCell: cell,
    value: coins = 0,
): OutMessage {
    val body = HighloadWalletV3.createInternalTransferBodyFromActionsCell(queryId, actionsCell);
    return createMessage({
        bounce: false,
        value,
        dest: self.address,
        body,
    });
}

fun HighloadWalletV3.packActions(
    self,
    messages: array<OutActionSendMessage>,
    value: coins,
    queryId: int,
): OutMessage {
    return self.packActionsRange(messages, 0, messages.size(), value, queryId);
}

fun HighloadWalletV3.packActionsRange(
    self,
    messages: array<OutActionSendMessage>,
    start: int,
    count: int,
    value: coins,
    queryId: int,
): OutMessage {
    if (count > HIGHLOAD_MAX_INLINE_ACTIONS) {
        val chained = self.packActionsRange(
            messages,
            start + HIGHLOAD_CHAIN_CUT,
            count - HIGHLOAD_CHAIN_CUT,
            value,
            queryId,
        );
        val chainMode = value > 0 ? SEND_MODE_PAY_FEES_SEPARATELY : SEND_MODE_CARRY_ALL_BALANCE;

        var head = packSendActionsToCell(messages, start, HIGHLOAD_CHAIN_CUT) as Cell<OutList>;
        head = OutList {
            prev: head,
            action: OutActionSendMessage {
                mode: chainMode,
                outMsg: chained.messageCell,
            },
        }.toCell();

        return self.createInternalTransferMessageFromActionsCell(queryId, head, value);
    }

    val actionsCell = packSendActionsToCell(messages, start, count);
    return self.createInternalTransferMessageFromActionsCell(queryId, actionsCell, value);
}

fun HighloadWalletV3.buildExternalRequestBody(
    keyPair: KeyPair,
    req: HighloadExternalRequest,
): cell {
    val inner = MsgInner {
        subwalletId: req.subwalletId,
        messageToSend: req.messageToSend,
        sendMode: req.mode,
        shift: HighloadWalletV3.queryIdShift(req.queryId),
        bitNumber: HighloadWalletV3.queryIdBitNumber(req.queryId),
        createdAt: req.createdAt,
        timeout: req.timeout,
    }.toCell();

    val signature = crypto.sign(keyPair.privateKey, inner);
    return beginCell().storeSlice(signature).storeRef(inner).endCell();
}

fun HighloadWalletV3.sendExternalRequest(
    self,
    keyPair: KeyPair,
    req: HighloadExternalRequest,
): SendResultList {
    val body = HighloadWalletV3.buildExternalRequestBody(keyPair, req);
    return self.sendRawExternalBody(body);
}

fun HighloadWalletV3.sendRawExternalBody(self, body: cell): SendResultList {
    val res = net.sendExternal(createExternalMessage(self.address, body.beginParse()));
    if (res == null) {
        Assert.fail("External was not accepted");
    }
    return res;
}

fun HighloadWalletV3.trySendRawExternalBody(self, body: cell): SendResultList? {
    val msg = createExternalMessage(self.address, body.beginParse());
    val extSrc = address("-1:0000000000000000000000000000000000000000000000000000000000000000");
    return ffi.sendMessageFrom(msg.messageCell, extSrc.toCell());
}

fun HighloadWalletV3.trySendRawExternalBodySingle(self, body: cell): SendResult? {
    val msg = createExternalMessage(self.address, body.beginParse());
    val extSrc = address("-1:0000000000000000000000000000000000000000000000000000000000000000");
    val raw = ffi.sendSingleMessage(msg.messageCell, extSrc.toCell());
    if (raw == null) {
        return null;
    }
    return SendResult.fromTuple(raw);
}

fun HighloadWalletV3.sendBatch(
    self,
    keyPair: KeyPair,
    messages: array<OutActionSendMessage>,
    subwalletId: int,
    queryId: int,
    timeout: int,
    createdAt: int,
    value: coins = 0,
): SendResultList {
    val internalTransfer = self.packActions(messages, value, queryId);
    val mode = value > 0 ? SEND_MODE_PAY_FEES_SEPARATELY : SEND_MODE_CARRY_ALL_BALANCE;
    return self.sendExternalRequest(
        keyPair,
        HighloadExternalRequest {
            messageToSend: internalTransfer.messageCell,
            mode,
            queryId,
            createdAt,
            subwalletId,
            timeout,
        },
    );
}

fun HighloadWalletV3.trySendExternalRequest(
    self,
    keyPair: KeyPair,
    req: HighloadExternalRequest,
): SendResultList? {
    val body = HighloadWalletV3.buildExternalRequestBody(keyPair, req);
    return self.trySendRawExternalBody(body);
}

fun HighloadWalletV3.trySendExternalRequestSingle(
    self,
    keyPair: KeyPair,
    req: HighloadExternalRequest,
): SendResult? {
    val body = HighloadWalletV3.buildExternalRequestBody(keyPair, req);
    return self.trySendRawExternalBodySingle(body);
}
