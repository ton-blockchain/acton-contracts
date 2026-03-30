import "@acton/io"

import "@acton/emulation/network"
import "./_helpers"

fun main() {
    val deployer = net.wallet("deployer");
    val contract = prepareConfigScriptContract();
    contract.deploy(deployer.address, { value: configDeployValue(), bounce: false }).wait();

    printConfigSummary(contract);
}
