import "@acton/env"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"

fun main() {
    val elector = promptElector("ELECTOR_ADDRESS", "Enter Elector address");
    printElectorInfo(elector, "ELECTOR");

    val ownerEnv = env<address>("ELECTOR_OWNER_ADDRESS");
    if (ownerEnv != null) {
        val (_, ownerHash) = ownerEnv.getWorkchainAndHash();
        printRecoverableStake(elector, ownerHash, "ELECTOR_OWNER");
        return;
    }

    if (
        !confirm(
            "Show recoverable stake for an address?",
            false,
            "Calls compute_returned_stake for the given owner",
        )
    ) {
        return;
    }
    val owner = promptElectorAddressRequired("ELECTOR_OWNER_ADDRESS", "Enter owner address");
    val (_, ownerHash) = owner.getWorkchainAndHash();
    printRecoverableStake(elector, ownerHash, "ELECTOR_OWNER");
}
