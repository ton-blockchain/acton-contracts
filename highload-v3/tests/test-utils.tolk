import "@acton/crypto"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "@acton/types/out_actions"
import "@acton/types/transaction"
import "../contracts/bitmap"
import "../contracts/storage"
import "../wrappers/HighloadWalletV3.gen"
import "../wrappers/utils"

const SUBWALLET_ID = 239
const DEFAULT_TIMEOUT = 128
const MAX_KEY_COUNT = (1 << 13)
const MAX_SHIFT = MAX_KEY_COUNT - 1
const MAX_BIT_NUMBER = 1022
const HIGHLOAD_DEPLOY_VALUE = 999999000000000000 // 999999 TON

struct TestContext {
    wallet: HighloadWalletV3
    deployer: Treasury
    notDeployer: Treasury
    keyPair: KeyPair
}

struct HighloadQueryId {
    shift: int
    bitNumber: int
}

struct (0x7abf6c01) TestExternalOutBody {
    marker: uint32
}

fun queryIdZero(): HighloadQueryId {
    return HighloadQueryId {
        shift: 0,
        bitNumber: 0,
    };
}

fun HighloadQueryId.fromShiftAndBitNumber(shift: int, bitNumber: int): HighloadQueryId {
    assert (shift >= 0) throw 11;
    assert (shift <= MAX_SHIFT) throw 11;
    assert (bitNumber >= 0) throw 11;
    assert (bitNumber <= MAX_BIT_NUMBER) throw 11;
    return HighloadQueryId { shift, bitNumber };
}

fun HighloadQueryId.fromQueryId(queryId: int): HighloadQueryId {
    return HighloadQueryId.fromShiftAndBitNumber(queryId >> 10, queryId & 1023);
}

fun HighloadQueryId.toInt(self): int {
    return (self.shift << 10) + self.bitNumber;
}

fun HighloadQueryId.getNext(self): HighloadQueryId {
    var nextShift = self.shift;
    var nextBit = self.bitNumber + 1;

    if (nextShift == MAX_SHIFT && nextBit > (MAX_BIT_NUMBER - 1)) {
        Assert.fail("Highload query id overload");
    }

    if (nextBit > MAX_BIT_NUMBER) {
        nextBit = 0;
        nextShift += 1;
        if (nextShift > MAX_SHIFT) {
            Assert.fail("Highload query id overload");
        }
    }

    return HighloadQueryId.fromShiftAndBitNumber(nextShift, nextBit);
}

fun setupHighloadTest(timeout: int = DEFAULT_TIMEOUT): TestContext {
    testing.setNow(1000);

    val keyPair = crypto.generateKeyPair();
    val deployer = testing.treasury("deployer");
    val notDeployer = testing.treasury("not-deployer");

    val wallet = HighloadWalletV3.fromConfig(keyPair.publicKey, SUBWALLET_ID, timeout);
    val deployRes = wallet.deploy(
        deployer.address,
        { value: HIGHLOAD_DEPLOY_VALUE, bounce: false },
    );
    expect(deployRes).toHaveSuccessfulDeploy({ to: wallet.address });

    return TestContext { wallet, deployer, notDeployer, keyPair };
}

fun setupHighloadTestWithKeyPair(
    keyPair: KeyPair,
    timeout: int = DEFAULT_TIMEOUT,
    deployerName: string = "deployer_alt",
): (HighloadWalletV3, Treasury) {
    val deployer = testing.treasury(deployerName);
    val wallet = HighloadWalletV3.fromConfig(keyPair.publicKey, SUBWALLET_ID, timeout);
    val deployRes = wallet.deploy(deployer.address, { value: ton("1000"), bounce: false });
    expect(deployRes).toHaveSuccessfulDeploy({ to: wallet.address });
    return (wallet, deployer);
}

fun requireTx(res: SendResultList, params: SearchParams = {}): TlbTransaction {
    val tx = res.findTransaction(params);
    expect(tx).toBeNotNull();
    return tx!;
}

