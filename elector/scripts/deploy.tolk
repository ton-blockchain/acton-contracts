import "@acton/env"

import "@acton/io"
import "@acton/emulation/network"
import "./_helpers"
import "../tests/wrappers/Elector"

fun main() {
    val deployer = net.wallet("deployer");
    val target = Elector.fromStorage(defaultScriptStorage(), null, MASTERCHAIN);

    println1("Deploying elector from {}", deployer.address);
    println1("Target elector address: {}", target.address);
    println1("Deploy value: {}", electorDeployValue());

    if (!electorDeployAllowed()) {
        printElectorDeployBlocker();
        return;
    }

    val elector = prepareElectorScriptContract();
    if (elector == null) {
        return;
    }

    val preparedElector = elector!;
    printElectorSummary(preparedElector);
}
