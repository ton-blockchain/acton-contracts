import "@acton/crypto/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/messages"
import "../contracts/types"

/// Benchmark: announce elections via tick-tock
get fun `test bench announce elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    net.runTickTock(elector.address, true);

    expect(elector.activeElectionId()).toNotEqual(0);
}

/// Benchmark: submit a valid stake
get fun `test bench new stake`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    val (_, _, _, pubkey, stake) = submitValidStake(elector, 0);

    expect(elector.participatesIn(pubkey)).toEqual(stake);
}

/// Benchmark: conduct elections (5 validators, tick-tock)
get fun `test bench conduct elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    conductValidElections(elector);

    val (
        _,
        _,
        _,
        _,
        _,
        _,
        isFinished,
    ) = elector.participantListExtended();
    expect(isFinished).toEqual(true);
}

/// Benchmark: install vset via tick-tock after elections
get fun `test bench install vset`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (_, vsetCell, _) = conductElectionsAndGetVset(elector, setup.configAddr);

    var config = net.getConfig();
    config.setParamRaw(34, vsetCell);
    net.setConfig(config);

    net.runTickTock(elector.address, true);

    expect(elector.activeElectionId()).toEqual(0);
}

/// Benchmark: recover stake after elections
get fun `test bench recover stake`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    // Submit 6 validators with maxValidators=5 so the 6th gets credited back
    var config = net.getConfig();
    config.setParamRaw(
        16,
        ValidatorLimits {
            maxValidators: 5,
            maxMainValidators: 5,
            minValidators: 5,
        }.toCell(),
    );
    net.setConfig(config);

    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");
    var totalStake: coins = 0;
    var extraSrcAddr = net.randomAddress("placeholder", MASTERCHAIN);
    var i = 0;
    while (i < 6) {
        val (_, srcAddr, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        totalStake += stake;
        if (i == 5) {
            extraSrcAddr = srcAddr;
        }
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
    net.setNow(closeAt + 1);
    net.runTickTock(elector.address, true);

    val res = elector.sendRecoverStakeRequest(extraSrcAddr, 1, { value: ton("1") });
    expect(res).toHaveSuccessfulTx<PayStake>({ from: elector.address, to: extraSrcAddr });
}

/// Benchmark: submit complaint
get fun `test bench new complaint`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, knownPubkey) = conductElectionsWithKnownValidator(elector);

    val complaint = createComplaint(knownPubkey, ton("100"), 1 << 30);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));

    val res = elector.sendNewComplaint(
        sender,
        1,
        stakeAt,
        complaint.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Benchmark: full voting cycle (2/3 threshold)
get fun `test bench complaint vote`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, frozenPubkey) = conductElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    val chash = registerTestComplaint(elector, stakeAt, frozenPubkey, ton("100"));

    // 4 votes to reach 2/3 (4*100=400 >= 333)
    var i = 1;
    while (i <= 4) {
        sendVote(
            elector,
            i,
            kps.get(i).privateKey,
            i,
            stakeAt,
            chash,
        );
        i += 1;
    }

    val info = elector.showComplaint(stakeAt, chash);
    assert (info != null) throw 700;
    expect(info.weightRemaining < 0).toEqual(true);
}

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
    var config = net.getConfig();
    config.setParamRaw(34, vset.toCell());
    net.setConfig(config);
    return kps;
}

/// Register a complaint, return the complaint hash from storage
fun registerTestComplaint(
    elector: Elector,
    stakeAt: int,
    frozenPubkey: uint256,
    fine: coins,
): uint256 {
    val complaint = createComplaint(frozenPubkey, fine, 0);
    val sender = net.randomAddress("complainer", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    elector.sendNewComplaint(
        sender,
        1,
        stakeAt,
        complaint.toCell().beginParse(),
        { value: ton("500") },
    );

    val complaints = elector.getPastComplaints(stakeAt);
    val first = complaints.findFirst();
    assert (first.isFound) throw 500;
    return first.getKey();
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
    val voteCell = vote.toCell();
    val sig = crypto.sign(privateKey, voteCell).loadBits(512) as bits512;

    val voter = net.randomAddress("voter", MASTERCHAIN);
    net.topUp(voter, ton("10"));
    return elector.sendSignedVoteForComplaint(
        voter,
        queryId,
        sig,
        voteCell.beginParse(),
        { value: ton("1") },
    );
}