fun countTxsOn(res: SendResultList, account: address): int {
    var count = 0;
    var i = 0;
    while (i < res.size()) {
        val tx = res.at(i).tx.load();
        if (tx.getAccountAddress() == account) {
            count += 1;
        }
        i += 1;
    }
    return count;
}

fun countTxsOnWithOutmsgCount(res: SendResultList, account: address, outmsgCount: int): int {
    var count = 0;
    var i = 0;
    while (i < res.size()) {
        val tx = res.at(i).tx.load();
        if (tx.getAccountAddress() == account && tx.outmsgCnt == outmsgCount) {
            count += 1;
        }
        i += 1;
    }
    return count;
}

fun activeAccountInfo(addr: address): TlbAccountInfo {
    val shard = testing.getShardAccount(addr);
    if (shard != null) {
        val acc = shard!.account.load();
        if (acc is TlbAccountInfo) {
            return acc;
        }
    }
    Assert.fail("Expected active account info");
}

fun activeCode(addr: address): cell {
    val info = activeAccountInfo(addr);
    if (info.storage.state !is TlbAccountStateActive) {
        Assert.fail("Expected active account state");
    }
    val code = info.storage.state.stateInit.code;
    if (code == null) {
        Assert.fail("Expected deployed code");
    }
    return code!;
}

fun activeDataCell(addr: address): cell {
    val info = activeAccountInfo(addr);
    if (info.storage.state is TlbAccountStateActive) {
        val active = info.storage.state;
        if (active.stateInit.data == null) {
            Assert.fail("Expected active account data");
        }
        return active.stateInit.data!;
    }
    Assert.fail("Expected active account state");
}

fun storedIsProcessed(wallet: HighloadWalletV3, queryId: int): bool {
    val st = HighloadWalletStorage.fromCell(activeDataCell(wallet.address));
    val shift = (queryId >> 10);
    val bitNumber = queryId & 1023;
    if (st.oldQueries.isProcessedInQueryMap(shift, bitNumber)) {
        return true;
    }
    return st.queries.isProcessedInQueryMap(shift, bitNumber);
}

fun storedIsProcessedInOldQueries(wallet: HighloadWalletV3, queryId: int): bool {
    val st = HighloadWalletStorage.fromCell(activeDataCell(wallet.address));
    val shift = (queryId >> 10);
    val bitNumber = queryId & 1023;
    return st.oldQueries.isProcessedInQueryMap(shift, bitNumber);
}

fun storedIsProcessedInCurrentQueries(wallet: HighloadWalletV3, queryId: int): bool {
    val st = HighloadWalletStorage.fromCell(activeDataCell(wallet.address));
    val shift = (queryId >> 10);
    val bitNumber = queryId & 1023;
    return st.queries.isProcessedInQueryMap(shift, bitNumber);
}

fun setActiveDataCell(addr: address, newData: cell) {
    val shard = testing.getShardAccount(addr);
    if (shard == null) {
        Assert.fail("Expected shard account when setting data");
    }

    var updatedShard = shard!;
    val account = updatedShard.account.load();
    if (account !is TlbAccountInfo) {
        Assert.fail("Expected TlbAccountInfo when setting data");
    }
    var info = account;
    if (info.storage.state !is TlbAccountStateActive) {
        Assert.fail("Expected active AccountState when setting data");
    }

    var active = info.storage.state;
    active.stateInit.data = newData;
    info.storage.state = active;
    updatedShard.account = (info as TlbAccount).toCell();
    testing.setShardAccount(addr, updatedShard);
}

fun emptyInternalTransferMessage(
    wallet: HighloadWalletV3,
    queryId: int = 0,
    value: coins = 0,
): cell {
    val actions = array<TlbOutAction> [];
    return wallet.createInternalTransferMessage(queryId, actions, value).messageCell;
}

