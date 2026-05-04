import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"

fun main() {
    val deployer = promptElectorWallet("ELECTOR_DEPLOYER", "Select Elector Deployer");
    val workchain = promptElectorWorkchain(
        "ELECTOR_WORKCHAIN",
        "Select target workchain (deployer's workchain must match)",
    );
    val deployValue = promptElectorCoins(
        "ELECTOR_DEPLOY_VALUE",
        "Enter deploy value (nanotons)",
        ELECTOR_DEFAULT_DEPLOY_AMOUNT,
    );

    val elector = deployElector(deployer, workchain, deployValue);

    printElectorInfo(elector, "ELECTOR");
}
