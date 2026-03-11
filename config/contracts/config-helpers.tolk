import "@stdlib/exotic-cells"
import "@stdlib/gas-payments"
import "@stdlib/tvm-lowlevel"
import "errors"
import "messages"
import "storage"
import "types"

fun setConfParam(index: int, value: cell) {
    var storage = lazy Storage.load();
    storage.setConfigParam(index, value);
    storage.save();
}

fun getVoteConfigInternal(critical: bool, cparam11: cell): ConfigProposalSetup {
    val setup = ConfigVotingSetup.fromCell(
        cparam11,
        { throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS },
    );
    return setup.selectProposalSetup(critical);
}

fun getVoteConfig(critical: bool): ConfigProposalSetup {
    val cparam11 = blockchain.configParam(CONFIG_PARAM_VOTING_SETUP);
    assert (cparam11 != null) throw ERROR_INVALID_PROPOSAL_STATUS;
    return getVoteConfigInternal(critical, cparam11!);
}

struct ValidatorSetWindow {
    utimeSince: int
    utimeUntil: int
}

fun checkValidatorSet(validatorSet: cell): ValidatorSetWindow {
    val parsed = ValidatorSetExt.fromCell(
        validatorSet,
        { throwIfOpcodeDoesNotMatch: ERROR_INVALID_VALIDATOR_SET },
    );

    assert (parsed.main > 0) throw ERROR_INVALID_VALIDATOR_SET;
    assert (parsed.total >= parsed.main) throw ERROR_INVALID_VALIDATOR_SET;

    return { utimeSince: parsed.utimeSince, utimeUntil: parsed.utimeUntil };
}

fun sendAnswer(addr: address, queryId: uint64, ansTag: int, mode: int) {
    val ansTag32 = (ansTag & 0xffffffff) as uint32;
    val answerMsg = createMessage({
        bounce: true,
        dest: addr,
        value: 0,
        body: AnswerBody {
            ansTag: ansTag32,
            queryId,
        },
    });
    answerMsg.send(mode);
}

