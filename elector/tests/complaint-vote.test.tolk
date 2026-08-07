import "@stdlib/lisp-lists"
import "@acton/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/transaction"
import "test-utils"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Elector.gen"

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
        dict.set(
            i,
            ValidatorDescrWithAdnlAddr {
                validatorPubkey: kp.publicKey,
                validatorWeight: weight,
                adnlAddr: 0,
            },
        );
        totalWeight += weight;
        i += 1;
    }
    val vset = VSet {
        utimeSince: (blockchain.now() - 1000),
        utimeUntil: (blockchain.now() + 9000),
        _total: numValidators,
        _main: numValidators,
        totalWeight,
        dict,
    };
    var config = testing.getConfig();
    config.setParamRaw(34, vset.toCell());
    testing.setConfig(config);
    return kps;
}

struct ComplaintRegistration {
    chash: uint256
    senderHash: uint256
}

/// Register a complaint via the wrapper, return the complaint hash and sender address hash
fun registerTestComplaintFull(
    elector: Elector,
    stakeAt: int,
    frozenPubkey: uint256,
    fine: coins,
    finePart: uint32,
): ComplaintRegistration {
    val complaint = createComplaint(frozenPubkey, fine, finePart);
    val sender = randomAddress("complainer", MASTERCHAIN);
    testing.topUp(sender, ton("1000"));
    elector.sendNewComplaint(
        sender,
        1,
        stakeAt,
        complaint,
        { value: ton("500") },
    );

    val complaints = elector.getPastComplaints(stakeAt);
    val first = complaints.findFirst();
    assert (first.isFound) throw 500;
    return ComplaintRegistration {
        chash: first.getKey(),
        senderHash: sender.getWorkchainAndHash().1,
    };
}

/// Register a complaint via the wrapper, return the complaint hash from storage
fun registerTestComplaint(
    elector: Elector,
    stakeAt: int,
    frozenPubkey: uint256,
    fine: coins,
): uint256 {
    return registerTestComplaintFull(elector, stakeAt, frozenPubkey, fine, 0).chash;
}

/// Sign a VoteForComplaint and send it via wrapper
fun sendVote(
    elector: Elector,
    queryId: uint64,
    privateKey: int,
    idx: uint16,
    electId: uint32,
    chash: uint256,
): SendResultList {
    val vote = VoteForComplaint {
        signTag: 0x56744350,
        idx,
        electId,
        chash,
    };
    val sig = crypto.sign(privateKey, vote.toCell()).loadBits(512) as bits512;

    val voter = randomAddress("voter", MASTERCHAIN);
    testing.topUp(voter, ton("10"));
    return elector.sendSignedVoteForComplaint(
        voter,
        queryId,
        sig,
        vote,
        { value: ton("1") },
    );
}

/// Test that vote with wrong sign tag is rejected
get fun `test vote wrong tag`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    val wrongVote = VoteForComplaint {
        signTag: 0xDEADBEEF,
        idx: 0,
        electId: stakeAt,
        chash: 0,
    };
    val sig = crypto.sign(kps.get(0).privateKey, wrongVote.toCell()).loadBits(512) as bits512;

    val voter = randomAddress("voter", MASTERCHAIN);
    testing.topUp(voter, ton("10"));
    val res = elector.sendSignedVoteForComplaint(
        voter,
        1,
        sig,
        wrongVote,
        { value: ton("1") },
    );
    expect(res).toHaveFailedTx({ to: elector.address, exitCode: 37 });
}

/// Test that vote with invalid signature is rejected
get fun `test vote invalid signature`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val _kps = setupVsetWithKnownValidators(5);
    registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    val wrongKp = crypto.generateKeyPair();
    val vote = VoteForComplaint {
        signTag: 0x56744350,
        idx: 0,
        electId: stakeAt,
        chash: 0,
    };
    val sig = crypto.sign(wrongKp.privateKey, vote.toCell()).loadBits(512) as bits512; // wrong key

    val voter = randomAddress("voter", MASTERCHAIN);
    testing.topUp(voter, ton("10"));
    val res = elector.sendSignedVoteForComplaint(
        voter,
        1,
        sig,
        vote,
        { value: ton("1") },
    );
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

    val wrongElectId: uint32 = (stakeAt + 999);
    val res = sendVote(
        elector,
        1,
        kps.get(0).privateKey,
        0,
        wrongElectId,
        0,
    );
    // proceedRegisterVote returns -2, response opcode = -2 + 0xd6745240 = 0xd674523e
    expect(res).toHaveTx({ from: elector.address, opcode: 0xd674523e });
}

