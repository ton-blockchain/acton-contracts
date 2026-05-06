import "@acton/env"
import "@acton/io"
import "@acton/emulation/scripts"
import "utils/common"

fun main() {
    val deployer = promptConfigWallet("CONFIG_DEPLOYER", "Select Config Deployer ActonWallet");

    val publicKey = env<int>("CONFIG_PUBLIC_KEY") ?? 0;
    val deployValue = promptConfigCoins(
        "CONFIG_DEPLOY_VALUE",
        "Enter deploy value",
        CONFIG_DEFAULT_DEPLOY_VALUE,
    );

    val storage = buildConfigStorage(publicKey);
    val contract = deployConfig(deployer, storage, deployValue);

    println("CONFIG DEPLOYER_ADDRESS={}", deployer.address);
    println("CONFIG STORAGE_PUBLIC_KEY={}", publicKey);
    printConfigInfo(contract, "CONFIG");
}
