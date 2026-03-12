type CreditsMap = map<uint256, coins>;

struct Storage {
    currectElections: Cell<Elections>?;
    credits: CreditsMap;
    pastElections: map<uint32, PastElection>;
    grams: coins;
    activeId: uint32;
    activeHash: uint256;
}

fun Storage.load(): Storage {
    return Storage.fromCell(contract.getData());
}

fun Storage.save(self): void {
    contract.setData(self.toCell());
}

struct MemberParams {
    msgValue: coins;
    timestamp: uint32;
    maxFactor: uint32;
    srcAddr: uint256;
    adnlAddr: uint256;
}

struct Elections {
    electionsAt: uint32;
    electionsCloseAt: uint32;
    minStake: coins;
    totalStake: coins;
    members: map<uint256, MemberParams>;
    isFailed: bool;
    isFinished: bool;
}

struct ValidatorInRound {
    addr: uint256;
    weight: uint64;
    stake: coins;
    isBanned: bool;
}

type FrozenDict = map<uint256, ValidatorInRound>;
type Complaints = map<uint256, ComplaintStatus>

struct PastElection {
    unfreezeAt: uint32;
    stakeHeld: uint32;
    vsetHash: uint256;
    frozenDict: FrozenDict;
    totalStake: coins;
    bonuses: coins;
    complaints: Complaints;
}

struct(0x2d) ComplaintStatus {
    complaint: Cell<Complaint>;
    // id -> timestamp
    voters: map<uint16, uint32>;
    vsetId: uint256;
    weightRemaining: int64;
}

// TODO not sure about this opcode
struct(0xbc) Complaint {
    validatorPubkey: uint256;
    description: cell;
    createdAt: uint32;
    severity: uint8;
    rewardAddr: uint256;
    paid: coins;
    suggestedFine: coins;
    suggestedFinePart: uint32;
}

struct(0x1a) ComplaintPrices {
    deposit: coins;
    bitPrice: coins;
    cellPrice: coins;
}

fun getComplaintPrices(): ComplaintPrices {
    val info = blockchain.configParam(13);
    if (info == null) {
        return ComplaintPrices {
            deposit: 1 << 36,
            bitPrice: 1,
            cellPrice: 512,
        }
    }
    return ComplaintPrices.fromCell(info);
}

// Config param 16
struct ValidatorLimits {
    maxValidators: uint16;
    maxMainValidators: uint16;
    minValidators: uint16;
}

fun getValidatorLimits(): ValidatorLimits {
    // SAFETY: This param can't be null
    val raw = blockchain.configParam(16)!;
    return ValidatorLimits.fromCell(raw);
}

// Config param 17
struct StakeLimits {
    minStake: coins;
    maxStake: coins;
    minTotalStake: coins;
    maxStakeFactor: uint32;
}

fun getStakeLimits(): StakeLimits {
    // SAFETY: This param can't be null
    val raw = blockchain.configParam(17)!;
    return StakeLimits.fromCell(raw);
}

struct ValidatorConfig {
    electedFor: uint32;
    electionsBeginBefore: uint32;
    electionsEndBefore: uint32;
    stakeHeldFor: uint32;
}

fun getValidatorConf(): ValidatorConfig {
    // SAFETY: This param can't be null
    val rawConf = blockchain.configParam(15)!;
    return ValidatorConfig.fromCell(rawConf);
}

// Validator set
struct(0x12) VSet {
    utimeSince: uint32;
    utimeUntil: uint32;
    // These fields are not used
    _total: uint16;
    _main: uint16;
    totalWeight: uint64;
    dict: map<uint16, AnyValidatorDescr>;
}

fun getCurrentVset(): (cell, VSet) {
    // SAFETY: This param can't be null
    val vset = blockchain.configParam(34)!;
    return (vset, VSet.fromCell(vset));
}

// validator#53 public_key:SigPubKey weight:uint64 = ValidatorDescr;
// validator_addr#73 public_key:SigPubKey weight:uint64 adnl_addr:bits256 = ValidatorDescr;
// ed25519_pubkey#8e81278a pubkey:bits256 = SigPubKey;
struct(0x538e81278a) ValidatorDescr {
    validatorPubkey: uint256;
    validatorWeight: uint64;
}

struct(0x738e81278a) ValidatorDescrWithAdnlAddr {
    validatorPubkey: uint256;
    validatorWeight: uint64;
    adnlAddr: uint256;
}

type AnyValidatorDescr = ValidatorDescr | ValidatorDescrWithAdnlAddr;

struct ExtendedValidatorDescr {
    totalWeight: uint64;
    this: ValidatorDescr;
}

fun getValidatorDescr(idx: int): ExtendedValidatorDescr {
    val (_, vset) = getCurrentVset();
    val res = vset.dict.get(idx);
    // Assume, that the value is always found

    val thisDescr = res.loadValue();
    match (thisDescr) {
        ValidatorDescr => {
            return ExtendedValidatorDescr {
                totalWeight: vset.totalWeight,
                this: thisDescr,
            }
        }
        ValidatorDescrWithAdnlAddr => {
            return ExtendedValidatorDescr {
                totalWeight: vset.totalWeight,
                this: ValidatorDescr {
                    validatorPubkey: thisDescr.validatorPubkey,
                    validatorWeight: thisDescr.validatorWeight,
                },
            }
        }
    }
}


struct ReturnMsg {
    op: uint32;
    queryId: uint64;
    reason: uint32;
}

fun ReturnMsg.packToBuilder(self, mutate b: builder) {
    b.storeUint(self.op, 32);
    b.storeUint(self.queryId, 64);
    if (self.reason >= 0) {
        b.storeUint(self.reason, 32);
    }
}

struct(0x654c5074) StakeSubmit {
    stakeAt: uint32;
    maxFactor: uint32;
    srcAddr: uint256;
    adnlAddr: uint256;
}