/// Test that vote for non-existent complaint returns error
get fun `test vote no such complaint`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, _frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);

    val fakeChash: uint256 = 12345;
    val res = sendVote(
        elector,
        1,
        kps.get(0).privateKey,
        0,
        stakeAt,
        fakeChash,
    );
    // registerVote returns -1 (complaint not found), response = -1 + 0xd6745240 = 0xd674523f
    expect(res).toHaveTx({ from: elector.address, opcode: 0xd674523f });
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
    val creditBefore = elector.computeReturnedStake(rewardAddr);

    // Known frozen stake from setup: conductElectionsWithKnownValidator uses this amount
    val stakeLimits = defaultStakeLimits();
    val stakeBefore: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    // Vote with validators idx 1-4 to collect 2/3 weight
    // Each has weight 100, total weight 500, need muldiv(500,2,3) = 333
    // 4 * 100 = 400 >= 333 → vote completes on 4th vote
    var i = 1;
    while (i <= 4) {
        val res = sendVote(
            elector,
            i,
            kps.get(i).privateKey,
            i,
            stakeAt,
            chash,
        );
        if (i < 4) {
            // Vote accepted (status 1): 0xd6745241
            expect(res).toHaveTx({ from: elector.address, opcode: 0xd6745241 });
        } else {
            // Vote finished (status 2): 0xd6745242
            expect(res).toHaveTx({ from: elector.address, opcode: 0xd6745242 });
        }

        // Verify intermediate complaint state via show_complaint
        val complaintInfo = elector.showComplaint(stakeAt, chash);
        assert (complaintInfo != null) throw (600 + i);

        i += 1;
    }

    // After vote completed: verify reward credited to complainer
    // trueFine = min(stake, fine + mulDivFloor(stake, finePart, 1 << 32))
    val trueFine = min(stakeBefore, fine + mulDivFloor(stakeBefore, finePart, 1 << 32));

    // reward = min(trueFine >> 3, paid * 8)
    val info = elector.showComplaint(stakeAt, chash);
    assert (info != null) throw 630;
    val paid = info.complaint.paid;
    val expectedReward = min(trueFine >> 3, paid * 8);
    val creditAfter = elector.computeReturnedStake(rewardAddr);
    expect(creditAfter).toEqual((creditBefore + expectedReward));
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
    val res1 = sendVote(
        elector,
        2,
        kps.get(0).privateKey,
        0,
        stakeAt,
        chash,
    );
    expect(res1).toHaveTx({ from: elector.address, opcode: 0xd6745241 });

    // Second vote with same validator idx — should return 0 (already voted)
    // response = 0 + 0xd6745240 = 0xd6745240
    val res2 = sendVote(
        elector,
        3,
        kps.get(0).privateKey,
        0,
        stakeAt,
        chash,
    );
    expect(res2).toHaveTx({ from: elector.address, opcode: 0xd6745240 });
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
        val res = sendVote(
            elector,
            i,
            kps.get(i).privateKey,
            i,
            stakeAt,
            chash,
        );
        if (i < 4) {
            // Vote accepted (status 1): 0xd6745241
            expect(res).toHaveTx({ from: elector.address, opcode: 0xd6745241 });
        } else {
            // Vote finished (status 2): 0xd6745242
            expect(res).toHaveTx({ from: elector.address, opcode: 0xd6745242 });
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
        dict.set(
            i,
            ValidatorDescrWithAdnlAddr {
                validatorPubkey: kps.get(i).publicKey,
                validatorWeight: weight,
                adnlAddr: 0,
            },
        );
        totalWeight += weight;
        i += 1;
    }
    val newVset = VSet {
        utimeSince: (blockchain.now() + 100),
        utimeUntil: (blockchain.now() + 10100),
        _total: 5,
        _main: 5,
        totalWeight,
        dict,
    };
    var config = testing.getConfig();
    config.setParamRaw(34, newVset.toCell());
    testing.setConfig(config);

    // Try voting with idx 0 — vset changed and weightRemaining < 0 → returns -3
    // response = -3 + 0xd6745240 = 0xd674523d
    val lateres = sendVote(
        elector,
        10,
        kps.get(0).privateKey,
        0,
        stakeAt,
        chash,
    );
    expect(lateres).toHaveTx({ from: elector.address, opcode: 0xd674523d });
}

