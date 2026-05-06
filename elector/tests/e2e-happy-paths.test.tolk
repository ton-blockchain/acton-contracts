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

const ELECTOR_E2E_EXTRA_VALIDATORS = 6
const ELECTOR_E2E_COMPLAINT_FINE = ton("100")
const ELECTOR_E2E_COMPLAINT_FINE_PART = 1 << 30
const ELECTOR_E2E_VOTE_THRESHOLD = 4
const ELECTOR_E2E_KEY_SEED_BASE = 0xE1EC70A

fun electorE2eKeyPair(index: int): KeyPair {
    return crypto.seedToKeyPair((ELECTOR_E2E_KEY_SEED_BASE + index) as uint256);
}

// fmt-ignore
fun submitE2eStake(elector: Elector, totalStake: coins, validatorIndex: int, customStake: coins = 0): (SendResultList, address, int, uint256, coins) {
    val kp = electorE2eKeyPair(validatorIndex);
    val adnlAddr = randomAddress("elector-e2e-adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();

    val stakeLimits = defaultStakeLimits();
    val minStake = max(stakeLimits.minStake, totalStake >> 12);
    val stake: coins = customStake > 0 ? customStake : minStake + ton("1000");

    val stakeAt = elector.activeElectionId();
    assert (stakeAt != 0) throw 999;

    val srcAddr = randomAddress("elector-e2e-staker", MASTERCHAIN);
    testing.topUp(srcAddr, stake + ton("100"));

    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val maxFactor: uint32 = (1 << 16) + (1 << 15);
    val signature = generateStakeSignature(
        kp.privateKey,
        stakeAt,
        maxFactor,
        srcHash,
        adnlInt,
    );

    val res = elector.sendNewStakeMessage(
        srcAddr,
        0,
        kp.publicKey,
        stakeAt,
        maxFactor,
        adnlInt,
        signature,
        { value: stake + ONECOIN },
    );

    return (res, srcAddr, stakeAt, kp.publicKey, stake);
}

fun submitE2eKnownValidatorStake(elector: Elector, kp: KeyPair): (address, uint256, coins) {
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    val stakeAt = elector.activeElectionId();
    assert (stakeAt != 0) throw 999;

    val srcAddr = randomAddress("elector-e2e-known-staker", MASTERCHAIN);
    testing.topUp(srcAddr, stakePerValidator + ton("100"));

    val (_, srcHash) = srcAddr.getWorkchainAndHash();
    val adnlAddr: uint256 = 12345;

    val maxFactor: uint32 = (1 << 16) + (1 << 15);
    val signature = generateStakeSignature(
        kp.privateKey,
        stakeAt,
        maxFactor,
        srcHash,
        adnlAddr,
    );

    elector.sendNewStakeMessage(
        srcAddr,
        0,
        kp.publicKey,
        stakeAt,
        maxFactor,
        adnlAddr,
        signature,
        { value: stakePerValidator + ONECOIN },
    );

    return (srcAddr, kp.publicKey, stakePerValidator);
}

fun conductE2eElections(elector: Elector): int {
    val stakeAt = elector.activeElectionId();
    assert (stakeAt != 0) throw 998;

    val validatorLimits = defaultValidatorLimits();
    val stakeLimits = defaultStakeLimits();

    var totalStake: coins = 0;
    val numValidators = max(validatorLimits.minValidators, 5);
    val stakePerValidator: coins = stakeLimits.minTotalStake / numValidators + ton("10000");
    var i = 0;
    while (i < numValidators) {
        val (_, _, _, _, stake) = submitE2eStake(elector, totalStake, i, stakePerValidator);
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
    testing.runTickTock(elector.address, true);

    return stakeAt;
}

fun conductE2eElectionsWithKnownValidator(elector: Elector): (int, uint256) {
    val kp = electorE2eKeyPair(100);
    val stakeAt = elector.activeElectionId();

    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    val (_, knownPubkey, knownStake) = submitE2eKnownValidatorStake(elector, kp);
    var totalStake = knownStake;

    var i = 0;
    while (i < 4) {
        val (_, _, _, _, stake) = submitE2eStake(elector, totalStake, 101 + i, stakePerValidator);
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
    testing.runTickTock(elector.address, true);

    return (stakeAt, knownPubkey);
}

fun conductE2eElectionsAndGetVset(
    elector: Elector,
    configAddr: address,
): (int, cell, uint256) {
    val stakeAt = elector.activeElectionId();
    assert (stakeAt != 0) throw 998;

    val validatorLimits = defaultValidatorLimits();
    val stakeLimits = defaultStakeLimits();

    var totalStake: coins = 0;
    val numValidators = max(validatorLimits.minValidators, 5);
    val stakePerValidator: coins = stakeLimits.minTotalStake / numValidators + ton("10000");
    var firstStakerHash: uint256 = 0;
    var i = 0;
    while (i < numValidators) {
        val (_, srcAddr, _, _, stake) = submitE2eStake(elector, totalStake, i, stakePerValidator);
        if (i == 0) {
            val (_, hash) = srcAddr.getWorkchainAndHash();
            firstStakerHash = hash;
        }
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
    val tickResult = testing.runTickTock(elector.address, true);

    val tx = tickResult.findTransaction<ElectedVSetMsg>({ from: elector.address, to: configAddr });
    val body = tx!.loadBody<ElectedVSetMsg>();

    return (stakeAt, body.vset, firstStakerHash);
}

fun announceElectionsStage(): ElectorSetup {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);

    expect(elector.activeElectionId()).toNotEqual(0);
    return setup;
}

fun submitStakeStage(setup: ElectorSetup) {
    val elector = setup.elector;

    val (_, _, _, pubkey, stake) = submitE2eStake(elector, 0, 0);

    expect(elector.participatesIn(pubkey)).toEqual(stake);
}

fun conductElectionsStage(setup: ElectorSetup) {
    val elector = setup.elector;

    conductE2eElections(elector);

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

fun installVsetStage(setup: ElectorSetup) {
    val elector = setup.elector;

    val (_, vsetCell, _) = conductE2eElectionsAndGetVset(elector, setup.configAddr);

    var config = testing.getConfig();
    config.setParamRaw(34, vsetCell);
    testing.setConfig(config);

    testing.runTickTock(elector.address, true);

    expect(elector.activeElectionId()).toEqual(0);
}

fun recoverStakeStage(setup: ElectorSetup) {
    val elector = setup.elector;

    // Submit 6 validators with maxValidators=5 so the 6th gets credited back
    var config = testing.getConfig();
    config.setParamRaw(
        16,
        ValidatorLimits {
            maxValidators: 5,
            maxMainValidators: 5,
            minValidators: 5,
        }.toCell(),
    );
    testing.setConfig(config);

    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");
    var totalStake: coins = 0;
    var extraSrcAddr = randomAddress("placeholder", MASTERCHAIN);
    var i = 0;
    while (i < ELECTOR_E2E_EXTRA_VALIDATORS) {
        val (_, srcAddr, _, _, stake) = submitE2eStake(
            elector,
            totalStake,
            i,
            stakePerValidator,
        );
        totalStake += stake;
        if (i == ELECTOR_E2E_EXTRA_VALIDATORS - 1) {
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
    testing.setNow(closeAt + 1);
    testing.runTickTock(elector.address, true);

    val res = elector.sendRecoverStakeRequest(extraSrcAddr, 1, { value: ton("1") });
    expect(res).toHaveTx<PayStake>({ from: elector.address, to: extraSrcAddr });
}

fun submitComplaintStage(setup: ElectorSetup) {
    val elector = setup.elector;

    val (stakeAt, knownPubkey) = conductE2eElectionsWithKnownValidator(elector);

    val complaint = createComplaint(
        knownPubkey,
        ELECTOR_E2E_COMPLAINT_FINE,
        ELECTOR_E2E_COMPLAINT_FINE_PART,
    );
    val sender = randomAddress("complainer", MASTERCHAIN);
    testing.topUp(sender, ton("1000"));

    val res = elector.sendNewComplaint(sender, 1, stakeAt, complaint, { value: ton("500") });
    expect(res).toHaveTx({ from: elector.address, to: sender });
}

fun voteForComplaintStage(setup: ElectorSetup) {
    val elector = setup.elector;

    val (stakeAt, frozenPubkey) = conductE2eElectionsWithKnownValidator(elector);
    val kps = setupVsetWithKnownValidators(5);
    val chash = registerTestComplaint(elector, stakeAt, frozenPubkey, ELECTOR_E2E_COMPLAINT_FINE);

    // 4 votes to reach 2/3 (4*100=400 >= 333)
    var i = 1;
    while (i <= ELECTOR_E2E_VOTE_THRESHOLD) {
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

get fun `test elector e2e bench: stage 1 announce elections`() {
    announceElectionsStage();
}

get fun `test elector e2e bench: stage 2 submit valid stake`() {
    val setup = announceElectionsStage();
    submitStakeStage(setup);
}

get fun `test elector e2e bench: stage 3 conduct elections`() {
    val setup = announceElectionsStage();
    conductElectionsStage(setup);
}

get fun `test elector e2e bench: stage 4 install validator set`() {
    val setup = announceElectionsStage();
    installVsetStage(setup);
}

get fun `test elector e2e bench: stage 5 recover stake`() {
    val setup = announceElectionsStage();
    recoverStakeStage(setup);
}

get fun `test elector e2e bench: stage 6 submit complaint`() {
    val setup = announceElectionsStage();
    submitComplaintStage(setup);
}

get fun `test elector e2e bench: stage 7 full complaint voting cycle`() {
    val setup = announceElectionsStage();
    voteForComplaintStage(setup);
}

/// Set up config param 34 with known validators (with ADNL addresses).
/// Returns array of KeyPairs used for the validators.
fun setupVsetWithKnownValidators(numValidators: int): array<KeyPair> {
    var kps: array<KeyPair> = [];
    var dict: map<uint16, AnyValidatorDescr> = [];
    var totalWeight: uint64 = 0;
    var i = 0;
    while (i < numValidators) {
        val kp = electorE2eKeyPair(200 + i);
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

/// Register a complaint, return the complaint hash from storage
fun registerTestComplaint(
    elector: Elector,
    stakeAt: int,
    frozenPubkey: uint256,
    fine: coins,
): uint256 {
    val complaint = createComplaint(frozenPubkey, fine, 0);
    val sender = randomAddress("complainer", MASTERCHAIN);
    testing.topUp(sender, ton("1000"));
    elector.sendNewComplaint(sender, 1, stakeAt, complaint, { value: ton("500") });

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
    val sig = crypto.sign(privateKey, vote.toCell()).loadBits(512) as bits512;

    val voter = randomAddress("voter", MASTERCHAIN);
    testing.topUp(voter, ton("10"));
    return elector.sendSignedVoteForComplaint(voter, queryId, sig, vote, { value: ton("1") });
}