fun sendConfirmation(addr: address, queryId: uint64, ansTag: int) {
    sendAnswer(addr, queryId, ansTag, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun sendError(addr: address, queryId: uint64, ansTag: int) {
    sendAnswer(addr, queryId, ansTag, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun buildMasterchainAddress(addressHash: uint256): address {
    return beginCell()
        .storeUint(4, 3)
        .storeInt(MASTERCHAIN, 8)
        .storeUint(addressHash, 256)
        .toSlice() as address;
}

fun changeElectorCode(codeBody: slice) {
    val electorParam = blockchain.configParam(CONFIG_PARAM_ELECTOR_ADDRESS);
    assert (electorParam != null) throw ERROR_INVALID_MESSAGE;

    val electorAddrHash = electorParam!.beginParse().preloadUint(256);
    val queryId = blockchain.now() as uint64;

    val actionMsg = createMessage({
        bounce: true,
        dest: buildMasterchainAddress(electorAddrHash),
        value: MIN_INTERNAL_MESSAGE_VALUE,
        body: ElectorCodeChangeAction {
            queryId,
            payload: codeBody,
        },
    });
    actionMsg.send(SEND_MODE_REGULAR);
}

@method_id(1666)
fun afterCodeUpgrade(param: slice, oldCode: continuation) {}

fun applyCodeUpgrade(newCode: cell, upgradeParams: slice) {
    contract.setCodePostponed(newCode);
    val oldCode = getTvmRegisterC3();
    setTvmRegisterC3(transformSliceToContinuation(newCode.beginParse()));
    afterCodeUpgrade(upgradeParams, oldCode);
    throw 0;
}

struct CurrentValidatorSetInfo {
    vset: cell
    totalWeight: int
    validators: map<uint16, slice>
}

fun getCurrentValidatorSet(): CurrentValidatorSetInfo {
    val vset = blockchain.configParam(CONFIG_PARAM_CURRENT_VALIDATOR_SET);
    assert (vset != null) throw ERROR_WRONG_CURRENT_VSET;

    val parsed = ValidatorSetExt.fromCell(
        vset!,
        { throwIfOpcodeDoesNotMatch: ERROR_WRONG_CURRENT_VSET },
    );
    val validators = createMapFromLowLevelDict<uint16, slice>(parsed.validators);
    return CurrentValidatorSetInfo {
        vset: vset!,
        totalWeight: parsed.totalWeight,
        validators,
    };
}

fun getValidatorDescription(idx: uint16): slice {
    val currentValidatorSet = getCurrentValidatorSet();
    val lookup = currentValidatorSet.validators.get(idx);

    assert (lookup.isFound) throw ERROR_WRONG_VALIDATOR_DESCRIPTION;

    return lookup.loadValue();
}

struct ValidatorKeyAndWeight {
    publicKey: int
    weight: int
}

fun unpackValidatorDescr(vdescr: slice): ValidatorKeyAndWeight {
    val descr = lazy ValidatorDescr.fromSlice(
        vdescr,
        { throwIfOpcodeDoesNotMatch: ERROR_WRONG_VALIDATOR_DESCRIPTION },
    );

    match (descr) {
        ValidatorDescrSimple => {
            assert (descr.pubkeyTag == OP_ED25519_PUBKEY) throw ERROR_WRONG_VALIDATOR_DESCRIPTION;
            return { publicKey: descr.publicKey, weight: descr.weight };
        }
        ValidatorDescrWithAdnl => {
            assert (descr.pubkeyTag == OP_ED25519_PUBKEY) throw ERROR_WRONG_VALIDATOR_DESCRIPTION;
            return { publicKey: descr.publicKey, weight: descr.weight };
        }
        else => throw ERROR_WRONG_VALIDATOR_DESCRIPTION,
    }
}

struct ProposalAcceptanceResult {
    cfgDict: ConfigDict
    paramId: int
    paramVal: cell?
}

@inline_ref
fun acceptProposal(
    mutate cfgDict: ConfigDict,
    proposalCell: Cell<ConfigProposal>,
    critical: bool,
): ProposalAcceptanceResult {
    val proposal = proposalCell.load();
    val paramId32 = proposal.paramId;
    val paramId = paramId32 as int;

    val currentValue = cfgDict.getById(paramId);
    val currentHash = currentValue == null ? 0 : (currentValue!.hash() as int);

    if (proposal.ifHashEqual != null && currentHash != proposal.ifHashEqual!) {
        return {
            cfgDict,
            paramId: 0,
            paramVal: null,
        };
    }

    if (paramId == CUSTOM_PARAM_1 || paramId == CUSTOM_PARAM_2) {
        return {
            cfgDict,
            paramId: 0,
            paramVal: null,
        };
    }

    val mandatoryParamsCell = cfgDict.getById(CONFIG_PARAM_MANDATORY_PARAMS);
    if (mandatoryParamsCell != null && proposal.paramValue == null) {
        val mandatoryParams = createMapFromLowLevelDict<int32, slice>(mandatoryParamsCell!);
        if (mandatoryParams.exists(paramId32)) {
            return {
                cfgDict,
                paramId: 0,
                paramVal: null,
            };
        }
    }

    val criticalParamsCell = cfgDict.getById(CONFIG_PARAM_CRITICAL_PARAMS);
    if (criticalParamsCell != null) {
        val criticalParams = createMapFromLowLevelDict<int32, slice>(criticalParamsCell!);
        if (criticalParams.exists(paramId32) && !critical) {
            return {
                cfgDict,
                paramId: 0,
                paramVal: null,
            };
        }
    }

    if (proposal.paramValue == null) {
        cfgDict.delete(paramId32);
    } else {
        cfgDict.set(paramId32, proposal.paramValue!);
    }

    return {
        cfgDict,
        paramId,
        paramVal: proposal.paramValue,
    };
}

@inline_ref
fun performProposedAction(publicKey: int, paramId: int, paramVal: cell?): uint256 {
    if (paramId == -999) {
        return paramVal == null ? 0 : paramVal!.beginParse().preloadUint(256);
    }

    if (paramVal == null) {
        return publicKey;
    }

    if (paramId == -1000) {
        var cs = paramVal!.beginParse();
        val newCode = cs.loadRef();
        applyCodeUpgrade(newCode, cs);
    }

    if (paramId == -1001) {
        changeElectorCode(paramVal!.beginParse());
    }

    return publicKey;
}

@inline_ref
fun updateProposalStatus(
    status: ConfigProposalStatus,
    previousWeightRemaining: int,
): ConfigProposalStatus? {
    val voteCfg = getVoteConfig(status.isCritical);
    var roundsRemaining = status.roundsRemaining as int;
    val wins = status.wins as int;
    var losses = status.losses as int;

    if (previousWeightRemaining >= 0) {
        losses += 1;
    }
    if (losses > voteCfg.maxLosses) {
        return null;
    }

    roundsRemaining -= 1;
    if (roundsRemaining < 0) {
        return null;
    }

    return ConfigProposalStatus {
        expires: status.expires,
        proposal: status.proposal,
        isCritical: status.isCritical,
        voters: status.voters,
        remainingWeight: status.remainingWeight,
        validatorSetId: status.validatorSetId,
        roundsRemaining: roundsRemaining as uint8,
        wins: wins as uint8,
        losses: losses as uint8,
    };
}

struct VoteRegistrationResult {
    acceptedProposal: Cell<ConfigProposal>?
    status: int
}

@inline_ref
fun registerVote(
    mutate voteDict: VoteDict,
    proposalHash: uint256,
    idx: uint16,
    weight: int,
): VoteRegistrationResult {
    val statusLookup = voteDict.get(proposalHash);

    if (!statusLookup.isFound) {
        return { acceptedProposal: null, status: -1 };
    }

    val currentValidatorSet = getCurrentValidatorSet();
    val curVsetId = currentValidatorSet.vset.hash();

    var status = ConfigProposalStatus.fromSlice(
        statusLookup.loadValue(),
        { throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS },
    );

    if (status.expires <= blockchain.now()) {
        voteDict.delete(proposalHash);
        return { acceptedProposal: null, status: -1 };
    }

    if (status.validatorSetId != curVsetId) {
        val updated = updateProposalStatus(status, status.remainingWeight);
        if (updated == null) {
            voteDict.delete(proposalHash);
            return { acceptedProposal: null, status: -1 };
        }

        status = updated!;
        status.validatorSetId = curVsetId;
        status.voters = [];
        status.remainingWeight = mulDivFloor(
            currentValidatorSet.totalWeight,
            VOTE_WEIGHT_THRESHOLD_NUMERATOR,
            VOTE_WEIGHT_THRESHOLD_DENOMINATOR,
        );
    }

    if (status.voters.exists(idx)) {
        return { acceptedProposal: null, status: -2 };
    }

    status.voters.set(idx, blockchain.now() as uint32);

    val oldWeightRemaining = status.remainingWeight;
    status.remainingWeight -= weight;
    if ((status.remainingWeight ^ oldWeightRemaining) >= 0) {
        voteDict.set(proposalHash, status.toCell().beginParse());
        return { acceptedProposal: null, status: 2 };
    }

    val voteCfg = getVoteConfig(status.isCritical);
    var wins = status.wins as int;
    wins += 1;

    if (wins >= voteCfg.minWins) {
        voteDict.delete(proposalHash);
        return { acceptedProposal: status.proposal, status: status.isCritical ? 7 : 6 };
    }

    status.wins = wins as uint8;
    voteDict.set(proposalHash, status.toCell().beginParse());
    return { acceptedProposal: null, status: 2 };
}

fun Storage.incrementSeqno(mutate self) {
    self.storedSeqno = ((self.storedSeqno + 1) % EXTERNAL_SEQNO_MODULO);
}

@inline_ref
fun proceedRegisterVote(proposalHash: uint256, idx: uint16, weight: int): int {
    var storage = lazy Storage.load();
    var voteDict = storage.voteDict;
    var acceptedProposal: Cell<ConfigProposal>? = null;
    var status = 0;

    val voteRegistration = registerVote(mutate voteDict, proposalHash, idx, weight);

    acceptedProposal = voteRegistration.acceptedProposal;
    status = voteRegistration.status;
    storage.voteDict = voteDict;

    storage.save();

    if (acceptedProposal != null) {
        val critical = status == 7;

        var configDict = storage.config;
        var paramId = 0;
        var paramVal: cell? = null;

        val proposalAcceptance = acceptProposal(mutate configDict, acceptedProposal!, critical);
        configDict = proposalAcceptance.cfgDict;
        paramId = proposalAcceptance.paramId;
        paramVal = proposalAcceptance.paramVal;

        storage.config = configDict;
        storage.save();

        // TODO: ?
        if (paramId != 0) {
            commitContractDataAndActions();

            val publicKey = performProposedAction(storage.publicKey, paramId, paramVal);

            storage.publicKey = publicKey;
            storage.save();
        }
    }

    return status;
}

struct ProposalScanResult {
    proposalStatusSlice: slice?
    changed: bool
}

@inline_ref
fun scanProposal(statusSlice: slice): ProposalScanResult {
    val currentValidatorSet = getCurrentValidatorSet();
    val curVsetId = currentValidatorSet.vset.hash();

    var status = ConfigProposalStatus.fromSlice(
        statusSlice,
        { throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS },
    );

    if (status.expires <= blockchain.now()) {
        return { proposalStatusSlice: null, changed: true };
    }

    if (status.validatorSetId == curVsetId) {
        return { proposalStatusSlice: statusSlice, changed: false };
    }

    val updated = updateProposalStatus(status, status.remainingWeight);
    if (updated == null) {
        return { proposalStatusSlice: null, changed: true };
    }

    status = updated!;
    status.validatorSetId = curVsetId;
    status.voters = [];
    status.remainingWeight = mulDivFloor(
        currentValidatorSet.totalWeight,
        VOTE_WEIGHT_THRESHOLD_NUMERATOR,
        VOTE_WEIGHT_THRESHOLD_DENOMINATOR,
    );

    // TODO: ?
    return { proposalStatusSlice: status.toCell().beginParse(), changed: true };
}

fun scanRandomProposal(mutate voteDict: VoteDict) {
    if (voteDict.isEmpty()) {
        return;
    }

    val entry = voteDict.findKeyGreaterOrEqual(random.uint256());
    if (!entry.isFound) {
        return;
    }

    val proposalHash = entry.getKey();

    var proposalStatusSlice: slice? = null;
    var changed = false;

    val scanResult = scanProposal(entry.loadValue());

    proposalStatusSlice = scanResult.proposalStatusSlice;
    changed = scanResult.changed;

    if (changed) {
        if (proposalStatusSlice == null) {
            voteDict.delete(proposalHash);
        } else {
            voteDict.set(proposalHash, proposalStatusSlice!);
        }
    }
}

@inline_ref
fun registerVotingProposal(msg: NewVotingProposalRequest, msgValue: coins): int {
    var expireAt = msg.expireAt as int;
    if ((expireAt >> 30) != 0) {
        expireAt -= blockchain.now();
    }

    val proposal = msg.proposal.load();
    val paramId = proposal.paramId as int;
    val paramId32 = proposal.paramId;

    if (paramId == CUSTOM_PARAM_1 || paramId == CUSTOM_PARAM_2) {
        return ERROR_TAG_CUSTOM_SLOT_VOTING_REJECTED;
    }

    var expectedHash = proposal.ifHashEqual == null ? -1 : (proposal.ifHashEqual! as int);
    if (expectedHash >= 0) {
        val curVal = blockchain.configParam(paramId);
        val curHash = curVal == null ? 0 : (curVal!.hash() as int);
        if (curHash != expectedHash) {
            expectedHash = ERROR_TAG_BAD_CURRENT_VALUE_HASH;
        }
    } else {
        val mandatoryParams = blockchain.configParam(CONFIG_PARAM_MANDATORY_PARAMS);
        if (mandatoryParams != null) {
            val mandatoryMap = createMapFromLowLevelDict<int32, slice>(mandatoryParams!);
            if (mandatoryMap.exists(paramId32)) {
                expectedHash = ERROR_TAG_MANDATORY_PARAM_CANNOT_BE_NULL;
            }
        }
    }

    if (proposal.paramValue != null && proposal.paramValue!.depth() >= 256) {
        expectedHash = ERROR_TAG_BAD_VALUE;
    }
    if (expectedHash < -1) {
        return expectedHash;
    }

    if (!msg.critical) {
        val criticalParams = blockchain.configParam(CONFIG_PARAM_CRITICAL_PARAMS);
        if (criticalParams != null) {
            val criticalMap = createMapFromLowLevelDict<int32, slice>(criticalParams!);
            if (criticalMap.exists(paramId32)) {
                expectedHash = ERROR_TAG_CRITICAL_FLAG_REQUIRED;
            }
        }
    }
    if (expectedHash < -1) {
        return expectedHash;
    }

    val voteCfg = getVoteConfig(msg.critical);
    if (expireAt < voteCfg.minStoreSec) {
        return ERROR_TAG_PROPOSAL_EXPIRED;
    }
    expireAt = min(expireAt, voteCfg.maxStoreSec);

    var bits = 0;
    var refs = 0;
    if (proposal.paramValue != null) {
        (_, bits, refs) = proposal.paramValue!.calculateSizeStrict(PROPOSAL_BITS_OVERHEAD);
    }

    val pricePerSecond = voteCfg.calculateStoragePrice(1, bits, refs);
    var price = pricePerSecond * expireAt;
    expireAt += blockchain.now();

    var storage = lazy Storage.load();
    var voteDict = storage.voteDict;
    val proposalHash = msg.proposal.hash();
    val existing = voteDict.get(proposalHash);

    if (existing.isFound) {
        var status = ConfigProposalStatus.fromSlice(
            existing.loadValue(),
            { throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS },
        );

        if (status.isCritical != msg.critical) {
            return ERROR_TAG_CANNOT_DOWNGRADE_CRITICALITY;
        }
        if (status.expires >= expireAt) {
            return ERROR_TAG_PROPOSAL_ALREADY_EXISTS;
        }

        price = pricePerSecond * (expireAt - status.expires + PROPOSAL_EXTENSION_GRACE_PERIOD);
        if (msgValue - price < MIN_INTERNAL_MESSAGE_VALUE) {
            return ERROR_TAG_NOT_ENOUGH_FUNDS;
        }

        status.expires = expireAt as uint32;
        voteDict.set(proposalHash, status.toCell().beginParse());

        storage.voteDict = voteDict;
        storage.save();
        return price;
    }

    if (msgValue - price < MIN_INTERNAL_MESSAGE_VALUE) {
        return ERROR_TAG_NOT_ENOUGH_FUNDS;
    }

    val currentValidatorSet = getCurrentValidatorSet();
    val weightRemaining = mulDivFloor(
        currentValidatorSet.totalWeight,
        VOTE_WEIGHT_THRESHOLD_NUMERATOR,
        VOTE_WEIGHT_THRESHOLD_DENOMINATOR,
    );

    voteDict.set(
        proposalHash,
        ConfigProposalStatus {
            expires: expireAt as uint32,
            proposal: msg.proposal,
            isCritical: msg.critical,
            voters: [],
            remainingWeight: weightRemaining as int64,
            validatorSetId: currentValidatorSet.vset.hash(),
            roundsRemaining: voteCfg.maxTotalRounds,
            wins: 0,
            losses: 0,
        }.toCell()
            .beginParse(),
    );

    storage.voteDict = voteDict;
    storage.save();
    return price;
}
