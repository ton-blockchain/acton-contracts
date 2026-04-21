import "@acton/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/tlb/maybe"
import "@acton/types/transaction"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/Elector"

/// Message format for elected validator set sent to config contract.
struct (0x4e565354) ElectedVSetMsg {
    queryId: uint64
    vset: Cell<VSet>
}

const NOW_CONST = 1667388240 // Expired timestamp matching default data
const ONECOIN: coins = 1000000000

struct ElectorSetup {
    elector: Elector
    configAddr: address
}

/// Default empty storage for elector contract
fun defaultStorage(): Storage {
    return Storage {
        currectElections: null,
        credits: [],
        pastElections: [],
        grams: 0,
        activeId: 0,
        activeHash: 0,
    };
}

/// Create default validators set cell (already expired)
fun defaultValidators(): VSet {
    return VSet {
        utimeSince: NOW_CONST - 1000,
        utimeUntil: NOW_CONST - 100,
        _total: 1,
        _main: 1,
        totalWeight: 0,
        dict: [],
    };
}

/// Default validation times config
fun defaultValidationTimes(): ValidatorConfig {
    return ValidatorConfig {
        electedFor: 10000,
        electionsBeginBefore: 8000,
        electionsEndBefore: 2000,
        stakeHeldFor: 8000,
    };
}

/// Default validator limits config
fun defaultValidatorLimits(): ValidatorLimits {
    return ValidatorLimits {
        maxValidators: 100,
        maxMainValidators: 100,
        minValidators: 5,
    };
}

/// Default stake limits config
fun defaultStakeLimits(): StakeLimits {
    return StakeLimits {
        minStake: 10000 * ONECOIN,
        maxStake: 500000 * ONECOIN,
        minTotalStake: 2000000 * ONECOIN,
        maxStakeFactor: (27 << 16) / 10, // ~2.7
    };
}

/// Deploy elector on masterchain with default config
fun setupElector(): ElectorSetup {
    testing.setNow(NOW_CONST);

    val elector = Elector.fromStorage(defaultStorage(), null, MASTERCHAIN);
    val deployer = testing.treasury("deployer");

    val res = elector.deploy(deployer.address, { value: ton("1000") });
    expect(res).toHaveSuccessfulDeploy({ to: elector.address });

    // Generate a config contract address on masterchain
    val configAddr = randomAddress("config", MASTERCHAIN);

    // Set up blockchain config
    var config = testing.getConfig();

    // Param 1: elector address hash
    val (_, electorHash) = elector.address.getWorkchainAndHash();
    config.setParamRaw(1, beginCell().storeUint(electorHash, 256).endCell());

    // Param 0: config contract address hash
    val (_, configHash) = configAddr.getWorkchainAndHash();
    config.setParamRaw(0, beginCell().storeUint(configHash, 256).endCell());

    // Param 15: validation times
    config.setParamRaw(15, defaultValidationTimes().toCell());

    // Param 16: validator limits
    config.setParamRaw(16, defaultValidatorLimits().toCell());

    // Param 17: stake limits
    config.setParamRaw(17, defaultStakeLimits().toCell());

    // Param 34: current validator set (expired)
    config.setParamRaw(34, defaultValidators().toCell());

    testing.setConfig(config);

    return ElectorSetup { elector, configAddr };
}

/// Run tick-tock to announce elections
fun announceElections(elector: Elector): SendResultList {
    return testing.runTickTock(elector.address, true);
}

/// Get active election ID via participant_list_extended
fun Elector.activeElectionId(self): int {
    val (
        electAt,
        _,
        _,
        _,
        _,
        _,
        _,
    ) = self.participantListExtended();
    return electAt;
}

/// Generate a valid stake signature
fun generateStakeSignature(
    privateKey: int,
    stakeAt: uint32,
    maxFactor: uint32,
    srcAddr: uint256,
    adnlAddr: uint256,
): bits512 {
    val dataCell = StakeSubmit { stakeAt, maxFactor, srcAddr, adnlAddr }.toCell();
    var sig = crypto.sign(privateKey, dataCell);
    return sig.loadBits(512) as bits512;
}

/// Submit a valid stake from a random masterchain address.
/// Returns (result, srcAddr, stakeAt, pubkey, stakeAmount).
/// If customStake > 0, uses that amount; otherwise computes minimum valid stake.
// fmt-ignore
fun submitValidStake(elector: Elector, totalStake: coins, customStake: coins = 0): (SendResultList, address, int, uint256, coins) {
    val kp = crypto.generateKeyPair();
    // Use a random address hash as ADNL address (256-bit random value)
    val adnlAddr = randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();

    val stakeLimits = defaultStakeLimits();
    val minStake = max(stakeLimits.minStake, totalStake >> 12);
    val stake: coins = customStake > 0 ? customStake : minStake + ton("1000");

    val stakeAt = elector.activeElectionId();
    assert (stakeAt != 0) throw 999;

    val srcAddr = randomAddress("staker", MASTERCHAIN);
    testing.topUp(srcAddr, stake + ton("100"));

    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val maxFactor: uint32 = (1 << 16) + (1 << 15); // 1.5
    val signature = generateStakeSignature(
        kp.privateKey,
        stakeAt,
        maxFactor,
        srcHash,
        adnlInt,
    );

    val res = elector.sendNewStakeMessage(
        srcAddr,
        0, // queryId
        kp.publicKey,
        stakeAt,
        maxFactor,
        adnlInt,
        signature,
        { value: stake + ONECOIN },
    );

    return (res, srcAddr, stakeAt, kp.publicKey, stake);
}