fun buildSignedExternalBody(
    _wallet: HighloadWalletV3,
    keyPair: KeyPair,
    messageToSend: cell,
    mode: int,
    queryId: int,
    createdAt: int,
    subwalletId: int = SUBWALLET_ID,
    timeout: int = DEFAULT_TIMEOUT,
): cell {
    return HighloadWalletV3.buildExternalRequestBody(
        keyPair,
        HighloadExternalRequest { messageToSend, mode, queryId, createdAt, subwalletId, timeout },
    );
}

fun sendSignedExternal(
    wallet: HighloadWalletV3,
    keyPair: KeyPair,
    messageToSend: cell,
    mode: int,
    queryId: int,
    createdAt: int,
    subwalletId: int = SUBWALLET_ID,
    timeout: int = DEFAULT_TIMEOUT,
): SendResultList {
    return wallet.sendExternalRequest(
        keyPair,
        HighloadExternalRequest { messageToSend, mode, queryId, createdAt, subwalletId, timeout },
    );
}

fun trySendSignedExternal(
    wallet: HighloadWalletV3,
    keyPair: KeyPair,
    messageToSend: cell,
    mode: int,
    queryId: int,
    createdAt: int,
    subwalletId: int = SUBWALLET_ID,
    timeout: int = DEFAULT_TIMEOUT,
): SendResultList? {
    return wallet.trySendExternalRequest(
        keyPair,
        HighloadExternalRequest { messageToSend, mode, queryId, createdAt, subwalletId, timeout },
    );
}

fun trySendSignedExternalSingle(
    wallet: HighloadWalletV3,
    keyPair: KeyPair,
    messageToSend: cell,
    mode: int,
    queryId: int,
    createdAt: int,
    subwalletId: int = SUBWALLET_ID,
    timeout: int = DEFAULT_TIMEOUT,
): SendResult? {
    return wallet.trySendExternalRequestSingle(
        keyPair,
        HighloadExternalRequest { messageToSend, mode, queryId, createdAt, subwalletId, timeout },
    );
}

fun sendAction(
    to: address,
    value: coins,
    body: cell? = null,
    mode: int = 0,
    bounce: bool = false,
): TlbOutActionSendMessage {
    if (body == null) {
        body = createEmptyCell();
    }
    return TlbOutActionSendMessage {
        mode: mode as uint8,
        outMsg: createMessage({
            bounce,
            value,
            dest: to,
            body: body!,
        }).messageCell,
    };
}

fun externalOutAction(body: TestExternalOutBody, mode: int = 0): TlbOutActionSendMessage {
    return TlbOutActionSendMessage {
        mode: mode as uint8,
        outMsg: createExternalLogMessage({ dest: createAddressNone(), body }).messageCell,
    };
}

fun setCodeAction(newCode: cell): TlbOutActionSetCode {
    return TlbOutActionSetCode { newCode };
}

fun makeDenseQueriesLeftAligned(): QueryBitmapMap {
    var queries = QueryBitmapMap [];
    var i = 0;
    val paddingLen = 1023 - 13;
    while (i < MAX_KEY_COUNT) {
        var b = beginCell();
        b.storeUint(i, 13);
        b.storeZeroes(paddingLen);
        queries.set(i, b.endCell());
        i += 1;
    }
    return queries;
}

fun makeDenseQueriesRightAligned(): QueryBitmapMap {
    var queries = QueryBitmapMap [];
    var i = 0;
    val paddingLen = 1023 - 13;
    while (i < MAX_KEY_COUNT) {
        var b = beginCell();
        b.storeZeroes(paddingLen);
        b.storeUint(i, 13);
        queries.set(i, b.endCell());
        i += 1;
    }
    return queries;
}

