import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/types/message"
import "@contracts/types"
import "@wrappers/SimpleExtension"
import "../vendor/w5/contracts/messages"
import "../vendor/w5/wrappers/WalletV5Contract"

const DEFAULT_EXTENSION_WALLET_NAME = "deployer-2"
const DEFAULT_EXTENSION_DEPLOY_VALUE = ton("0.5")
const DEFAULT_EXTENSION_SUBSCRIPTION_AMOUNT = ton("0.25")
const DEFAULT_EXTENSION_PAYMENT_INTERVAL = 3600

fun extensionWalletName(): string {
    return envOr("SIMPLE_EXTENSION_WALLET", DEFAULT_EXTENSION_WALLET_NAME);
}

fun extensionDeployValue(): coins {
    return envOr("SIMPLE_EXTENSION_DEPLOY_VALUE", DEFAULT_EXTENSION_DEPLOY_VALUE);
}

fun extensionSubscriptionAmount(): coins {
    return envOr(
        "SIMPLE_EXTENSION_SUBSCRIPTION_AMOUNT",
        DEFAULT_EXTENSION_SUBSCRIPTION_AMOUNT,
    );
}

fun extensionPaymentInterval(): int {
    return envOr("SIMPLE_EXTENSION_PAYMENT_INTERVAL", DEFAULT_EXTENSION_PAYMENT_INTERVAL);
}

fun extensionAddressOverride(): address? {
    return env("SIMPLE_EXTENSION_ADDRESS");
}

fun extensionAdminValue(): coins {
    return envOr("SIMPLE_EXTENSION_ADMIN_VALUE", ton("0.05"));
}

fun buildExtensionForDeployer(deployer: Wallet): SimpleExtension {
    val explicitAddress = extensionAddressOverride();
    if (explicitAddress != null) {
        return SimpleExtension.fromAddress(explicitAddress!);
    }

    return SimpleExtension.fromStorage(ExtensionStorage {
        walletAddress: deployer.address,
        admin: deployer.address,
        subscriptionAmount: extensionSubscriptionAmount(),
        lastPaymentTime: null,
        paymentTimeInterval: extensionPaymentInterval(),
    });
}

fun deployerWalletV5(deployer: Wallet): WalletV5Contract {
    return WalletV5Contract { address: deployer.address };
}

fun walletHasExtension(wallet: WalletV5Contract, extensionAddress: address): bool {
    val extensions = wallet.getExtensions();
    val (_, extensionHash) = extensionAddress.getWorkchainAndHash();
    return extensions.exists(extensionHash);
}

fun printWalletExtensions(wallet: WalletV5Contract) {
    val extensions = wallet.getExtensionsArray();
    println("Wallet v5 address: {}", wallet.address);
    println("Seqno: {}", wallet.getSeqno());
    println("Extensions count: {}", extensions.size());

    var i = 0;
    while (i < extensions.size()) {
        println("Extension[{}]: {}", i, extensions.get(i));
        i += 1;
    }
}

fun buildSignedExtensionActions(wallet: Wallet, seqno: int, extraActions: array<ExtraAction>) {
    val actions = ActionsList {
        outActions: [],
        extraActions,
    };
    return createExternalSignedBody(wallet.toKeyPair(), wallet.walletId(), seqno, actions);
}

fun externalMessageBodyHash(msg: OutMessage): slice {
    val extMsg = (msg.messageCell as Cell<ExtMessageRelaxedGeneric>).load();
    var body = extMsg.body;
    body.skipBits(1); // skip Either tag bit
    return beginCell().storeUint(body.hash(), 256).toSlice();
}

fun waitForExternalMessage(
    dest: address,
    msg: OutMessage,
    quiet: bool = false,
    attempts: int = 20,
    sleepDuration: int = 1000,
): bool {
    return net.waitForTransaction(
        dest,
        externalMessageBodyHash(msg),
        quiet,
        attempts,
        sleepDuration,
    );
}
