import "@stdlib/exotic-cells"
import "@stdlib/gas-payments"
import "@stdlib/lisp-lists"
import "@stdlib/tvm-lowlevel"
import "errors"
import "messages"
import "storage"
import "types"

fun setConfParam(index: int32, value: cell) {
    var storage = lazy Storage.load();
    var cfgDict = storage.loadConfigDict();
    cfgDict.set(index, value);
    storage.saveConfigDict(cfgDict);
    storage.save();
}

fun getVoteConfigInternal(critical: bool, cparam11: cell): ConfigProposalSetup {
    val setup = ConfigVotingSetup.fromCell(cparam11, {
        throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS,
    });
    return critical ? setup.criticalParams.load() : setup.normalParams.load();
}

fun getVoteConfig(critical: bool): ConfigProposalSetup {
    val cparam11 = blockchain.configParam(11);
    assert (cparam11 != null) throw ERROR_INVALID_PROPOSAL_STATUS;
    return getVoteConfigInternal(critical, cparam11!);
}

fun checkValidatorSet(vset: cell): (int, int) {
    val parsed = ValidatorSetExt.fromCell(vset, {
        throwIfOpcodeDoesNotMatch: ERROR_INVALID_VALIDATOR_SET,
    });
    assert (parsed.main > 0) throw ERROR_INVALID_VALIDATOR_SET;
    assert (parsed.total >= parsed.main) throw ERROR_INVALID_VALIDATOR_SET;
    return (parsed.utimeSince, parsed.utimeUntil);
}

fun sendAnswer(addr: address, queryId: uint64, ansTag: int32, mode: int) {
    val ansTagBits = (ansTag as int) & 0xffffffff;
    sendRawMessage(
        beginCell()
            .storeUint(0x18, 6)
            .storeAddress(addr)
            .storeCoins(0)
            .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
            .storeUint(ansTagBits, 32)
            .storeUint(queryId, 64)
            .endCell(),
        mode,
    );
}

