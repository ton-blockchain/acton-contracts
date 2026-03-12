import "@acton/crypto/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/types"
import "../contracts/messages"

/// Set up config param 34 with known validators (with ADNL addresses)
/// Returns array of KeyPairs used for the validators.
fun setupVsetWithKnownValidators(numValidators: int): array<KeyPair> {
    var kps: array<KeyPair> = [];
    var dict: map<uint16, AnyValidatorDescr> = [];
    var totalWeight: uint64 = 0;
    var i = 0;
    while (i < numValidators) {
        val kp = crypto.generateKeyPair();
        kps.push(kp);
        val weight: uint64 = 100;
        dict.set(i, ValidatorDescrWithAdnlAddr {
            validatorPubkey: kp.publicKey as uint256,
            validatorWeight: weight,
            adnlAddr: 0,
        });
        totalWeight += weight;
        i += 1;
    }
    val vset = VSet {
        utimeSince: (blockchain.now() - 1000) as uint32,
        utimeUntil: (blockchain.now() + 9000) as uint32,
        _total: numValidators as uint16,
        _main: numValidators as uint16,
        totalWeight,
        dict,
    };
    var config = net.getConfig();
    config.setParamRaw(34, vset.toCell());
    net.setConfig(config);
    return kps;
}

/// Build a raw complaint cell for the given validator pubkey
fun buildComplaintCell(validatorPubkey: uint256, suggestedFine: coins, suggestedFinePart: uint32): cell {
    val description = beginCell().storeUint(0xDEAD, 32).endCell();
    return beginCell()
        .storeUint(0xbc, 8) // Complaint prefix
        .storeUint(validatorPubkey, 256)
        .storeRef(description)
        .storeUint(0, 32) // createdAt (will be overwritten)
        .storeUint(0, 8) // severity
        .storeUint(0, 256) // rewardAddr (will be overwritten)
        .storeCoins(0) // paid (will be overwritten)
        .storeCoins(suggestedFine)
        .storeUint(suggestedFinePart, 32)
        .endCell();
}

/// Build a NewComplaint message body cell
fun buildComplaintBody(queryId: uint64, electionId: uint32, complaintCell: cell): cell {
    val cs = complaintCell.beginParse();
    return beginCell()
        .storeUint(0x52674370, 32) // NewComplaint opcode
        .storeUint(queryId, 64)
        .storeUint(electionId, 32)
        .storeSlice(cs)
        .endCell();
}

/// Build a VoteForComplaint cell
fun buildVoteCell(idx: uint16, electId: uint32, chash: uint256): cell {
    return VoteForComplaint {
        signTag: 0x56744350,
        idx,
        electId,
        chash,
    }.toCell();
}

/// Sign a vote and build the SignedVoteForComplaint message body cell
fun buildSignedVoteBody(queryId: uint64, privateKey: int, idx: uint16, electId: uint32, chash: uint256): cell {
    val voteCell = buildVoteCell(idx, electId, chash);
    val sigSlice = crypto.sign(privateKey, voteCell);

    val voteSlice = voteCell.beginParse();
    return beginCell()
        .storeUint(0x56744370, 32) // SignedVoteForComplaint opcode
        .storeUint(queryId, 64)
        .storeSlice(sigSlice) // 512-bit signature
        .storeSlice(voteSlice)
        .endCell();
}

/// Submit a known validator stake and return its pubkey.
/// Call BEFORE conductValidElections.
fun submitKnownValidatorStake(elector: Elector, totalStake: coins, kp: KeyPair): (address, uint256, coins) {
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    val stakeAt = elector.active_election_id();
    assert (stakeAt != 0) throw 999;

    val srcAddr = net.randomAddress("known-staker", MASTERCHAIN);
    net.topUp(srcAddr, stakePerValidator + ton("100"));

    val (_, srcHash) = srcAddr.getWorkchainAndHash();
    val adnlAddr: uint256 = 12345; // dummy ADNL

    val maxFactor: uint32 = (1 << 16) + (1 << 15); // 1.5
    val signature = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlAddr,
    );

    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256, stakeAt as uint32,
        maxFactor, adnlAddr, signature,
        { value: stakePerValidator + ONECOIN },
    );

    return (srcAddr, kp.publicKey as uint256, stakePerValidator);
}

/// Conduct elections with a known first validator.
/// Returns (stakeAt, knownPubkey) where knownPubkey is in the frozen dict.
fun conductElectionsWithKnownValidator(elector: Elector): (int, uint256) {
    val kp = crypto.generateKeyPair();
    val stakeAt = elector.active_election_id();

    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    // Submit known validator first
    val (_, knownPubkey, knownStake) = submitKnownValidatorStake(elector, 0, kp);
    var totalStake = knownStake;

    // Submit 4 more to meet minValidators
    var i = 0;
    while (i < 4) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        totalStake += stake;
        i += 1;
    }

    // Advance past close
    val (_, closeAt, _, _, _, _, _) = elector.participant_list_extended();
    net.setNow(closeAt + 1);
    net.runTickTock(elector.address, true);

    return (stakeAt, knownPubkey);
}

