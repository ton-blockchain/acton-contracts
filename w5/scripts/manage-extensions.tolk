import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"
import "../contracts/messages"
import "../tests/wrappers/WalletV5Contract"

fun main() {
    val deployer = net.wallet("deployer");
    val keyPair = w5KeyPair();
    val wallet = w5DeployWallet(deployer.address);
    val extension = envOr("W5_EXTENSION", deployer.address);
    val value = w5AdminValue();

    println1("Managing extensions for wallet: {}", wallet.address);
    println1("Extension address: {}", extension);

    var seqno = wallet.getSeqno();

    var addActions: array<ExtraAction> = [];
    addActions.push(AddExtensionExtraAction { addr: extension });
    var signedBody = w5BuildSignedActions(keyPair, seqno, addActions);
    var res = wallet.sendSignedBody(deployer.address, signedBody, { value });
    if (!res.wait()) {
        println("Failed to add extension");
        return;
    }
    println1("Extension added, seqno is now {}", wallet.getSeqno());

    var extensionActions: array<ExtraAction> = [];
    extensionActions.push(SetSignatureAllowedExtraAction { allowSignature: false });
    var extBody = ActionsList {
        outActions: [],
        extraActions: extensionActions,
    }.toCell();
    res = wallet.sendExtensionActionRequest(extension, extBody, 0, { value });
    if (!res.wait()) {
        println("Failed to disable signatures from extension");
        return;
    }
    println1("Signature mode disabled, allowed? {}", wallet.isSignatureAllowed());

    extensionActions = [];
    extensionActions.push(SetSignatureAllowedExtraAction { allowSignature: true });
    extBody = ActionsList {
        outActions: [],
        extraActions: extensionActions,
    }.toCell();
    res = wallet.sendExtensionActionRequest(extension, extBody, 1, { value });
    if (!res.wait()) {
        println("Failed to re-enable signatures from extension");
        return;
    }
    println1("Signature mode restored, allowed? {}", wallet.isSignatureAllowed());

    seqno = wallet.getSeqno();
    var removeActions: array<ExtraAction> = [];
    removeActions.push(RemoveExtensionExtraAction { addr: extension });
    signedBody = w5BuildSignedActions(keyPair, seqno, removeActions);
    res = wallet.sendSignedBody(deployer.address, signedBody, { value });
    if (!res.wait()) {
        println("Failed to remove extension");
        return;
    }

    println1("Extension removed, final seqno: {}", wallet.getSeqno());
    w5PrintInfo(wallet);
}