fun sendConfirmation(addr: address, queryId: uint64, ansTag: int32) {
    sendAnswer(addr, queryId, ansTag, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun sendError(addr: address, queryId: uint64, ansTag: int32) {
    sendAnswer(addr, queryId, ansTag, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun changeElectorCode(cs: slice) {
    val electorParam = blockchain.configParam(1);
    assert (electorParam != null) throw ERROR_INVALID_MESSAGE;

    val electorAddrHash = electorParam!.beginParse().preloadUint(256);
    val queryId = blockchain.now();

    sendRawMessage(
        beginCell()
            .storeUint(0xc4ff, 17)
            .storeUint(electorAddrHash, 256)
            .storeCoins(1 << 30)
            .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
            .storeUint(OP_ACTION_CHANGE_CONFIG_CODE, 32)
            .storeUint(queryId, 64)
            .storeSlice(cs)
            .endCell(),
        SEND_MODE_REGULAR,
    );
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

@inline_ref
fun performAction(mutate cfgDict: ConfigDict, publicKey: int, action: int, cs: slice): (ConfigDict, int) {
    if (action == OP_ACTION_CHANGE_PARAM) {
        val paramIndex = cs.loadInt(32) as int32;
        val paramValue = cs.loadRef();
        cs.assertEnd();
        cfgDict.set(paramIndex, paramValue);
        return (cfgDict, publicKey);
    }
    if (action == OP_ACTION_CHANGE_CONFIG_CODE) {
        val newCode = cs.loadRef();
        applyCodeUpgrade(newCode, cs);
    }
    if (action == OP_ACTION_CHANGE_MASTER_PUBKEY) {
        val nextPublicKey = cs.loadUint(256);
        cs.assertEnd();
        return (cfgDict, nextPublicKey);
    }
    if (action == OP_ACTION_CHANGE_ELECTOR_CODE) {
        changeElectorCode(cs);
        return (cfgDict, publicKey);
    }
    assert (action == 0) throw ERROR_UNKNOWN_ACTION;
    return (cfgDict, publicKey);
}

fun getCurrentVset(): (cell, int, map<uint16, slice>) {
    val vset = blockchain.configParam(34);
    assert (vset != null) throw ERROR_WRONG_CURRENT_VSET;

    val parsed = ValidatorSetExt.fromCell(vset!, {
        throwIfOpcodeDoesNotMatch: ERROR_WRONG_CURRENT_VSET,
    });
    val validators = createMapFromLowLevelDict<uint16, slice>(parsed.validators);
    return (vset!, parsed.totalWeight, validators);
}

fun getValidatorDescr(idx: uint16): (slice, int) {
    val (_, totalWeight, dict) = getCurrentVset();
    val lookup = dict.get(idx);
    assert (lookup.isFound) throw ERROR_WRONG_VALIDATOR_DESCRIPTION;
    return (lookup.loadValue(), totalWeight);
}

fun unpackValidatorDescr(vdescr: slice): (int, int) {
    val descr = lazy ValidatorDescr.fromSlice(vdescr, {
        throwIfOpcodeDoesNotMatch: ERROR_WRONG_VALIDATOR_DESCRIPTION,
    });

    match (descr) {
        ValidatorDescrSimple => {
            assert (descr.pubkeyTag == OP_ED25519_PUBKEY) throw ERROR_WRONG_VALIDATOR_DESCRIPTION;
            return (descr.publicKey, descr.weight);
        }
        ValidatorDescrWithAdnl => {
            assert (descr.pubkeyTag == OP_ED25519_PUBKEY) throw ERROR_WRONG_VALIDATOR_DESCRIPTION;
            return (descr.publicKey, descr.weight);
        }
        else => throw ERROR_WRONG_VALIDATOR_DESCRIPTION,
    }
}

fun parseConfigProposal(proposalCell: cell): ConfigProposal {
    return ConfigProposal.fromCell(proposalCell, {
        throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS,
    });
}

@inline_ref
fun acceptProposal(mutate cfgDict: ConfigDict, proposalCell: cell, critical: bool): (ConfigDict, int, cell?) {
    val proposal = parseConfigProposal(proposalCell);
    val paramId32 = proposal.paramId;
    val paramId = paramId32 as int;

    var curVal: cell? = null;
    val currentLookup = cfgDict.get(paramId32);
    if (currentLookup.isFound) {
        curVal = currentLookup.loadValue();
    }
    val curHash = curVal == null ? 0 : (curVal!.hash() as int);
    if (proposal.ifHashEqual != null && curHash != proposal.ifHashEqual!) {
        return (cfgDict, 0, null);
    }

    if (paramId == CUSTOM_PARAM_1 || paramId == CUSTOM_PARAM_2) {
        return (cfgDict, 0, null);
    }

    val mandatoryParamsLookup = cfgDict.get(9 as int32);
    if (mandatoryParamsLookup.isFound && proposal.paramValue == null) {
        val mandatoryParams = createMapFromLowLevelDict<int32, slice>(mandatoryParamsLookup.loadValue());
        if (mandatoryParams.exists(paramId32)) {
            return (cfgDict, 0, null);
        }
    }

    val criticalParamsLookup = cfgDict.get(10 as int32);
    if (criticalParamsLookup.isFound) {
        val criticalParams = createMapFromLowLevelDict<int32, slice>(criticalParamsLookup.loadValue());
        if (criticalParams.exists(paramId32) && !critical) {
            return (cfgDict, 0, null);
        }
    }

    if (proposal.paramValue == null) {
        cfgDict.delete(paramId32);
    } else {
        cfgDict.set(paramId32, proposal.paramValue!);
    }

    return (cfgDict, paramId, proposal.paramValue);
}

@inline_ref
fun performProposedAction(mutate cfgDict: ConfigDict, publicKey: int, paramId: int, paramVal: cell?): (ConfigDict, int) {
    if (paramId == -999) {
        return (cfgDict, paramVal == null ? 0 : paramVal!.beginParse().preloadUint(256));
    }
    if (paramVal == null) {
        return (cfgDict, publicKey);
    }
    if (paramId == -1000) {
        var cs = paramVal!.beginParse();
        val newCode = cs.loadRef();
        applyCodeUpgrade(newCode, cs);
    }
    if (paramId == -1001) {
        changeElectorCode(paramVal!.beginParse());
    }
    return (cfgDict, publicKey);
}

@inline_ref
fun updateProposalStatus(status: ConfigProposalStatus, previousWeightRemaining: int): ConfigProposalStatus? {
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

@inline_ref
fun registerVote(mutate voteDict: VoteDict, proposalHash: uint256, idx: uint16, weight: int): (VoteDict, cell?, int) {
    val statusLookup = voteDict.get(proposalHash);
    if (!statusLookup.isFound) {
        return (voteDict, null, -1);
    }

    val (curVset, totalWeight, _) = getCurrentVset();
    val curVsetId = curVset.hash();

    var status = ConfigProposalStatus.fromCell(statusLookup.loadValue(), {
        throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS,
    });
    if (status.expires <= blockchain.now()) {
        voteDict.delete(proposalHash);
        return (voteDict, null, -1);
    }

    if (status.validatorSetId != curVsetId) {
        val updated = updateProposalStatus(status, status.remainingWeight);
        if (updated == null) {
            voteDict.delete(proposalHash);
            return (voteDict, null, -1);
        }
        status = updated!;
        status.validatorSetId = curVsetId;
        status.voters = [];
        status.remainingWeight = mulDivFloor(totalWeight, 3, 4);
    }

    if (status.voters.exists(idx)) {
        return (voteDict, null, -2);
    }

    status.voters.set(idx, blockchain.now() as uint32);

    val oldWeightRemaining = status.remainingWeight;
    status.remainingWeight -= weight;
    if ((status.remainingWeight ^ oldWeightRemaining) >= 0) {
        voteDict.set(proposalHash, status.toCell());
        return (voteDict, null, 2);
    }

    val voteCfg = getVoteConfig(status.isCritical);
    var wins = status.wins as int;
    wins += 1;

    if (wins >= voteCfg.minWins) {
        voteDict.delete(proposalHash);
        return (voteDict, status.proposal, status.isCritical ? 7 : 6);
    }

    status.wins = wins as uint8;
    voteDict.set(proposalHash, status.toCell());
    return (voteDict, null, 2);
}

@inline_ref
fun proceedRegisterVote(proposalHash: uint256, idx: uint16, weight: int): int {
    var storage = lazy Storage.load();
    var voteDict = storage.voteDict;
    var acceptedProposal: cell? = null;
    var status = 0;

    (voteDict, acceptedProposal, status) = registerVote(mutate voteDict, proposalHash, idx, weight);
    storage.voteDict = voteDict;
    storage.save();

    if (acceptedProposal != null) {
        val critical = status == 7;
        var cfgDict = storage.loadConfigDict();
        var paramId = 0;
        var paramVal: cell? = null;
        (cfgDict, paramId, paramVal) = acceptProposal(mutate cfgDict, acceptedProposal!, critical);

        storage.saveConfigDict(cfgDict);
        storage.save();

        if (paramId != 0) {
            commitContractDataAndActions();

            var publicKey = storage.publicKey as int;
            (cfgDict, publicKey) = performProposedAction(mutate cfgDict, publicKey, paramId, paramVal);

            storage.publicKey = publicKey as uint256;
            storage.saveConfigDict(cfgDict);
            storage.save();
        }
    }

    return status;
}

@inline_ref
fun scanProposal(proposalHash: uint256, statusCell: cell): (cell?, bool) {
    val (curVset, totalWeight, _) = getCurrentVset();
    val curVsetId = curVset.hash();

    var status = ConfigProposalStatus.fromCell(statusCell, {
        throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS,
    });
    if (status.expires <= blockchain.now()) {
        return (null, true);
    }
    if (status.validatorSetId == curVsetId) {
        return (statusCell, false);
    }

    val updated = updateProposalStatus(status, status.remainingWeight);
    if (updated == null) {
        return (null, true);
    }
    status = updated!;
    status.validatorSetId = curVsetId;
    status.voters = [];
    status.remainingWeight = mulDivFloor(totalWeight, 3, 4);

    return (status.toCell(), true);
}

fun scanRandomProposal(mutate voteDict: VoteDict): VoteDict {
    if (voteDict.isEmpty()) {
        return voteDict;
    }

    val entry = voteDict.findKeyGreaterOrEqual(random.uint256());
    if (!entry.isFound) {
        return voteDict;
    }

    val proposalHash = entry.getKey();
    var proposalStatusCell: cell? = null;
    var changed = false;
    (proposalStatusCell, changed) = scanProposal(proposalHash, entry.loadValue());

    if (changed) {
        if (proposalStatusCell == null) {
            voteDict.delete(proposalHash);
        } else {
            voteDict.set(proposalHash, proposalStatusCell!);
        }
    }

    return voteDict;
}

@inline_ref
fun registerVotingProposal(msg: NewVotingProposalRequest, msgValue: coins): int {
    var expireAt = msg.expireAt as int;
    if ((expireAt >> 30) != 0) {
        expireAt -= blockchain.now();
    }

    val proposal = parseConfigProposal(msg.proposal);
    val paramId = proposal.paramId as int;
    val paramId32 = proposal.paramId;

    if (paramId == CUSTOM_PARAM_1 || paramId == CUSTOM_PARAM_2) {
        return ERROR_TAG_CUSTOM_SLOT_VOTING_REJECTED;
    }

    var hash = proposal.ifHashEqual == null ? -1 : (proposal.ifHashEqual! as int);
    if (hash >= 0) {
        val curVal = blockchain.configParam(paramId);
        val curHash = curVal == null ? 0 : (curVal!.hash() as int);
        if (curHash != hash) {
            hash = ERROR_TAG_BAD_CURRENT_VALUE_HASH;
        }
    } else {
        val mandatoryParams = blockchain.configParam(9);
        if (mandatoryParams != null) {
            val mandatoryMap = createMapFromLowLevelDict<int32, slice>(mandatoryParams!);
            if (mandatoryMap.exists(paramId32)) {
                hash = ERROR_TAG_MANDATORY_PARAM_CANNOT_BE_NULL;
            }
        }
    }

    if (proposal.paramValue != null && proposal.paramValue!.depth() >= 256) {
        hash = ERROR_TAG_BAD_VALUE;
    }
    if (hash < -1) {
        return hash;
    }

    if (!msg.critical) {
        val criticalParams = blockchain.configParam(10);
        if (criticalParams != null) {
            val criticalMap = createMapFromLowLevelDict<int32, slice>(criticalParams!);
            if (criticalMap.exists(paramId32)) {
                hash = ERROR_TAG_CRITICAL_FLAG_REQUIRED;
            }
        }
    }
    if (hash < -1) {
        return hash;
    }

    val voteCfg = getVoteConfig(msg.critical);
    if (expireAt < voteCfg.minStoreSec) {
        return ERROR_TAG_PROPOSAL_EXPIRED;
    }
    expireAt = min(expireAt, voteCfg.maxStoreSec);

    var bits = 0;
    var refs = 0;
    if (proposal.paramValue != null) {
        (_, bits, refs) = proposal.paramValue!.calculateSizeStrict(1024);
    }

    val pps = voteCfg.bitPrice * (bits + 1024) + voteCfg.cellPrice * (refs + 2);
    var price = pps * expireAt;
    expireAt += blockchain.now();

    var storage = lazy Storage.load();
    var voteDict = storage.voteDict;
    val proposalHash = msg.proposal.hash();
    val existing = voteDict.get(proposalHash);

    if (existing.isFound) {
        var status = ConfigProposalStatus.fromCell(existing.loadValue(), {
            throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS,
        });
        if (status.isCritical != msg.critical) {
            return ERROR_TAG_CANNOT_DOWNGRADE_CRITICALITY;
        }
        if (status.expires >= expireAt) {
            return ERROR_TAG_PROPOSAL_ALREADY_EXISTS;
        }

        price = pps * (expireAt - status.expires + 16384);
        if (msgValue - price < (1 << 30)) {
            return ERROR_TAG_NOT_ENOUGH_FUNDS;
        }

        status.expires = expireAt as uint32;
        voteDict.set(proposalHash, status.toCell());
        storage.voteDict = voteDict;
        storage.save();
        return price;
    }

    if (msgValue - price < (1 << 30)) {
        return ERROR_TAG_NOT_ENOUGH_FUNDS;
    }

    val (vset, totalWeight, _) = getCurrentVset();
    val weightRemaining = mulDivFloor(totalWeight, 3, 4);

    voteDict.set(
        proposalHash,
        ConfigProposalStatus {
            expires: expireAt as uint32,
            proposal: msg.proposal as Cell<ConfigProposal>,
            isCritical: msg.critical,
            voters: [],
            remainingWeight: weightRemaining as int64,
            validatorSetId: vset.hash(),
            roundsRemaining: voteCfg.maxTotalRounds,
            wins: 0,
            losses: 0,
        }.toCell(),
    );

    storage.voteDict = voteDict;
    storage.save();
    return price;
}

fun onInternalMessage(in: InMessage) {
    val isAdminOfCustomParam = in.senderAddress == ADMIN_ADDRESS_FOR_CUSTOM_PARAMS;
    val isValidWorkchain = isAdminOfCustomParam || in.senderAddress.getWorkchain() == MASTERCHAIN;

    if (!isValidWorkchain || in.body.isEmpty()) {
        return;
    }

    val tag = in.body.preloadUint(32);
    if (isAdminOfCustomParam && tag != OP_SET_CUSTOM_PARAM) {
        throw ERROR_INVALID_MESSAGE;
    }

    if (tag == OP_SET_NEXT_VALIDATOR_SET) {
        val msg = SetNextValidatorSetRequest.fromSlice(in.body, {
            throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE,
        });

        val electorParam = blockchain.configParam(1);
        val electorHash = electorParam == null ? -1 : (electorParam!.beginParse().preloadUint(256) as int);

        val (_, srcHash) = in.senderAddress.getWorkchainAndHash();
        var ok = false;
        if (srcHash == electorHash) {
            val (utimeSince, utimeUntil) = checkValidatorSet(msg.vset);
            val now = blockchain.now();
            ok = (utimeSince > now) && (utimeUntil > utimeSince);
        }

        if (ok) {
            setConfParam(36 as int32, msg.vset);
            sendConfirmation(in.senderAddress, msg.queryId, TAG_SET_NEXT_VALIDATORS_ACCEPTED);
        } else {
            sendError(in.senderAddress, msg.queryId, TAG_SET_NEXT_VALIDATORS_REJECTED);
        }
        return;
    }

    if (tag == OP_SET_CUSTOM_PARAM) {
        val msg = SetCustomParamRequest.fromSlice(in.body, {
            throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE,
        });
        val receiverAddress = msg.receiverAddress.castToInternal();
        val (_, isExotic) = msg.value.beginParseSpecial();
        val depth = msg.value.depth();

        val isCustomParam = (msg.paramId as int) == CUSTOM_PARAM_1 ||
            (msg.paramId as int) == CUSTOM_PARAM_2;
        if (!isExotic && depth == 0 && isCustomParam && isAdminOfCustomParam) {
            setConfParam(msg.paramId, msg.value);
            sendConfirmation(receiverAddress, msg.queryId, TAG_SET_CUSTOM_PARAM_ACCEPTED);
        } else {
            sendError(receiverAddress, msg.queryId, TAG_SET_CUSTOM_PARAM_REJECTED);
        }
        return;
    }

    if (tag == OP_NEW_VOTING_PROPOSAL) {
        val msg = NewVotingProposalRequest.fromSlice(in.body, {
            throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE,
        });
        val price = registerVotingProposal(msg, in.valueCoins);

        var mode = SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE;
        var ansTag = -price;
        if (price >= 0) {
            reserveToncoinsOnBalance(price, RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE);
            ansTag = TAG_NEW_VOTING_CREATED;
            mode = SEND_MODE_CARRY_ALL_BALANCE;
        }

        sendAnswer(in.senderAddress, msg.queryId, ansTag as int32, mode);
        return;
    }

    if (tag == OP_VOTE_FOR_PROPOSAL) {
        val msg = VoteForProposalRequest.fromSlice(in.body, {
            throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE,
        });

        // Signature is checked over the raw suffix starting from `SignedVotePayload`.
        var body = in.body;
        body.loadUint(32);
        body.loadUint(64);
        val signature = body.loadBits(512);
        val voteBody = body;
        val votePayload = SignedVotePayload.fromSlice(body, {
            throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE,
        });

        val (validatorDescr, _) = getValidatorDescr(votePayload.validatorIndex);
        val (validatorPubkey, weight) = unpackValidatorDescr(validatorDescr);
        assert (isSliceSignatureValid(voteBody, signature, validatorPubkey)) throw ERROR_INVALID_SIGNATURE;

        val result = proceedRegisterVote(votePayload.proposalHash, votePayload.validatorIndex, weight);
        sendConfirmation(in.senderAddress, msg.queryId, (TAG_VOTE_PROCESSED_BASE + result) as int32);
        return;
    }

    assert (tag == 0 || (tag & (1 << 31)) != 0) throw ERROR_INVALID_MESSAGE;
}

fun onExternalMessage(inMsgBody: slice) {
    val signature = inMsgBody.loadBits(512);
    val signedBody = inMsgBody;

    var cs = signedBody;
    val action = cs.loadUint(32);
    val msgSeqno = cs.loadUint(32);
    val validUntil = cs.loadUint(32);

    assert (validUntil >= blockchain.now()) throw ERROR_VALID_UNTIL_EXPIRED;
    assert (cs.depth() <= 128) throw ERROR_EXTERNAL_BODY_TOO_DEEP;

    var storage = lazy Storage.load();
    assert (msgSeqno == storage.storedSeqno) throw ERROR_BAD_SEQNO;

    if (action == OP_VOTE_FOR_PROPOSAL) {
        val vote = ExternalVoteAction.fromSlice(signedBody, {
            throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE,
        });

        val (validatorDescr, _) = getValidatorDescr(vote.validatorIndex);
        val (validatorPubkey, weight) = unpackValidatorDescr(validatorDescr);
        assert (isSliceSignatureValid(signedBody, signature, validatorPubkey)) throw ERROR_INVALID_SIGNATURE;

        acceptExternalMessage();

        storage.storedSeqno = ((storage.storedSeqno as int + 1) % (1 << 32)) as uint32;
        storage.save();
        commitContractDataAndActions();

        proceedRegisterVote(vote.proposalHash, vote.validatorIndex, weight);
    }
}

fun onRunTickTock() {
    var storage = lazy Storage.load();
    var cfgDict = storage.loadConfigDict();
    var updated = false;

    val nextVsetLookup = cfgDict.get(36 as int32);
    if (nextVsetLookup.isFound) {
        val nextVset = nextVsetLookup.loadValue();
        var ds = nextVset.beginParse();
        if (ds.remainingBitsCount() >= 40) {
            val tag = ds.loadUint(8);
            val since = ds.preloadUint(32);
            if (since <= blockchain.now() && tag == OP_VALIDATOR_SET_EXT) {
                val oldCurrentVset = cfgDict.setAndGetPrevious(34 as int32, nextVset);
                if (oldCurrentVset.isFound) {
                    cfgDict.set(32 as int32, oldCurrentVset.loadValue());
                } else {
                    cfgDict.delete(32 as int32);
                }
                cfgDict.delete(36 as int32);
                updated = true;
            }
        }
    }

    if (!updated) {
        var voteDict = storage.voteDict;
        storage.voteDict = scanRandomProposal(mutate voteDict);
    }

    storage.saveConfigDict(cfgDict);
    storage.save();
}

get fun seqno(): int {
    val storage = lazy Storage.load();
    return storage.storedSeqno;
}

fun unpackProposal(statusCell: cell): tuple {
    val status = ConfigProposalStatus.fromCell(statusCell, {
        throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS,
    });
    val proposal = status.proposal.load();

    var votersList = [] as lisp_list<int>;
    var voter = status.voters.findLast();
    while (voter.isFound) {
        votersList.prependHead(voter.getKey());
        voter = status.voters.iteratePrev(voter);
    }

    val paramHash = proposal.ifHashEqual == null ? -1 : (proposal.ifHashEqual! as int);
    return [
        status.expires,
        status.isCritical,
        [proposal.paramId, proposal.paramValue, paramHash] as tuple,
        status.validatorSetId,
        votersList,
        status.remainingWeight,
        status.roundsRemaining,
        status.wins,
        status.losses,
    ] as tuple;
}

get fun get_proposal(proposalHash: int): tuple? {
    val storage = lazy Storage.load();
    val lookup = storage.voteDict.get(proposalHash as uint256);
    if (!lookup.isFound) {
        return null;
    }
    return unpackProposal(lookup.loadValue());
}

get fun list_proposals(): lisp_list<tuple> {
    val storage = lazy Storage.load();

    var list = [] as lisp_list<tuple>;
    var entry = storage.voteDict.findLast();
    while (entry.isFound) {
        list.prependHead([entry.getKey(), unpackProposal(entry.loadValue())] as tuple);
        entry = storage.voteDict.iteratePrev(entry);
    }

    return list;
}

get fun proposal_storage_price(critical: int, seconds: int, bits: int, refs: int): int {
    val storage = lazy Storage.load();
    val cfgDict = storage.loadConfigDict();
    val cparam11Lookup = cfgDict.get(11 as int32);
    assert (cparam11Lookup.isFound) throw ERROR_INVALID_PROPOSAL_STATUS;

    val voteCfg = getVoteConfigInternal(critical != 0, cparam11Lookup.loadValue());
    if (seconds < voteCfg.minStoreSec) {
        return -1;
    }
    seconds = min(seconds, voteCfg.maxStoreSec);
    return (voteCfg.bitPrice * (bits + 1024) + voteCfg.cellPrice * (refs + 2)) * seconds;
}
