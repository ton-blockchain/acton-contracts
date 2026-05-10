import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../contracts/messages"
import "../wrappers/WalletV5.gen"
import "../wrappers/utils"

fun main() {
    val extensionSender = promptW5Wallet(
        "W5_EXTENSION_SENDER",
        "Select ActonWallet that is registered as an extension on the W5 wallet",
    );
    val keyPair = promptW5KeyPair();
    val subwalletId = promptW5SubwalletId();
    val wallet = resolveW5Wallet(keyPair, subwalletId);

    if (!scripts.isContractDeployed(wallet.address)) {
        println("W5 wallet at {} is not deployed yet — run deploy.tolk first.", wallet.address);
        return;
    }

    val current = wallet.isSignatureAllowed();
    println("Current signature_allowed: {}", current);
    val targetFromEnv = env<bool>("W5_SIGNATURE_ALLOWED");
    val target = targetFromEnv != null
        ? targetFromEnv!
        : confirm(
            "Allow signature?",
            !current,
            "false disables external signed flow until only extensions can act",
        );

    val extensions = wallet.getExtensionsArray();
    var extensionRegistered = false;
    var i = 0;
    while (i < extensions.size()) {
        if (extensions.get(i) == extensionSender.address) {
            extensionRegistered = true;
        }
        i += 1;
    }
    if (!extensionRegistered) {
        println(
            "Sender {} is not registered as an extension on W5 {}. SetSignatureAllowedExtraAction requires an extension-authenticated request — run add-extension.tolk first.",
            extensionSender.address,
            wallet.address,
        );
        return;
    }

    val actionsBody = ActionsList {
        outActions: [],
        extraActions: [SetSignatureAllowedExtraAction { allowSignature: target } as ExtraAction],
    };
    val res = wallet.sendExtensionActionBody(
        extensionSender.address,
        actionsBody,
        0,
        { value: ton("0.03") },
    );
    if (res.waitForFirstTransaction() == null) {
        println("Set-signature extension request was not confirmed");
        return;
    }

    println("W5 SIGNATURE_ALLOWED_TARGET={}", target);
    if (net.isBroadcasting()) {
        println("Signature change broadcast — re-run info to inspect updated state.");
        return;
    }
    printW5Info(wallet, "W5");
}
