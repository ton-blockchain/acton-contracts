import "@acton/emulation/network"
import "@acton/promts/prompts"
import "utils/common"

fun main() {
    val deployer = promptW5Wallet("W5_DEPLOYER", "Select Deployer Wallet");
    val deployValue = promptW5Coins(
        "W5_DEPLOY_VALUE",
        "Enter deploy value",
        W5_DEFAULT_DEPLOY_VALUE,
    );

    val wallet = w5FromSeed();
    deployW5IfNeeded(deployer, wallet, deployValue);

    printW5Info(wallet, "W5");
}
