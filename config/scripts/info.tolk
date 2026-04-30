import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/Config.gen"

fun main() {
    val contract = promptConfigContract("Enter Config contract address");
    printConfigInfo(contract, "CONFIG");

    if (!scripts.isContractDeployed(contract.address)) {
        return;
    }

    val proposalHashEnv = env<int>("CONFIG_PROPOSAL_HASH");
    if (proposalHashEnv != null) {
        val raw = contract.getProposal(proposalHashEnv);
        if (raw == null) {
            println("CONFIG PROPOSAL_HASH={} -> <not found>", proposalHashEnv);
        } else {
            printProposalTuple("CONFIG", proposalHashEnv, raw!);
        }
        return;
    }

    if (!confirm("List all proposals?", true, "Walks the storage proposal dict")) {
        return;
    }
    printAllProposals(contract, "CONFIG");
}
