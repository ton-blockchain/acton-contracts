import "@acton/io"

import "@acton/build/build"
import "@acton/emulation/network"
import "./_helpers"

fun main() {
    val deployer = net.wallet("deployer-1");
    val contract = prepareConfigScriptContract();

    println1("Deploying config contract from {}", deployer.address);
    println1("Deploy value: {}", configDeployValue());
    contract.deploy(deployer.address, { value: configDeployValue(), bounce: false }).wait();

    printConfigSummary(contract);
}
