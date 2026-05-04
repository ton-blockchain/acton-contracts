import "@acton/crypto"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "../contracts/messages"
import "../wrappers/WalletV5.gen"
import "../wrappers/utils"

const W5_E2E_KEY_SEED = 0x57550001
const W5_E2E_NOW = 1000
const W5_E2E_VALID_UNTIL = 2000
const W5_E2E_EXTENSION_QUERY_ID = 5501
const W5_E2E_RECOVERY_QUERY_ID = 5502

const W5_E2E_SIGNED_TRANSFER_VALUE = ton("0.003")
const W5_E2E_EXTENSION_TRANSFER_VALUE = ton("0.004")
const W5_E2E_RECOVERY_TRANSFER_VALUE = ton("0.005")
const W5_E2E_EXTENSION_CALL_VALUE = ton("0.1")
const W5_E2E_INTERNAL_SIGNED_VALUE = ton("0.1")

const W5_E2E_SIGNED_MARKER = 500001
const W5_E2E_EXTENSION_MARKER = 500002
const W5_E2E_RECOVERY_MARKER = 500003

struct W5E2eFixture {
    wallet: WalletV5
    deployer: Treasury
    keyPair: KeyPair
}

fun w5E2eKeyPair(): KeyPair {
    return crypto.seedToKeyPair(W5_E2E_KEY_SEED as uint256);
}

fun w5E2eMarkerBody(marker: int): cell {
    return beginCell().storeUint(marker, 32).endCell();
}

fun w5E2eSendMarkerAction(dest: address, value: coins, marker: int): SendAction {
    val transferMessage = createMessage({
        bounce: false,
        value,
        dest,
        body: w5E2eMarkerBody(marker),
    });
    return SendAction {
        mode: SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS,
        messageCell: transferMessage.messageCell,
    };
}

fun expectW5Extension(wallet: WalletV5, extension: address, exists: bool) {
    val extensions = wallet.getExtensions();
    val (_, extensionHash) = extension.getWorkchainAndHash();
    expect(extensions.exists(extensionHash)).toEqual(exists);
}

fun deployW5Stage(): W5E2eFixture {
    testing.setNow(W5_E2E_NOW);

    val keyPair = w5E2eKeyPair();
    val (wallet, deployer) = deployWalletWithKey(keyPair);

    expect(wallet.getPublicKey()).toEqual(keyPair.publicKey);
    expect(wallet.getSubwalletId()).toEqual(DEFAULT_SUBWALLET_ID);
    expect(wallet.getSeqno()).toEqual(0);
    expect(wallet.isSignatureAllowed()).toEqual(true);
    expect(wallet.getExtensions()).toBeEmpty();

    return W5E2eFixture { wallet, deployer, keyPair };
}

fun sendSignedExternalTransferStage(fixture: W5E2eFixture): int {
    val recipient = testing.treasury("w5-e2e-signed-recipient");
    val seqno = fixture.wallet.getSeqno();

    var outActions: array<SendAction> = [];
    outActions.push(
        w5E2eSendMarkerAction(
            recipient.address,
            W5_E2E_SIGNED_TRANSFER_VALUE,
            W5_E2E_SIGNED_MARKER,
        ),
    );

    val body = createExternalSignedBody(
        fixture.keyPair,
        DEFAULT_SUBWALLET_ID,
        seqno,
        ActionsList {
            outActions,
            extraActions: [],
        },
        W5_E2E_VALID_UNTIL,
    );
    val res = fixture.wallet.sendExternalSigned(body)!;

    expect(res).toHaveTx({
        from: fixture.wallet.address,
        to: recipient.address,
        value: W5_E2E_SIGNED_TRANSFER_VALUE,
        body: w5E2eMarkerBody(W5_E2E_SIGNED_MARKER),
    });
    expect(fixture.wallet.getSeqno()).toEqual(seqno + 1);

    return seqno + 1;
}

fun installPrimaryExtensionStage(fixture: W5E2eFixture): int {
    val seqno = fixture.wallet.getSeqno();

    var extraActions: array<ExtraAction> = [];
    extraActions.push(AddExtensionExtraAction { addr: fixture.deployer.address });

    val body = createExternalSignedBody(
        fixture.keyPair,
        DEFAULT_SUBWALLET_ID,
        seqno,
        ActionsList {
            outActions: [],
            extraActions,
        },
        W5_E2E_VALID_UNTIL,
    );
    val res = fixture.wallet.sendExternalSigned(body)!;

    expect(res.size()).toEqual(1);
    expect(res).toHaveTx({ exitCode: 0 });
    expect(fixture.wallet.getSeqno()).toEqual(seqno + 1);
    expect(fixture.wallet.getExtensions()).toHaveLength(1);
    expectW5Extension(fixture.wallet, fixture.deployer.address, true);

    return seqno + 1;
}

fun sendExtensionTransferAndAddExtensionStage(fixture: W5E2eFixture) {
    val seqnoBefore = fixture.wallet.getSeqno();
    val recipient = testing.treasury("w5-e2e-extension-recipient");
    val secondaryExtension = testing.treasury("w5-e2e-secondary-extension");

    var outActions: array<SendAction> = [];
    outActions.push(
        w5E2eSendMarkerAction(
            recipient.address,
            W5_E2E_EXTENSION_TRANSFER_VALUE,
            W5_E2E_EXTENSION_MARKER,
        ),
    );

    var extraActions: array<ExtraAction> = [];
    extraActions.push(AddExtensionExtraAction { addr: secondaryExtension.address });

    val res = fixture
        .wallet
        .sendExtensionActionBody(
            fixture.deployer.address,
            ActionsList { outActions, extraActions },
            W5_E2E_EXTENSION_QUERY_ID,
            { value: W5_E2E_EXTENSION_CALL_VALUE },
        );

    expect(res.size()).toEqual(2);
    expect(res).toHaveSuccessfulTx({
        from: fixture.deployer.address,
        to: fixture.wallet.address,
    });
    expect(res).toHaveTx({
        from: fixture.wallet.address,
        to: recipient.address,
        value: W5_E2E_EXTENSION_TRANSFER_VALUE,
        body: w5E2eMarkerBody(W5_E2E_EXTENSION_MARKER),
    });
    expect(fixture.wallet.getSeqno()).toEqual(seqnoBefore);
    expect(fixture.wallet.getExtensions()).toHaveLength(2);
    expectW5Extension(fixture.wallet, fixture.deployer.address, true);
    expectW5Extension(fixture.wallet, secondaryExtension.address, true);
}

