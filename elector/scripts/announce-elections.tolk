import "@acton/io"

import "@acton/emulation/network"
import "./_helpers"

fun main() {
    val elector = prepareElectorScriptContract();

    println("Running elector tick-tock to announce elections");
    net.runTickTock(elector.address, true);

    printElectorSummary(elector);
}
