import "@acton/crypto"
import "@acton/ffi"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/WalletV5.gen"
import "../wrappers/utils"

const W5_BENCH_KEY_SEED = 0x57550001
const W5_BENCH_NOW = 1000
const W5_BENCH_VALID_UNTIL = 2000

const W5_BENCH_DEPLOY_VALUE = ton("0.05")
const W5_BENCH_TOP_UP_VALUE = ton("10")
const W5_BENCH_SIGNED_INTERNAL_VALUE = ton("0.1")
const W5_BENCH_EXTENSION_CALL_VALUE = ton("0.1")

const W5_BENCH_TRANSFER_VALUE = ton("1")
const W5_BENCH_EXTENSION_TRANSFER_VALUE = ton("0.001")

struct W5BenchFixture {
    wallet: WalletV5
    deployer: Treasury
    receiver: Treasury
    keyPair: KeyPair
}

fun w5BenchKeyPair(): KeyPair {
    return crypto.seedToKeyPair(W5_BENCH_KEY_SEED as uint256);
}

fun w5BenchRawTransferMessage(dest: address, value: coins): cell {
    return beginCell()
        .storeUint(0x10, 6)
        .storeAddress(dest)
        .storeCoins(value)
        .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .storeRef(createEmptyCell())
        .endCell();
}

fun w5BenchSendTxAction(dest: address, value: coins): SendAction {
    return SendAction {
        mode: SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS,
        messageCell: w5BenchRawTransferMessage(dest, value),
    };
}

fun w5BenchSendTxActions(dest: address, value: coins): ActionsList {
    var outActions: array<SendAction> = [];
    outActions.push(w5BenchSendTxAction(dest, value));

    return ActionsList {
        outActions,
        extraActions: [],
    };
}

fun w5BenchAddExtensionActions(extension: address): ActionsList {
    var extraActions: array<ExtraAction> = [];
    extraActions.push(AddExtensionExtraAction { addr: extension });

    return ActionsList {
        outActions: [],
        extraActions,
    };
}

fun w5BenchExtensionExists(wallet: WalletV5, extension: address): bool {
    val extensions = wallet.getExtensions();
    val (_, extensionHash) = extension.getWorkchainAndHash();
    return extensions.exists(extensionHash);
}

fun deployW5BenchFixture(): W5BenchFixture {
    testing.setNow(W5_BENCH_NOW);

    val keyPair = w5BenchKeyPair();
    val deployer = testing.treasury("deployer");
    val receiver = testing.treasury("receiver");

    val storage = Storage {
        isSignatureAllowed: true,
        seqno: 0,
        subwalletId: DEFAULT_SUBWALLET_ID,
        publicKey: keyPair.publicKey,
        extensions: [],
    };
    val wallet = WalletV5.fromStorage(storage);

    val deployResult = wallet.deploy(
        deployer.address,
        { value: W5_BENCH_DEPLOY_VALUE, bounce: false },
    );
    deployResult.giveName("setup deploy WalletV5");
    expect(deployResult).toHaveSuccessfulDeploy({
        from: deployer.address,
        to: wallet.address,
    });

    val topUpResult = wallet.sendAny(
        deployer.address,
        createEmptyCell(),
        { value: W5_BENCH_TOP_UP_VALUE },
    );
    topUpResult.giveName("setup top up WalletV5");

    expect(wallet.getSeqno()).toEqual(0);
    expect(wallet.getPublicKey()).toEqual(keyPair.publicKey);

    return W5BenchFixture { wallet, deployer, receiver, keyPair };
}

fun sendW5BenchSignedExternal(
    fixture: W5BenchFixture,
    actions: ActionsList,
): SendResultList {
    val seqno = fixture.wallet.getSeqno();
    val body = createExternalSignedBody(
        fixture.keyPair,
        DEFAULT_SUBWALLET_ID,
        seqno,
        actions,
        W5_BENCH_VALID_UNTIL,
    );
    val msg = net.createExternalMessage(fixture.wallet.address, body);
    // Match the TypeScript gas logger: measure the wallet external-in tx, then deliver children separately.
    val cursor = TxCursor {
        id: ffi.startMessageIter(
            msg.messageCell,
            address("-1:0000000000000000000000000000000000000000000000000000000000000000").toCell(),
        ),
    };
    val res = cursor.executeN(1);
    cursor.close();
    expect(fixture.wallet.getSeqno()).toEqual(seqno + 1);
    return res;
}

fun sendW5BenchSignedInternal(
    fixture: W5BenchFixture,
    actions: ActionsList,
): SendResultList {
    val seqno = fixture.wallet.getSeqno();
    val body = createSignedBody(
        fixture.keyPair,
        DEFAULT_SUBWALLET_ID,
        seqno,
        actions,
        W5_BENCH_VALID_UNTIL,
    );
    val res = fixture
        .wallet
        .sendSignedBody(
            fixture.deployer.address,
            body,
            { value: W5_BENCH_SIGNED_INTERNAL_VALUE },
        );
    expect(fixture.wallet.getSeqno()).toEqual(seqno + 1);
    return res;
}

