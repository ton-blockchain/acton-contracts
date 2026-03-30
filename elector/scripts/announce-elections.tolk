import "@acton/io"

import "@acton/emulation/network"
import "./_helpers"

fun main() {
    if (!electorDeployAllowed()) {
        printElectorDeployBlocker();
        return;
    }

    val elector = prepareElectorScriptContract();
    if (elector == null) {
        return;
    }
    val preparedElector = elector!;

    println("Running elector tick-tock to announce elections");
    net.runTickTock(preparedElector.address, true);

    printElectorSummary(preparedElector);
}
