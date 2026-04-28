import "@acton/build"
import "@acton/crypto"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../contracts/c5-register-validation"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/WalletV5.gen"
import "../wrappers/utils"

const W5_DEFAULT_SEED = 0x2222222222222222222222222222222222222222222222222222222222222222
const W5_DEFAULT_SUBWALLET_ID = 0
const W5_DEFAULT_DEPLOY_VALUE = ton("0.05")
const W5_DEFAULT_ACTION_VALUE = ton("0.01")
const W5_DEFAULT_ADMIN_VALUE = ton("0.03")
const W5_DEFAULT_QUERY_ID = 0

fun w5Seed(): int {
    return env<int>("W5_SEED") ?? W5_DEFAULT_SEED;
}

fun w5KeyPair(): KeyPair {
    return crypto.seedToKeyPair(w5Seed());
}

fun w5SubwalletId(): int {
    return env<int>("W5_SUBWALLET_ID") ?? W5_DEFAULT_SUBWALLET_ID;
}

fun w5DeployValue(): int {
    return env<int>("W5_DEPLOY_VALUE") ?? W5_DEFAULT_DEPLOY_VALUE;
}

fun w5ActionValue(): int {
    return env<int>("W5_ACTION_VALUE") ?? W5_DEFAULT_ACTION_VALUE;
}

fun w5AdminValue(): int {
    return env<int>("W5_ADMIN_VALUE") ?? W5_DEFAULT_ADMIN_VALUE;
}

fun w5WalletAddress(): address? {
    return env("W5_WALLET_ADDRESS");
}

fun w5BuildWallet(): WalletV5 {
    val keyPair = w5KeyPair();
    val explicitAddress = w5WalletAddress();

    if (explicitAddress != null) {
        return WalletV5 { address: explicitAddress! };
    }

    return WalletV5.fromLibraryStorage(Storage {
        isSignatureAllowed: true,
        seqno: 0,
        subwalletId: w5SubwalletId(),
        publicKey: keyPair.publicKey,
        extensions: [],
    });
}

fun w5DeployWallet(deployer: address): WalletV5 {
    val wallet = w5BuildWallet();
    if (wallet.stateInit != null) {
        val res = wallet.deploy(deployer, { value: w5DeployValue(), bounce: false });
        res.waitForFirstTransaction();
    }
    return wallet;
}

fun w5SendAction(
    dest: address,
    value: coins,
    body: cell? = null,
    mode: int = SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS,
): SendAction {
    var actionBody = body;
    if (actionBody == null) {
        actionBody = createEmptyCell();
    }
    return SendAction {
        mode,
        messageCell: createMessage({
            bounce: false,
            value,
            dest,
            body: actionBody!,
        }).messageCell,
    };
}

fun w5BuildSignedActions(
    keyPair: KeyPair,
    seqno: int,
    extraActions: array<ExtraAction>,
    outActions: array<SendAction> = [],
): SignedBody {
    val actions = ActionsList { outActions, extraActions };
    return createSignedBody(keyPair, w5SubwalletId(), seqno, actions);
}

fun w5PrintInfo(wallet: WalletV5) {
    val extensions = wallet.getExtensionsArray();
    println("Wallet v5 address: {}", wallet.address);
    println("Seqno: {}", wallet.getSeqno());
    println("Public key: {}", wallet.getPublicKey());
    println("Subwallet id: {}", wallet.getSubwalletId());
    println("Signature allowed: {}", wallet.isSignatureAllowed());
    println("Extensions count: {}", extensions.size());

    var i = 0;
    while (i < extensions.size()) {
        println("Extension[{}]: {}", i, extensions.get(i));
        i += 1;
    }
}