fun preloadDenseQueryMaps(wallet: HighloadWalletV3, now: int) {
    var st = HighloadWalletStorage.fromCell(activeDataCell(wallet.address));
    st.oldQueries = makeDenseQueriesRightAligned();
    st.queries = makeDenseQueriesLeftAligned();
    st.lastCleanTime = now;
    setActiveDataCell(wallet.address, st.toCell());
}

fun badExternalOutWithBadSource(): cell {
    val invalidDestAsInternal = beginCell()
        .storeUint(2, 2) // addr_std$10
        .storeUint(0, 1) // anycast nothing
        .storeInt(0, 8)
        .storeUint(1, 10)
        .endCell();

    return beginCell()
        .storeUint(3, 2) // ext_out_msg_info$11
        .storeBool(false) // invalid src for MsgAddressInt
        .storeSlice(invalidDestAsInternal.beginParse())
        .endCell();
}

fun badExternalOutWithBadDest(): cell {
    val src = randomAddress("bad-ext-out-src");
    return beginCell()
        .storeUint(3, 2) // ext_out_msg_info$11
        .storeAddress(src)
        .storeBool(false) // invalid MsgAddressExt
        .endCell();
}

fun badExternalInWithBadSource(): cell {
    val maybeTruncatedExt = beginCell()
        .storeUint(1, 2) // addr_extern$01
        .storeUint(128, 9)
        .storeUint(0, 10)
        .endCell();

    return beginCell()
        .storeUint(2, 2) // ext_in_msg_info$10
        .storeSlice(maybeTruncatedExt.beginParse())
        .endCell();
}

fun badExternalInWithBadDest(): cell {
    return beginCell()
        .storeUint(2, 2) // ext_in_msg_info$10
        .storeUint(1, 2) // addr_extern$01
        .storeUint(256, 9)
        .storeUint(123456789, 256)
        .storeBool(false) // invalid MsgAddressInt
        .endCell();
}

fun badInternalMessageWithBadGrams(): cell {
    val src = randomAddress("bad-grams-src");
    val dst = randomAddress("bad-grams-dst");
    return beginCell()
        .storeUint(0, 1) // int_msg_info$0
        .storeUint(0, 1) // ihr_disabled
        .storeUint(0, 1) // bounce
        .storeUint(0, 1) // bounced
        .storeAddress(src)
        .storeAddress(dst)
        .storeUint(8, 4) // grams len
        .storeUint(1, 1) // invalid grams payload (truncated)
        .endCell();
}

fun badInternalMessageWithBadInitStateData(): cell {
    val src = randomAddress("bad-init-src");
    val dst = randomAddress("bad-init-dst");

    val brokenInit = beginCell()
        .storeUint(0, 1) // split_depth none
        .storeUint(1, 1) // special present
        .storeUint(1, 1) // tick
        .storeUint(0, 1) // tock
        .storeUint(1, 1) // code maybe ref
        .storeUint(1, 1) // data maybe ref
        .storeUint(1, 1) // library maybe ref (refs absent)
        .endCell();

    return beginCell()
        .storeUint(0, 1) // int_msg_info$0
        .storeUint(0, 1)
        .storeUint(0, 1)
        .storeUint(0, 1)
        .storeAddress(src)
        .storeAddress(dst)
        .storeCoins(0)
        .storeMaybeRef(null)
        .storeCoins(0)
        .storeCoins(0)
        .storeUint(1000, 64)
        .storeUint(1000, 32)
        .storeUint(1, 1) // maybe init
        .storeUint(1, 1) // either right
        .storeRef(brokenInit)
        .storeUint(0, 1) // body either left, but no body follows
        .endCell();
}

fun badPayloadMessages(): array<cell> {
    var result = array<cell> [];
    result.push(badExternalInWithBadDest());
    result.push(badExternalOutWithBadDest());
    result.push(badExternalInWithBadSource());
    result.push(badExternalOutWithBadSource());
    result.push(badInternalMessageWithBadGrams());
    result.push(badInternalMessageWithBadInitStateData());
    return result;
}
