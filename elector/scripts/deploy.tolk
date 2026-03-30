import "@acton/env"

import "@acton/io"
import "@acton/emulation/network"
import "./_helpers"
import "../tests/wrappers/Elector"

fun main() {
    val deployer = net.wallet("deployer-1");
    val target = Elector.fromStorage(defaultScriptStorage(), null, MASTERCHAIN);

    println1("Deploying elector from {}", deployer.address);
    println1("Target elector address: {}", target.address);
    println1("Deploy value: {}", electorDeployValue());

    if (envOr<int>("ELECTOR_ALLOW_DEPLOY", 0) == 0) {
        println("Blocker: elector masterchain deployment with deployer-1 is not supported by the current emulator path.");
        println("Set ELECTOR_ALLOW_DEPLOY=1 to attempt the send path in a different environment.");
        return;
    }

    val elector = prepareElectorScriptContract();
    printElectorSummary(elector);
}
