import "@acton/crypto/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/types"
import "../contracts/messages"

/// Set up config param 34 with known validators (with ADNL addresses).
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

struct ComplaintRegistration {
    chash: uint256;
    senderHash: uint256;
}

/// Register a complaint via the wrapper, return the complaint hash and sender address hash
fun registerTestComplaintFull(elector: Elector, stakeAt: int, frozenPubkey: uint256, fine: coins, finePart: uint32): ComplaintRegistration {
    val complaint = createComplaint(frozenPubkey, fine, finePart);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    elector.sendNewComplaint(sender, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("500") });

    val complaints = elector.get_past_complaints(stakeAt as uint32);
    val first = complaints.findFirst();
    assert (first.isFound) throw 500;
    return ComplaintRegistration { chash: first.getKey(), senderHash: sender.getWorkchainAndHash().1 };
}

/// Register a complaint via the wrapper, return the complaint hash from storage
fun registerTestComplaint(elector: Elector, stakeAt: int, frozenPubkey: uint256, fine: coins): uint256 {
    return registerTestComplaintFull(elector, stakeAt, frozenPubkey, fine, 0).chash;
}

/// Sign a VoteForComplaint and send it via wrapper
fun sendVote(elector: Elector, queryId: uint64, privateKey: int, idx: uint16, electId: uint32, chash: uint256): SendResultList {
    val vote = VoteForComplaint { signTag: 0x56744350, idx, electId, chash };
    val voteCell = vote.toCell();
    val sig = crypto.sign(privateKey, voteCell).loadBits(512) as bits512;

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    return elector.sendSignedVoteForComplaint(voter, queryId, sig, voteCell.beginParse(), { value: ton("1") });
}

/// Test that vote with wrong sign tag is rejected
get fun `test vote wrong tag`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    // Build vote with wrong sign tag — must use manual cell since struct enforces correct tag
    val wrongVoteCell = beginCell()
        .storeUint(0xDEADBEEF, 32)
        .storeUint(0, 16)
        .storeUint(stakeAt, 32)
        .storeUint(0, 256)
        .endCell();
    val sig = crypto.sign(kps.get(0).privateKey, wrongVoteCell).loadBits(512) as bits512;

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    val res = elector.sendSignedVoteForComplaint(voter, 1, sig, wrongVoteCell.beginParse(), { value: ton("1") });
    expect(res).toHaveFailedTx({ to: elector.address, exitCode: 37 });
}

/// Test that vote with invalid signature is rejected
get fun `test vote invalid signature`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    val wrongKp = crypto.generateKeyPair();
    val vote = VoteForComplaint { signTag: 0x56744350, idx: 0, electId: stakeAt as uint32, chash: 0 };
    val voteCell = vote.toCell();
    val sig = crypto.sign(wrongKp.privateKey, voteCell).loadBits(512) as bits512; // wrong key

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    val res = elector.sendSignedVoteForComplaint(voter, 1, sig, voteCell.beginParse(), { value: ton("1") });
    expect(res).toHaveFailedTx({ to: elector.address, exitCode: 34 });
}