fun disableSignatureFromExtensionStage(fixture: W5E2eFixture) {
    val seqnoBefore = fixture.wallet.getSeqno();

    var extraActions: array<ExtraAction> = [];
    extraActions.push(SetSignatureAllowedExtraAction { allowSignature: false });

    val res = fixture
        .wallet
        .sendExtensionActionBody(
            fixture.deployer.address,
            ActionsList {
                outActions: [],
                extraActions,
            },
            W5_E2E_RECOVERY_QUERY_ID,
            { value: W5_E2E_EXTENSION_CALL_VALUE },
        );

    expect(res.size()).toEqual(1);
    expect(res).toHaveSuccessfulTx({
        from: fixture.deployer.address,
        to: fixture.wallet.address,
    });
    expect(fixture.wallet.isSignatureAllowed()).toEqual(false);
    expect(fixture.wallet.getSeqno()).toEqual(seqnoBefore);
}

fun recoverSignatureAndRemovePrimaryExtensionStage(fixture: W5E2eFixture) {
    val seqnoBefore = fixture.wallet.getSeqno();
    val secondaryExtension = testing.treasury("w5-e2e-secondary-extension");

    var extraActions: array<ExtraAction> = [];
    extraActions.push(SetSignatureAllowedExtraAction { allowSignature: true });
    extraActions.push(RemoveExtensionExtraAction { addr: fixture.deployer.address });

    val res = fixture
        .wallet
        .sendExtensionActionBody(
            fixture.deployer.address,
            ActionsList {
                outActions: [],
                extraActions,
            },
            W5_E2E_RECOVERY_QUERY_ID + 1,
            { value: W5_E2E_EXTENSION_CALL_VALUE },
        );

    expect(res.size()).toEqual(1);
    expect(res).toHaveSuccessfulTx({
        from: fixture.deployer.address,
        to: fixture.wallet.address,
    });
    expect(fixture.wallet.isSignatureAllowed()).toEqual(true);
    expect(fixture.wallet.getSeqno()).toEqual(seqnoBefore);
    expect(fixture.wallet.getExtensions()).toHaveLength(1);
    expectW5Extension(fixture.wallet, fixture.deployer.address, false);
    expectW5Extension(fixture.wallet, secondaryExtension.address, true);
}

fun sendRecoveredInternalSignedTransferStage(fixture: W5E2eFixture): int {
    val seqno = fixture.wallet.getSeqno();
    val recipient = testing.treasury("w5-e2e-recovered-recipient");

    var outActions: array<SendAction> = [];
    outActions.push(
        w5E2eSendMarkerAction(
            recipient.address,
            W5_E2E_RECOVERY_TRANSFER_VALUE,
            W5_E2E_RECOVERY_MARKER,
        ),
    );

    val body = createSignedBody(
        fixture.keyPair,
        DEFAULT_SUBWALLET_ID,
        seqno,
        ActionsList {
            outActions,
            extraActions: [],
        },
        W5_E2E_VALID_UNTIL,
    );
    val res = fixture
        .wallet
        .sendSignedBody(
            fixture.deployer.address,
            body,
            { value: W5_E2E_INTERNAL_SIGNED_VALUE },
        );

    expect(res).toHaveSuccessfulTx({
        from: fixture.deployer.address,
        to: fixture.wallet.address,
    });
    expect(res).toHaveTx({
        from: fixture.wallet.address,
        to: recipient.address,
        value: W5_E2E_RECOVERY_TRANSFER_VALUE,
        body: w5E2eMarkerBody(W5_E2E_RECOVERY_MARKER),
    });
    expect(fixture.wallet.getSeqno()).toEqual(seqno + 1);

    return seqno + 1;
}

get fun `test w5 e2e bench: stage 1 deploy wallet`() {
    deployW5Stage();
}

get fun `test w5 e2e bench: stage 2 send signed external transfer`() {
    val fixture = deployW5Stage();
    sendSignedExternalTransferStage(fixture);
}

get fun `test w5 e2e bench: stage 3 install primary extension`() {
    val fixture = deployW5Stage();
    sendSignedExternalTransferStage(fixture);
    installPrimaryExtensionStage(fixture);
}

get fun `test w5 e2e bench: stage 4 extension transfer and add extension`() {
    val fixture = deployW5Stage();
    sendSignedExternalTransferStage(fixture);
    installPrimaryExtensionStage(fixture);
    sendExtensionTransferAndAddExtensionStage(fixture);
}

get fun `test w5 e2e bench: stage 5 full flow with signature recovery`() {
    val fixture = deployW5Stage();
    sendSignedExternalTransferStage(fixture);
    installPrimaryExtensionStage(fixture);
    sendExtensionTransferAndAddExtensionStage(fixture);
    disableSignatureFromExtensionStage(fixture);
    recoverSignatureAndRemovePrimaryExtensionStage(fixture);
    sendRecoveredInternalSignedTransferStage(fixture);
}
