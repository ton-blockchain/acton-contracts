import "@stdlib/gas-payments"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@acton/types/message"
import "../../contracts/messages"
import "../../contracts/storage"

struct ConfigContract {
    address: address
    stateInit: ContractState? = null
}

fun ConfigContract.fromStorage(storage: Storage, toShard: AddressShardingOptions? = null) {
    val stateInit = ContractState {
        code: build("config"),
        data: storage.toCell(),
    };
    val cAddress = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return ConfigContract {
        address: cAddress,
        stateInit,
    };
}

fun ConfigContract.fromAddress(address: address) {
    return ConfigContract { address };
}

fun ConfigContract.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy a contract created with fromAddress");
    }
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit! },
    });
    return net.send(from, msg);
}

fun ConfigContract.sendSetNextValidatorSetRequest(
    self,
    from: address,
    queryId: uint64,
    vset: cell,
    config: SendParams = {},
): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: SetNextValidatorSetRequest { queryId, vset },
    });
    return net.send(from, msg);
}

fun ConfigContract.sendSetCustomParamRequest(
    self,
    from: address,
    queryId: uint64,
    paramId: int32,
    receiverAddress: address,
    value: cell,
    config: SendParams = {},
): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: SetCustomParamRequest { queryId, paramId, receiverAddress, value },
    });
    return net.send(from, msg);
}

fun ConfigContract.sendNewVotingProposalRequest(
    self,
    from: address,
    queryId: uint64,
    expireAt: uint32,
    critical: bool,
    proposal: ConfigProposal,
    config: SendParams = {},
): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: NewVotingProposalRequest {
            queryId,
            expireAt,
            critical,
            proposal: proposal.toCell(),
        },
    });
    return net.send(from, msg);
}

fun ConfigContract.sendVoteForProposalRequest(
    self,
    from: address,
    queryId: uint64,
    signature: bits512,
    signedVoteBody: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: VoteForProposalRequest { queryId, signature, signedVoteBody },
    });
    return net.send(from, msg);
}

fun ConfigContract.sendAny(
    self,
    from: address,
    body: cell,
    config: SendParams = {},
): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, msg);
}

fun ConfigContract.seqno(self): int {
    return net.runGetMethod(self.address, "seqno");
}

fun ConfigContract.get_proposal(self, proposalHash: int): tuple? {
    return net.runGetMethod(self.address, "get_proposal", proposalHash);
}

fun ConfigContract.list_proposals(self): lisp_list<tuple> {
    return net.runGetMethod(self.address, "list_proposals");
}

fun ConfigContract.proposal_storage_price(
    self,
    critical: int,
    seconds: int,
    bits: int,
    refs: int,
): int {
    return net.runGetMethod(
        self.address,
        "proposal_storage_price",
        [critical, seconds, bits, refs] as tuple,
    );
}
