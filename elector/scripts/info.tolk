import "@acton/io"

import "@acton/emulation/network"
import "./_helpers"

fun main() {
    val elector = prepareElectorScriptContract();
    printElectorSummary(elector);
}
