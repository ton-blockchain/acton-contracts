import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/types/message"
import "../../contracts/messages"
import "../../contracts/types"
import "../../contracts/utils"

struct Elector {
    address: address
    stateInit: ContractState? = null
}

/// Creates a contract wrapper instance from the storage data
fun Elector.fromStorage(storage: Storage, toShard: AddressShardingOptions? = null) {
    val stateInit = ContractState {
        code: build("elector"),
        data: storage.toCell(),
    };
    val address = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return Elector { address, stateInit };
}

/// Creates a contract wrapper instance from the address
fun Elector.fromAddress(address: address) {
    return Elector { address };
}

/// Deploys the contract to the blockchain
fun Elector.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment");
    }
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendSimpleTransfer(self, from: address, config: SendParams = {}): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: SimpleTransfer {},
    });
    return net.send(from, genericMsg);
}

fun Elector.sendNewStakeMessage(
    self,
    from: address,
    queryId: uint64,
    validatorPubkey: uint256,
    stakeAt: uint32,
    maxFactor: uint32,
    adnlAddr: uint256,
    signature: bits512,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: NewStakeMessage {
            queryId,
            validatorPubkey,
            stakeAt,
            maxFactor,
            adnlAddr,
            signature: signature.toCell(),
        },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendRecoverStakeRequest(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: RecoverStakeRequest { queryId },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendUpgradeCode(
    self,
    from: address,
    queryId: uint64,
    newCode: cell,
    remaining: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: UpgradeCode { queryId, newCode, remaining },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendConfigConfirmed(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ConfigConfirmed { queryId },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendConfigConfirmedAlt(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ConfigConfirmedAlt { queryId },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendNewComplaint(
    self,
    from: address,
    queryId: uint64,
    electionId: uint32,
    rawComplaint: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: NewComplaint { queryId, electionId, rawComplaint },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendSignedVoteForComplaint(
    self,
    from: address,
    queryId: uint64,
    signature: bits512,
    vote: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: SignedVoteForComplaint { queryId, signature, vote },
    });
    return net.send(from, genericMsg);
}

fun Elector.sendFallbackMessage(
    self,
    from: address,
    opcodeBits: uint31,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: FallbackMessage { opcodeBits, queryId },
    });
    return net.send(from, genericMsg);
}

/// Send message to the contract with a custom body cell
fun Elector.sendAny(self, from: address, body: cell, config: SendParams = {}): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, genericMsg);
}

fun Elector.participates_in(self, validatorPubkey: uint256): int {
    return net.runGetMethod(self.address, "participates_in", validatorPubkey);
}

fun Elector.participant_list(self): lisp_list<array<int>> {
    return net.runGetMethod(self.address, "participant_list");
}

fun Elector.participant_list_extended(self): (
    int,
    int,
    coins,
    coins,
    lisp_list<ParticipantExtEntry>,
    bool,
    bool,
) {
    return net.runGetMethod(self.address, "participant_list_extended");
}

fun Elector.compute_returned_stake(self, walletAddr: uint256): int {
    return net.runGetMethod(self.address, "compute_returned_stake", walletAddr);
}

fun Elector.past_election_ids(self): lisp_list<int> {
    return net.runGetMethod(self.address, "past_election_ids");
}

fun Elector.past_elections(self): lisp_list<PastElectionFullEntry> {
    return net.runGetMethod(self.address, "past_elections");
}

fun Elector.past_elections_list(self): lisp_list<array<int>> {
    return net.runGetMethod(self.address, "past_elections_list");
}

fun Elector.get_past_complaints(self, electionId: uint32): Complaints {
    return net.runGetMethod(self.address, "get_past_complaints", electionId);
}

fun Elector.show_complaint(self, electionId: uint32, chash: uint256): ComplaintFullInfo? {
    return net.runGetMethod(self.address, "show_complaint", [electionId, chash] as tuple);
}

fun Elector.list_complaints(self, electionId: uint32): lisp_list<ComplaintListEntry> {
    return net.runGetMethod(self.address, "list_complaints", electionId);
}

fun Elector.complaint_storage_price(self, bits: int, refs: int, expireIn: int): int {
    return net.runGetMethod(
        self.address,
        "complaint_storage_price",
        [bits, refs, expireIn] as tuple,
    );
}
