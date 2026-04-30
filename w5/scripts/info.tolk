import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"

fun main() {
    val keyPair = promptW5KeyPair();
    val subwalletId = promptW5SubwalletId();
    printW5Info(resolveW5Wallet(keyPair, subwalletId), "W5");
}
