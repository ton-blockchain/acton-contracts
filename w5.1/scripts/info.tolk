import "utils/common"

fun main() {
    val keyPair = promptW5KeyPair();
    val subwalletId = promptW5SubwalletId();
    printW5Info(resolveW5Wallet(keyPair, subwalletId), "W5");
}