/// Test that vote with wrong sign tag is rejected
get fun `test vote wrong tag`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);

    // Set up vset with known validators
    val kps = setupVsetWithKnownValidators(5);

    // Register a complaint
    val fine = ton("100");
    val complaintCell = buildComplaintCell(frozenPubkey, fine, 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    elector.sendAny(sender, body, { value: ton("500") });

    // Build vote with wrong sign tag
    val wrongVoteCell = beginCell()
        .storeUint(0xDEADBEEF, 32) // wrong tag
        .storeUint(0, 16) // idx
        .storeUint(stakeAt, 32)
        .storeUint(0, 256) // chash
        .endCell();
    val sigSlice = crypto.sign(kps.get(0).privateKey, wrongVoteCell);

    val voteBody = beginCell()
        .storeUint(0x56744370, 32)
        .storeUint(1, 64) // queryId
        .storeSlice(sigSlice)
        .storeSlice(wrongVoteCell.beginParse())
        .endCell();

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    // Should throw 37 (wrong sign tag) — transaction should fail
    val res = elector.sendAny(voter, voteBody, { value: ton("1") });
    expect(res).toHaveFailedTx({ to: elector.address, exitCode: 37 });
}

/// Test that vote with invalid signature is rejected
get fun `test vote invalid signature`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);

    val kps = setupVsetWithKnownValidators(5);

    // Register a complaint
    val complaintCell = buildComplaintCell(frozenPubkey, ton("100"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    elector.sendAny(sender, body, { value: ton("500") });

    // Build vote with correct tag but sign with wrong key
    val wrongKp = crypto.generateKeyPair();
    val voteCell = buildVoteCell(0, stakeAt as uint32, 0);
    val sigSlice = crypto.sign(wrongKp.privateKey, voteCell); // wrong key

    val voteBody = beginCell()
        .storeUint(0x56744370, 32)
        .storeUint(1, 64)
        .storeSlice(sigSlice)
        .storeSlice(voteCell.beginParse())
        .endCell();

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    // Should throw 34 (invalid signature)
    val res = elector.sendAny(voter, voteBody, { value: ton("1") });
    expect(res).toHaveFailedTx({ to: elector.address, exitCode: 34 });
}

/// Test that vote for non-existent election is rejected
get fun `test vote no such elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);

    val kps = setupVsetWithKnownValidators(5);

    // Register a complaint first (so there IS a complaint)
    val complaintCell = buildComplaintCell(frozenPubkey, ton("100"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    elector.sendAny(sender, body, { value: ton("500") });

    // Vote with wrong election ID
    val wrongElectId: uint32 = (stakeAt + 999) as uint32;
    val voteBody = buildSignedVoteBody(1, kps.get(0).privateKey, 0, wrongElectId, 0);

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    // proceedRegisterVote returns -2, response opcode = -2 + 0xd6745240 = 0xd674523e
    val res = elector.sendAny(voter, voteBody, { value: ton("1") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: voter, opcode: 0xd674523e });
}

/// Test that vote for non-existent complaint returns error
get fun `test vote no such complaint`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);

    val kps = setupVsetWithKnownValidators(5);

    // Don't register any complaint — vote directly
    val fakeChash: uint256 = 12345;
    val voteBody = buildSignedVoteBody(1, kps.get(0).privateKey, 0, stakeAt as uint32, fakeChash);

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    // registerVote returns -1 (complaint not found), response = -1 + 0xd6745240 = 0xd674523f
    val res = elector.sendAny(voter, voteBody, { value: ton("1") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: voter, opcode: 0xd674523f });
}

/// Test that a successful vote is registered
get fun `test vote success`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);

    val kps = setupVsetWithKnownValidators(5);

    // Register a complaint against a frozen validator
    val fine = ton("100");
    val complaintCell = buildComplaintCell(frozenPubkey, fine, 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    val cplRes = elector.sendAny(sender, body, { value: ton("500") });
    expect(cplRes).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Get the actual complaint hash from list_complaints
    // The complaint is repacked by the contract, so hash differs from our cell.
    // Use get_past_complaints to iterate, or list_complaints.
    val complaints = elector.get_past_complaints(stakeAt as uint32);
    val firstComplaint = complaints.findFirst();
    assert (firstComplaint.isFound) throw 500;
    val chash = firstComplaint.getKey();

    // Vote with validator 0
    val voteBody = buildSignedVoteBody(2, kps.get(0).privateKey, 0, stakeAt as uint32, chash);
    val voter = net.randomAddress("voter0", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    // status 1 = vote accepted, response = 1 + 0xd6745240 = 0xd6745241
    val voteRes = elector.sendAny(voter, voteBody, { value: ton("1") });
    expect(voteRes).toHaveSuccessfulTx({ from: elector.address, to: voter, opcode: 0xd6745241 });
}

/// Test that voting twice is rejected
get fun `test vote already voted`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);

    val kps = setupVsetWithKnownValidators(5);

    // Register complaint
    val complaintCell = buildComplaintCell(frozenPubkey, ton("100"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    elector.sendAny(sender, body, { value: ton("500") });

    val complaints = elector.get_past_complaints(stakeAt as uint32);
    val firstComplaint = complaints.findFirst();
    assert (firstComplaint.isFound) throw 500;
    val chash = firstComplaint.getKey();

    // First vote — should succeed
    val voteBody1 = buildSignedVoteBody(2, kps.get(0).privateKey, 0, stakeAt as uint32, chash);
    val voter1 = net.randomAddress("voter0a", MASTERCHAIN);
    net.topUp(voter1, ton("10"));
    val res1 = elector.sendAny(voter1, voteBody1, { value: ton("1") });
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: voter1, opcode: 0xd6745241 });

    // Second vote with same validator idx — should return 0 (already voted)
    // response = 0 + 0xd6745240 = 0xd6745240
    val voteBody2 = buildSignedVoteBody(3, kps.get(0).privateKey, 0, stakeAt as uint32, chash);
    val voter2 = net.randomAddress("voter0b", MASTERCHAIN);
    net.topUp(voter2, ton("10"));
    val res2 = elector.sendAny(voter2, voteBody2, { value: ton("1") });
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: voter2, opcode: 0xd6745240 });
}
