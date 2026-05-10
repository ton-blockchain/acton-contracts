import "utils/common"

fun main() {
    val deployer = promptW5Wallet("W5_DEPLOYER", "Select W5 Deployer ActonWallet");
    val keyPair = promptW5KeyPair();
    val subwalletId = promptW5SubwalletId();
    val value = promptW5Coins("W5_DEPLOY_VALUE", "Enter deploy value", W5_DEFAULT_DEPLOY_VALUE);

    val wallet = deployW5Wallet(deployer, keyPair, subwalletId, value);

    printW5Info(wallet, "W5");
}
