import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../contracts/messages"
import "../wrappers/WalletV5Contract"

fun main() {
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
            "false disables external signed flow until restored by an extension",
        );

    val seqno = wallet.getSeqno();
    val actions = ActionsList {
        outActions: [],
        extraActions: [SetSignatureAllowedExtraAction { allowSignature: target } as ExtraAction],
    };
    val body = createExternalSignedBody(keyPair, subwalletId, seqno, actions);

    val res = wallet.sendExternalSigned(body);
    if (res == null) {
        println("Set-signature external could not be submitted");
        return;
    }
    if (res.waitForFirstTransaction() == null) {
        println("Set-signature was not confirmed");
        return;
    }

    println("W5 SIGNATURE_ALLOWED_TARGET={}", target);
    if (net.isBroadcasting()) {
        println("Signature change broadcast — re-run info to inspect updated state.");
        return;
    }
    printW5Info(wallet, "W5");
}