fun installW5BenchDeployerExtension(fixture: W5BenchFixture) {
    val res = sendW5BenchSignedInternal(
        fixture,
        w5BenchAddExtensionActions(fixture.deployer.address),
    );
    res.giveName("setup add deployer extension");

    expect(res.size()).toEqual(1);
    expect(res).toHaveSuccessfulTx({
        from: fixture.deployer.address,
        to: fixture.wallet.address,
        exitCode: 0,
    });
    expect(w5BenchExtensionExists(fixture.wallet, fixture.deployer.address)).toEqual(true);
}

get fun `test w5 bench: correctness of deploy`() {
    val fixture = deployW5BenchFixture();

    expect(fixture.wallet.getSeqno()).toEqual(0);
    expect(fixture.wallet.getPublicKey()).toEqual(fixture.keyPair.publicKey);
    expect(fixture.wallet.isSignatureAllowed()).toEqual(true);
    expect(fixture.wallet.getExtensions()).toBeEmpty();
}

get fun `test w5 bench: EXTERNAL transfer`() {
    val fixture = deployW5BenchFixture();
    val receiverBalanceBefore = testing.getAccountBalance(fixture.receiver.address);

    val res = sendW5BenchSignedExternal(
        fixture,
        w5BenchSendTxActions(fixture.receiver.address, W5_BENCH_TRANSFER_VALUE),
    );
    res.giveName("EXTERNAL transfer");

    expect(res.size()).toEqual(1);
    val outMessages = res.at(0).outMessages;
    expect(outMessages.size()).toEqual(1);

    val delivered = testing.processSingleTraceStep(
        fixture.wallet.address,
        OutMessage { messageCell: outMessages.atCell(0) },
    );
    val fee = delivered.tx.load().totalFees.grams;
    val receiverBalanceAfter = testing.getAccountBalance(fixture.receiver.address);
    expect(receiverBalanceAfter).toEqual(receiverBalanceBefore + W5_BENCH_TRANSFER_VALUE - fee);
}

get fun `test w5 bench: INTERNAL transfer`() {
    val fixture = deployW5BenchFixture();
    val receiverBalanceBefore = testing.getAccountBalance(fixture.receiver.address);

    val res = sendW5BenchSignedInternal(
        fixture,
        w5BenchSendTxActions(fixture.receiver.address, W5_BENCH_TRANSFER_VALUE),
    );
    res.giveName("INTERNAL transfer");

    expect(res.size()).toEqual(2);
    expect(res).toHaveSuccessfulTx({
        from: fixture.deployer.address,
        to: fixture.wallet.address,
        exitCode: 0,
    });
    expect(res).toHaveTx({
        from: fixture.wallet.address,
        to: fixture.receiver.address,
        value: W5_BENCH_TRANSFER_VALUE,
    });

    val fee = res.at(1).tx.load().totalFees.grams;
    val receiverBalanceAfter = testing.getAccountBalance(fixture.receiver.address);
    expect(receiverBalanceAfter).toEqual(receiverBalanceBefore + W5_BENCH_TRANSFER_VALUE - fee);
}

get fun `test w5 bench: ADD extension`() {
    val fixture = deployW5BenchFixture();

    val res = sendW5BenchSignedExternal(
        fixture,
        w5BenchAddExtensionActions(fixture.receiver.address),
    );
    res.giveName("ADD extension");

    expect(res.size()).toEqual(1);
    expect(res.at(0).outMessages.size()).toEqual(0);
    expect(fixture.wallet.getExtensions()).toHaveLength(1);
    expect(w5BenchExtensionExists(fixture.wallet, fixture.receiver.address)).toEqual(true);
}

get fun `test w5 bench: EXTENSION transfer`() {
    val fixture = deployW5BenchFixture();
    installW5BenchDeployerExtension(fixture);

    val receiverBalanceBefore = testing.getAccountBalance(fixture.receiver.address);
    val res = fixture
        .wallet
        .sendExtensionActionBody(
            fixture.deployer.address,
            w5BenchSendTxActions(fixture.receiver.address, W5_BENCH_EXTENSION_TRANSFER_VALUE),
            0,
            { value: W5_BENCH_EXTENSION_CALL_VALUE },
        );
    res.giveName("EXTENSION transfer");

    expect(res.size()).toEqual(2);
    expect(res).toHaveSuccessfulTx({
        from: fixture.deployer.address,
        to: fixture.wallet.address,
        exitCode: 0,
    });
    expect(res).toHaveTx({
        from: fixture.wallet.address,
        to: fixture.receiver.address,
        value: W5_BENCH_EXTENSION_TRANSFER_VALUE,
        exitCode: 0,
    });

    val fee = res.at(1).tx.load().totalFees.grams;
    val receiverBalanceAfter = testing.getAccountBalance(fixture.receiver.address);
    expect(receiverBalanceAfter).toEqual(
        receiverBalanceBefore + W5_BENCH_EXTENSION_TRANSFER_VALUE - fee,
    );
}