/// Find a past election entry by id from the past_elections getter list
fun findPastElection(elector: Elector, id: int): PastElectionFullEntry? {
    var l = elector.pastElections();
    var result: PastElectionFullEntry? = null;
    while (!l.isEmpty()) {
        val entry = l.popHead();
        if (entry.id == id) {
            result = entry;
        }
    }
    return result;
}

/// Recompute the canonical total stake directly from the frozen dict.
/// This is what `throw_unless(59, total == tot_stakes)` checks against pastElection.totalStake.
fun sumFrozenStakes(fd: FrozenDict): int {
    var total = 0;
    var pubkey = -1;
    var found = true;
    do {
        val lookup = fd.findKeyGreater(pubkey);
        found = lookup.isFound;
        if (found) {
            pubkey = lookup.getKey();
            total += lookup.loadValue().stake;
        }
    } while (found);
    return total;
}

struct SlashSetup {
    stakeAt: int
    vsetCell: cell
    knownPubkey: uint256
    knownStakerHash: uint256
}

/// Conduct elections with one known validator AND capture the elected vset cell
/// (needed to later install + promote + unfreeze).
fun conductWithKnownValidatorAndVset(elector: Elector, configAddr: address): SlashSetup {
    val kp = crypto.generateKeyPair();
    val stakeAt = elector.activeElectionId();
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    val (knownSrc, knownPubkey, knownStake) = submitKnownValidatorStake(elector, 0, kp);
    val (_, knownStakerHash) = knownSrc.getWorkchainAndHash();

    var totalStake = knownStake;
    var i = 0;
    while (i < 4) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        totalStake += stake;
        i += 1;
    }

    val (
        _,
        closeAt,
        _,
        _,
        _,
        _,
        _,
    ) = elector.participantListExtended();
    testing.setNow(closeAt + 1);
    val tick = testing.runTickTock(elector.address, true);

    val tx = tick.findTransaction<ElectedVSetMsg>({ from: elector.address, to: configAddr });
    val body = tx!.loadBody<ElectedVSetMsg>();

    return SlashSetup {
        stakeAt,
        vsetCell: body.vset,
        knownPubkey,
        knownStakerHash,
    };
}

