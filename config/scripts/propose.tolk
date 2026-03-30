import "@acton/io"

import "@acton/emulation/config"
import "@acton/emulation/network"
import "./_helpers"

fun main() {
    val deployer = net.wallet("deployer");
    val contract = prepareConfigScriptContract();
    contract.deploy(deployer.address, { value: configDeployValue(), bounce: false }).wait();

    val proposal = buildScriptProposal();
    println1("Submitting proposal for param id {}", configProposalParamId());
    println1("Proposer address: {}", deployer.address);
    println1("Target config address: {}", contract.address);
    println1("Proposal value payload: {}", configProposalText());
    println1("Proposal value coins: {}", configProposalValue());

    if (deployer.address.getWorkchain() != MASTERCHAIN) {
        println("Blocker: config proposal submission requires a masterchain sender.");
        println("deployer is not masterchain in this workspace, so this path is intentionally not sent.");
        return;
    }

    val res = contract.sendNewVotingProposalRequest(
        deployer.address,
        1,
        (net.now() + 86400) as uint32,
        false,
        proposal,
        { value: configProposalValue(), bounce: true },
    );
    res.wait();

    val hash = proposal.toCell().hash();
    println1("Created proposal hash: {}", hash);
    println1("Proposal exists: {}", contract.getProposal(hash as int) != null);
    printConfigSummary(contract);
}