/// Test that vote for non-existent election is rejected
get fun `test vote no such elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    val wrongElectId: uint32 = (stakeAt + 999) as uint32;
    val res = sendVote(elector, 1, kps.get(0).privateKey, 0, wrongElectId, 0);
    // proceedRegisterVote returns -2, response opcode = -2 + 0xd6745240 = 0xd674523e
    expect(res).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd674523e });
}

/// Test that vote for non-existent complaint returns error
get fun `test vote no such complaint`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);

    val fakeChash: uint256 = 12345;
    val res = sendVote(elector, 1, kps.get(0).privateKey, 0, stakeAt as uint32, fakeChash);
    // registerVote returns -1 (complaint not found), response = -1 + 0xd6745240 = 0xd674523f
    expect(res).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd674523f });
}

/// Test full 2/3 voting cycle with fine deduction and reward verification
get fun `test vote success`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);

    val fine: coins = ton("100");
    val finePart: uint32 = 1 << 30; // 1/4 of stake as additional fine
    val reg = registerTestComplaintFull(elector, stakeAt, frozenPubkey, fine, finePart);
    val chash = reg.chash;
    val rewardAddr = reg.senderHash;

    // Record credit before voting
    val creditBefore = elector.compute_returned_stake(rewardAddr);

    // Known frozen stake from setup: conductElectionsWithKnownValidator uses this amount
    val stakeLimits = defaultStakeLimits();
    val stakeBefore: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    // Vote with validators idx 1-4 to collect 2/3 weight
    // Each has weight 100, total weight 500, need muldiv(500,2,3) = 333
    // 4 * 100 = 400 >= 333 → vote completes on 4th vote
    var i = 1;
    while (i <= 4) {
        val res = sendVote(elector, i as uint64, kps.get(i).privateKey, i as uint16, stakeAt as uint32, chash);
        if (i < 4) {
            // Vote accepted (status 1): 0xd6745241
            expect(res).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745241 });
        } else {
            // Vote finished (status 2): 0xd6745242
            expect(res).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745242 });
        }

        // Verify intermediate complaint state via show_complaint
        val complaintInfo = elector.show_complaint(stakeAt as uint32, chash);
        assert (complaintInfo != null) throw (600 + i);

        i += 1;
    }

    // After vote completed: verify reward credited to complainer
    // trueFine = min(stake, fine + mulDivFloor(stake, finePart, 1 << 32))
    val trueFine = min(stakeBefore, fine + mulDivFloor(stakeBefore, finePart, 1 << 32));

    // reward = min(trueFine >> 3, paid * 8)
    val info = elector.show_complaint(stakeAt as uint32, chash);
    assert (info != null) throw 630;
    val paid = info.complaint.paid;
    val expectedReward = min(trueFine >> 3, paid * 8);
    val creditAfter = elector.compute_returned_stake(rewardAddr);
    expect(creditAfter as int).toEqual((creditBefore + expectedReward) as int);
}

/// Test that voting twice is rejected
get fun `test vote already voted`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    val chash = registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    // First vote — should succeed
    val res1 = sendVote(elector, 2, kps.get(0).privateKey, 0, stakeAt as uint32, chash);
    expect(res1).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745241 });

    // Second vote with same validator idx — should return 0 (already voted)
    // response = 0 + 0xd6745240 = 0xd6745240
    val res2 = sendVote(elector, 3, kps.get(0).privateKey, 0, stakeAt as uint32, chash);
    expect(res2).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745240 });
}

/// Test that vote on completed complaint with changed vset returns old_vset (-3)
get fun `test vote old vset finished`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    val chash = registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    // Vote with validators idx 1-4 to collect 2/3 weight
    // Each has weight 100, total weight 500, need muldiv(500,2,3) = 333
    // 4 * 100 = 400 >= 333 → vote completes on 4th vote
    var i = 1;
    while (i <= 4) {
        val res = sendVote(elector, i as uint64, kps.get(i).privateKey, i as uint16, stakeAt as uint32, chash);
        if (i < 4) {
            // Vote accepted (status 1): 0xd6745241
            expect(res).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745241 });
        } else {
            // Vote finished (status 2): 0xd6745242
            expect(res).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745242 });
        }
        i += 1;
    }

    // Change config param 34 to a different vset (same validators, different timing)
    // so that vsetId changes but signatures still verify
    var dict: map<uint16, AnyValidatorDescr> = [];
    var totalWeight: uint64 = 0;
    i = 0;
    while (i < 5) {
        val weight: uint64 = 100;
        dict.set(i, ValidatorDescrWithAdnlAddr {
            validatorPubkey: kps.get(i).publicKey as uint256,
            validatorWeight: weight,
            adnlAddr: 0,
        });
        totalWeight += weight;
        i += 1;
    }
    val newVset = VSet {
        utimeSince: (blockchain.now() + 100) as uint32,
        utimeUntil: (blockchain.now() + 10100) as uint32,
        _total: 5 as uint16,
        _main: 5 as uint16,
        totalWeight,
        dict,
    };
    var config = net.getConfig();
    config.setParamRaw(34, newVset.toCell());
    net.setConfig(config);

    // Try voting with idx 0 — vset changed and weightRemaining < 0 → returns -3
    // response = -3 + 0xd6745240 = 0xd674523d
    val lateres = sendVote(elector, 10, kps.get(0).privateKey, 0, stakeAt as uint32, chash);
    expect(lateres).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd674523d });
}

/// Test that vote resets when vset changes before 2/3 collected
get fun `test vote old vset reset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    val chash = registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    // Vote with only 1 validator (idx 1, weight 100 < 333) — not enough for 2/3
    val res1 = sendVote(elector, 1, kps.get(1).privateKey, 1, stakeAt as uint32, chash);
    expect(res1).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745241 });

    // Change config param 34 to a different vset (same validators, different timing)
    var dict: map<uint16, AnyValidatorDescr> = [];
    var totalWeight: uint64 = 0;
    var i = 0;
    while (i < 5) {
        val weight: uint64 = 100;
        dict.set(i, ValidatorDescrWithAdnlAddr {
            validatorPubkey: kps.get(i).publicKey as uint256,
            validatorWeight: weight,
            adnlAddr: 0,
        });
        totalWeight += weight;
        i += 1;
    }
    val newVset = VSet {
        utimeSince: (blockchain.now() + 100) as uint32,
        utimeUntil: (blockchain.now() + 10100) as uint32,
        _total: 5 as uint16,
        _main: 5 as uint16,
        totalWeight,
        dict,
    };
    var config = net.getConfig();
    config.setParamRaw(34, newVset.toCell());
    net.setConfig(config);

    // Vote with idx 2 — vset changed, weightRemaining > 0 → reset, then vote accepted
    // response = 1 + 0xd6745240 = 0xd6745241
    val res2 = sendVote(elector, 2, kps.get(2).privateKey, 2, stakeAt as uint32, chash);
    expect(res2).toHaveSuccessfulTx({ from: elector.address, opcode: 0xd6745241 });

    // Verify vote was reset: show_complaint should show updated vsetId
    val info = elector.show_complaint(stakeAt as uint32, chash);
    assert (info != null) throw 600;
    // The vsetId should now match the new vset hash
    expect(info.vsetId).toEqual(newVset.toCell().hash());
}