/// Full slash -> unfreeze flow.
/// Proves that after punish() the invariant totalStake == Σ frozen.stake still holds,
/// unfreeze does NOT throw 59, and the slashed validator receives the REDUCED stake back.
get fun `test slash then unfreeze`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val sl = conductWithKnownValidatorAndVset(elector, setup.configAddr);
    val stakeAt = sl.stakeAt;
    val victimPubkey = sl.knownPubkey;

    // ---- pre-slash invariant: pastElection.totalStake == Σ frozen.stake ----
    val pe0 = findPastElection(elector, stakeAt)!;
    expect(pe0.totalStake).toEqual(sumFrozenStakes(pe0.frozenDict));
    val victim0Lookup = pe0.frozenDict.get(victimPubkey);
    assert (victim0Lookup.isFound) throw 700;
    val victim0 = victim0Lookup.loadValue();
    val victimStake0 = victim0.stake;
    val victimAddr = victim0.addr;
    expect(victimAddr).toEqual(sl.knownStakerHash);

    // ---- slash via 2/3 vote (idx 1..4, weight 100 each, threshold = muldiv(500,2,3)=333) ----
    val kps = setupVsetWithKnownValidators(5);
    val fine: coins = ton("100");
    val finePart: uint32 = 1 << 30; // + 1/4 of the stake
    val reg = registerTestComplaintFull(elector, stakeAt, victimPubkey, fine, finePart);
    val chash = reg.chash;

    var i = 1;
    while (i <= 4) {
        val res = sendVote(
            elector,
            i,
            kps.get(i).privateKey,
            i,
            stakeAt,
            chash,
        );
        if (i < 4) {
            expect(res).toHaveTx({ from: elector.address, opcode: 0xd6745241 }); // Accepted
        } else {
            expect(
                res,
            ).toHaveTx({ from: elector.address, opcode: 0xd6745242 });           // Finished -> punish
        }
        i += 1;
    }

    // ---- post-slash: BOTH stake and totalStake drop by the SAME fine; invariant holds ----
    val trueFine = min(victimStake0, fine + mulDivFloor(victimStake0, finePart, 1 << 32));
    val pe1 = findPastElection(elector, stakeAt)!;
    val victimStake1 = pe1.frozenDict.get(victimPubkey).loadValue().stake;
    expect(victimStake1).toEqual(victimStake0 - trueFine);           // frozen stake reduced
    expect(pe1.totalStake).toEqual(
        pe0.totalStake - trueFine,
    );                                                               // totalStake reduced by same fine
    expect(pe1.totalStake).toEqual(sumFrozenStakes(pe1.frozenDict)); // <-- the assert-59 invariant

    // ---- install elected vset → activeId set, bonuses funded from slashed grams ----
    var config = testing.getConfig();
    config.setParamRaw(34, sl.vsetCell);
    testing.setConfig(config);
    testing.runTickTock(elector.address, true);
    expect(elector.activeElectionId()).toEqual(0); // currectElections cleared = vset installed

    // ---- promote to a new vset so this election becomes inactive & unfreezeAt is recomputed ----
    val stakeHeld = defaultValidationTimes().stakeHeldFor;
    val newVset = buildVSet(blockchain.now(), blockchain.now() + 10000, 1, 1, 0);
    config = testing.getConfig();
    config.setParamRaw(34, newVset.toCell());
    config.setParamRaw(36, newVset.toCell());
    testing.setConfig(config);
    val promoteTime = blockchain.now() + 100;
    testing.setNow(promoteTime);
    testing.runTickTock(elector.address, true);

    // ---- state right before unfreeze: bonuses now present → unfreezeWithBonuses path ----
    val pe2 = findPastElection(elector, stakeAt)!;
    val victimStake2 = pe2.frozenDict.get(victimPubkey).loadValue().stake;
    expect(victimStake2).toEqual(victimStake1);                      // unchanged since slash
    expect(pe2.totalStake).toEqual(
        sumFrozenStakes(pe2.frozenDict),
    );                                                               // invariant holds with bonuses set
    assert (
        pe2.bonuses > 0
    ) throw 702;                                                     // bonus path actually exercised
    val victimCreditBefore = elector.computeReturnedStake(victimAddr);

    // ---- UNFREEZE: the tick that would throw 59 if the "desync" claim were true ----
    testing.setNow(promoteTime + stakeHeld + 1);
    testing.runTickTock(elector.address, true);

    // past election removed → unfreeze succeeded (no exit 59, no locked funds)
    val gone = findPastElection(elector, stakeAt);
    assert (gone == null) throw 703;

    // victim got back the REDUCED stake (+ proportional bonus), NOT the original
    val expectedBonus = mulDivFloor(pe2.bonuses, victimStake2, pe2.totalStake);
    val victimCreditAfter = elector.computeReturnedStake(victimAddr);
    expect(victimCreditAfter - victimCreditBefore).toEqual(victimStake2 + expectedBonus);
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
    val res1 = sendVote(
        elector,
        1,
        kps.get(1).privateKey,
        1,
        stakeAt,
        chash,
    );
    expect(res1).toHaveTx({ from: elector.address, opcode: 0xd6745241 });

    // Change config param 34 to a different vset (same validators, different timing)
    var dict: map<uint16, AnyValidatorDescr> = [];
    var totalWeight: uint64 = 0;
    var i = 0;
    while (i < 5) {
        val weight: uint64 = 100;
        dict.set(
            i,
            ValidatorDescrWithAdnlAddr {
                validatorPubkey: kps.get(i).publicKey,
                validatorWeight: weight,
                adnlAddr: 0,
            },
        );
        totalWeight += weight;
        i += 1;
    }
    val newVset = VSet {
        utimeSince: (blockchain.now() + 100),
        utimeUntil: (blockchain.now() + 10100),
        _total: 5,
        _main: 5,
        totalWeight,
        dict,
    };
    var config = testing.getConfig();
    config.setParamRaw(34, newVset.toCell());
    testing.setConfig(config);

    // Vote with idx 2 — vset changed, weightRemaining > 0 → reset, then vote accepted
    // response = 1 + 0xd6745240 = 0xd6745241
    val res2 = sendVote(
        elector,
        2,
        kps.get(2).privateKey,
        2,
        stakeAt,
        chash,
    );
    expect(res2).toHaveTx({ from: elector.address, opcode: 0xd6745241 });

    // Verify vote was reset: show_complaint should show updated vsetId
    val info = elector.showComplaint(stakeAt, chash);
    assert (info != null) throw 600;
    // The vsetId should now match the new vset hash
    expect(info.vsetId).toEqual(newVset.toCell().hash());
}