/// Conduct valid elections by submitting enough stakes and advancing time past close.
/// Needs at least minValidators (5) different validators and minTotalStake (2M TON).
fun conductValidElections(elector: Elector): int {
    val stakeAt = elector.activeElectionId();
    assert (stakeAt != 0) throw 998;

    val validatorLimits = defaultValidatorLimits();
    val stakeLimits = defaultStakeLimits();

    // Submit enough validators to meet both minValidators and minTotalStake.
    // Each validator stakes enough so that minValidators * stakePerValidator >= minTotalStake.
    var totalStake: coins = 0;
    val numValidators = max(validatorLimits.minValidators, 5);
    val stakePerValidator: coins = stakeLimits.minTotalStake / numValidators + ton("10000");
    var i = 0;
    while (i < numValidators) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
        totalStake += stake;
        i += 1;
    }

    // Get elections close time and advance past it
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

    // Run tick-tock to conduct elections
    testing.runTickTock(elector.address, true);

    return stakeAt;
}

/// Create a test Complaint struct with placeholder fields (createdAt, rewardAddr, paid are overwritten by contract)
fun createComplaint(
    validatorPubkey: uint256,
    suggestedFine: coins,
    suggestedFinePart: uint32,
): Complaint {
    return Complaint {
        validatorPubkey,
        description: beginCell().storeUint(0xDEAD, 32).endCell(),
        createdAt: 0,
        severity: 0,
        rewardAddr: 0,
        paid: 0,
        suggestedFine,
        suggestedFinePart,
    };
}

/// Submit a known validator stake. Call BEFORE conductValidElections.
// fmt-ignore
fun submitKnownValidatorStake(elector: Elector, _totalStake: coins, kp: KeyPair): (address, uint256, coins) {
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    val stakeAt = elector.activeElectionId();
    assert (stakeAt != 0) throw 999;

    val srcAddr = randomAddress("known-staker", MASTERCHAIN);
    testing.topUp(srcAddr, stakePerValidator + ton("100"));

    val (_, srcHash) = srcAddr.getWorkchainAndHash();
    val adnlAddr: uint256 = 12345;

    val maxFactor: uint32 = (1 << 16) + (1 << 15); // 1.5
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

/// Conduct elections with a known first validator.
/// Returns (stakeAt, knownPubkey) where knownPubkey is in the frozen dict.
fun conductElectionsWithKnownValidator(elector: Elector): (int, uint256) {
    val kp = crypto.generateKeyPair();
    val stakeAt = elector.activeElectionId();

    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");

    val (_, knownPubkey, knownStake) = submitKnownValidatorStake(elector, 0, kp);
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
    testing.runTickTock(elector.address, true);

    return (stakeAt, knownPubkey);
}

/// Build a validators set cell from parameters
fun buildVSet(validSince: int, validUntil: int, total: int, main: int, totalWeight: int): VSet {
    return VSet {
        utimeSince: validSince,
        utimeUntil: validUntil,
        _total: total,
        _main: min(main, total),
        totalWeight: totalWeight as uint64,
        dict: [],
    };
}

/// Conduct elections and extract the elected vset cell from the outgoing message to config.
fun conductElectionsAndGetVset(elector: Elector, configAddr: address): (int, cell, uint256) {
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
        val (_, srcAddr, _, _, stake) = submitValidStake(elector, totalStake, stakePerValidator);
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

/// Install vset → promote → unfreeze.
fun doInstallPromoteUnfreeze(elector: Elector, vsetCell: cell) {
    val stakeHeld = defaultValidationTimes().stakeHeldFor;

    var cfg = testing.getConfig();
    cfg.setParamRaw(34, vsetCell);
    testing.setConfig(cfg);
    testing.runTickTock(elector.address, true);

    val newVset = buildVSet(blockchain.now(), blockchain.now() + 10000, 1, 1, 0);
    cfg = testing.getConfig();
    cfg.setParamRaw(34, newVset.toCell());
    cfg.setParamRaw(36, newVset.toCell());
    testing.setConfig(cfg);

    val promoteTime = blockchain.now() + 100;
    testing.setNow(promoteTime);
    testing.runTickTock(elector.address, true);

    testing.setNow(promoteTime + stakeHeld + 1);
    testing.runTickTock(elector.address, true);
}

/// Set expired vset and announce new elections.
fun prepareNextRound(elector: Elector) {
    val now = blockchain.now();
    val expiredVset = buildVSet(now - 1000, now - 100, 1, 1, 0);
    var cfg = testing.getConfig();
    cfg.setParamRaw(34, expiredVset.toCell());
    cfg.delete(36);
    testing.setConfig(cfg);
    testing.runTickTock(elector.address, true);
}
