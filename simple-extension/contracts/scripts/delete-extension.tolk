import "@acton/io"
import "@acton/emulation/network"
import "common"
import "../vendor/w5/contracts/messages"
import "../vendor/w5/wrappers/WalletV5Contract"

const ERROR_EXTENSION_DELETE_VERIFICATION_FAILED = 7012
const ERROR_EXTENSION_DELETE_WAIT_FAILED = 7013

fun main() {
    if (!net.isBroadcasting()) {
        println(
            "delete-extension.tolk requires `--net` because wallet keys and wallet_id are only available for configured wallets opened with net.wallet()",
        );
        return;
    }

    val deployer = net.wallet(extensionWalletName());
    val wallet = deployerWalletV5(deployer);
    val extension = buildExtensionForDeployer(deployer);

    println("Deployer wallet: {}", deployer.address);
    println("Extension address: {}", extension.address);

    if (!walletHasExtension(wallet, extension.address)) {
        println("Extension is not installed");
        printWalletExtensions(wallet);
        return;
    }

    val seqno = wallet.getSeqno();
    var extraActions: array<ExtraAction> = [];
    extraActions.push(RemoveExtensionExtraAction { addr: extension.address });

    val body = buildSignedExtensionActions(deployer, seqno, extraActions);
    val msg = createExternalMessage(wallet.address, body);
    val res = net.sendExternal(msg);
    if (res == null) {
        println("Delete message was not accepted by the network");
        return;
    }
    assert (waitForExternalMessage(wallet.address, msg, true)) throw ERROR_EXTENSION_DELETE_WAIT_FAILED;

    assert (
        !walletHasExtension(wallet, extension.address)
    ) throw ERROR_EXTENSION_DELETE_VERIFICATION_FAILED;

    println("Extension removed successfully");
    printWalletExtensions(wallet);
}
