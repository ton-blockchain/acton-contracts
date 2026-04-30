import "@acton/io"
import "@acton/prompts"
import "@acton/types/big_array"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@acton/emulation/testing"
import "utils/common"

// The elector's onRunTickTock cannot be triggered by an external message; only
// the validator-block tick-tock pipeline calls it. So announcing elections via
// this script makes sense only against the local emulator (no `--net`) or a
// forked network state — typically with the elector already pre-configured.
fun main() {
    if (net.isBroadcasting()) {
        println("ELECTOR ANNOUNCE_STATUS=skipped");
        println("ELECTOR REASON=tick-tock cannot be triggered by external messages on a broadcast network");
        return;
    }

    val elector = promptElector("ELECTOR_ADDRESS", "Enter Elector address");
    if (!scripts.isContractDeployed(elector.address)) {
        println("ELECTOR ANNOUNCE_STATUS=skipped");
        println("ELECTOR REASON=elector is not deployed at this address");
        return;
    }

    println("ELECTOR ANNOUNCE_STATUS=running tock");
    val res = testing.runTickTock(elector.address, true);
    println("ELECTOR ANNOUNCE_TX_COUNT={}", res.size());

    printElectorInfo(elector, "ELECTOR");
}
