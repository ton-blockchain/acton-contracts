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
import "../wrappers/utils"

const ELECTOR_E2E_COMPLAINT_FINE: coins = ton("100")
const ELECTOR_E2E_COMPLAINT_FINE_PART: uint32 = 1 << 30
const ELECTOR_E2E_KNOWN_VALIDATOR_COUNT = 5

struct ElectorE2eContext {
    elector: Elector
    configAddr: address
}

struct ElectorE2eElected {
    ctx: ElectorE2eContext
    stakeAt: int
    knownPubkey: uint256
    vsetCell: cell
}

struct ElectorE2eVoting {
    elected: ElectorE2eElected
    kps: array<KeyPair>
    chash: uint256
}

fun deployElectorStage(): ElectorE2eContext {
    val setup = setupElector();
    expect(setup.elector.activeElectionId()).toEqual(0);
    return ElectorE2eContext {
        elector: setup.elector,
        configAddr: setup.configAddr,
    };
}

fun announceElectionsStage(ctx: ElectorE2eContext): ElectorE2eContext {
    announceElections(ctx.elector);
    expect(ctx.elector.activeElectionId()).toNotEqual(0);
    return ctx;
}

fun submitStakeStage(ctx: ElectorE2eContext): ElectorE2eContext {
    val (_, _, _, pubkey, stake) = submitValidStake(ctx.elector, 0);
    expect(ctx.elector.participatesIn(pubkey)).toEqual(stake);
    return ctx;
}

fun conductElectionsStage(ctx: ElectorE2eContext): ElectorE2eElected {
    val kp = crypto.generateKeyPair();
    val stakeAt = ctx.elector.activeElectionId();

    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    val (_, knownPubkey, knownStake) = submitKnownValidatorStake(ctx.elector, 0, kp);
    var totalStake = knownStake;

    var i = 0;
    while (i < 4) {
        val (_, _, _, _, stake) = submitValidStake(ctx.elector, totalStake, stakePerValidator);
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
    ) = ctx.elector.participantListExtended();
    testing.setNow(closeAt + 1);
    val tickResult = testing.runTickTock(ctx.elector.address, true);

    val (
        _,
        _,
        _,
        _,
        _,
        _,
        isFinished,
    ) = ctx.elector.participantListExtended();
    expect(isFinished).toEqual(true);

    val tx = tickResult.findTransaction<ElectedVSetMsg>({
        from: ctx.elector.address,
        to: ctx.configAddr,
    });
    val vsetCell = tx!.loadBody<ElectedVSetMsg>().vset;

    return ElectorE2eElected { ctx, stakeAt, knownPubkey, vsetCell };
}

fun installVsetStage(elected: ElectorE2eElected): ElectorE2eElected {
    var config = testing.getConfig();
    config.setParamRaw(34, elected.vsetCell);
    testing.setConfig(config);

    testing.runTickTock(elected.ctx.elector.address, true);

    expect(elected.ctx.elector.activeElectionId()).toEqual(0);
    return elected;
}

fun registerComplaintStage(elected: ElectorE2eElected): ElectorE2eVoting {
    val kps = setupVsetWithKnownValidators(ELECTOR_E2E_KNOWN_VALIDATOR_COUNT);
    val complaint = createComplaint(
        elected.knownPubkey,
        ELECTOR_E2E_COMPLAINT_FINE,
        ELECTOR_E2E_COMPLAINT_FINE_PART,
    );
    val sender = randomAddress("complainer", MASTERCHAIN);
    testing.topUp(sender, ton("1000"));
    elected
        .ctx
        .elector
        .sendNewComplaint(sender, 1, elected.stakeAt, complaint, { value: ton("500") });

    val complaints = elected.ctx.elector.getPastComplaints(elected.stakeAt);
    val first = complaints.findFirst();
    assert (first.isFound) throw 500;
    return ElectorE2eVoting {
        elected,
        kps,
        chash: first.getKey(),
    };
}

fun completeVotingStage(voting: ElectorE2eVoting) {
    // 4 votes (each weight 100) reach 2/3 of totalWeight=500 → mulDivFloor(500,2,3)=333
    var i = 1;
    while (i <= 4) {
        sendVote(
            voting.elected.ctx.elector,
            i,
            voting.kps.get(i).privateKey,
            i,
            voting.elected.stakeAt,
            voting.chash,
        );
        i += 1;
    }

    val info = voting.elected.ctx.elector.showComplaint(voting.elected.stakeAt, voting.chash);
    assert (info != null) throw 700;
    expect(info.weightRemaining < 0).toEqual(true);
}

get fun `test elector e2e bench: stage 1 deploy elector`() {
    deployElectorStage();
}

get fun `test elector e2e bench: stage 2 announce elections`() {
    val ctx = deployElectorStage();
    announceElectionsStage(ctx);
}

get fun `test elector e2e bench: stage 3 submit stake`() {
    var ctx = deployElectorStage();
    ctx = announceElectionsStage(ctx);
    submitStakeStage(ctx);
}

get fun `test elector e2e bench: stage 4 conduct elections`() {
    var ctx = deployElectorStage();
    ctx = announceElectionsStage(ctx);
    conductElectionsStage(ctx);
}

get fun `test elector e2e bench: stage 5 install vset`() {
    var ctx = deployElectorStage();
    ctx = announceElectionsStage(ctx);
    val elected = conductElectionsStage(ctx);
    installVsetStage(elected);
}

get fun `test elector e2e bench: stage 6 register complaint`() {
    var ctx = deployElectorStage();
    ctx = announceElectionsStage(ctx);
    var elected = conductElectionsStage(ctx);
    elected = installVsetStage(elected);
    registerComplaintStage(elected);
}

get fun `test elector e2e bench: stage 7 complete voting`() {
    var ctx = deployElectorStage();
    ctx = announceElectionsStage(ctx);
    var elected = conductElectionsStage(ctx);
    elected = installVsetStage(elected);
    val voting = registerComplaintStage(elected);
    completeVotingStage(voting);
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
    var config = testing.getConfig();
    config.setParamRaw(34, vset.toCell());
    testing.setConfig(config);
    return kps;
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
