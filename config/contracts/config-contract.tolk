import "@stdlib/gas-payments"
import "@stdlib/lisp-lists"
import "config-helpers"
import "errors"
import "messages"
import "storage"
import "types"

fun isKnownInternalMessageTag(tag: uint32): bool {
    return tag == OP_SET_NEXT_VALIDATOR_SET || tag == OP_SET_CUSTOM_PARAM ||
    tag == OP_NEW_VOTING_PROPOSAL ||
    tag == OP_VOTE_FOR_PROPOSAL;
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

    if (!isKnownInternalMessageTag(tag)) {
        assert (tag == 0 || (tag & INTERNAL_QUERY_HIGH_BIT) != 0) throw ERROR_INVALID_MESSAGE;
        return;
    }

    val msg = lazy AllowedInternalMessage.fromSlice(
        in.body,
        { throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE },
    );

    match (msg) {
        SetNextValidatorSetRequest => {
            val electorParam = blockchain.configParam(CONFIG_PARAM_ELECTOR_ADDRESS);
            var ok = false;

            if (electorParam != null) {
                val (_, srcHash) = in.senderAddress.getWorkchainAndHash();
                val electorHash = electorParam!.beginParse().preloadUint(256);

                if (srcHash == electorHash) {
                    val (utimeSince, utimeUntil) = checkValidatorSet(msg.vset);
                    val now = blockchain.now();
                    ok = (utimeSince > now) && (utimeUntil > utimeSince);
                }
            }

            if (ok) {
                setConfParam(CONFIG_PARAM_NEXT_VALIDATOR_SET, msg.vset);
                sendConfirmation(in.senderAddress, msg.queryId, TAG_SET_NEXT_VALIDATORS_ACCEPTED);
            } else {
                sendError(in.senderAddress, msg.queryId, TAG_SET_NEXT_VALIDATORS_REJECTED);
            }
        }

        SetCustomParamRequest => {
            val (_, isExotic) = msg.value.beginParseSpecial();
            val isCustomParam = msg.paramId == CUSTOM_PARAM_1 || msg.paramId == CUSTOM_PARAM_2;

            if (!isExotic && msg.value.depth() == 0 && isCustomParam && isAdminOfCustomParam) {
                setConfParam(msg.paramId as int, msg.value);
                sendConfirmation(msg.receiverAddress, msg.queryId, TAG_SET_CUSTOM_PARAM_ACCEPTED);
            } else {
                sendError(msg.receiverAddress, msg.queryId, TAG_SET_CUSTOM_PARAM_REJECTED);
            }
        }

        NewVotingProposalRequest => {
            val price = registerVotingProposal(msg, in.valueCoins);

            var mode = SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE;
            var ansTag = -price;
            if (price >= 0) {
                reserveToncoinsOnBalance(price, RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE);
                ansTag = TAG_NEW_VOTING_CREATED;
                mode = SEND_MODE_CARRY_ALL_BALANCE;
            }

            sendAnswer(in.senderAddress, msg.queryId, ansTag, mode);
        }

        VoteForProposalRequest => {
            val signedVote = msg.loadSignedVotePayload(ERROR_INVALID_MESSAGE);

            val (validatorDescr, _) = getValidatorDescr(signedVote.validatorIndex);
            val (validatorPubkey, weight) = unpackValidatorDescr(validatorDescr);

            assert (
                isSliceSignatureValid(msg.signedVoteBody, msg.signature as slice, validatorPubkey)
            ) throw ERROR_INVALID_SIGNATURE;

            val result = proceedRegisterVote(
                signedVote.proposalHash,
                signedVote.validatorIndex,
                weight,
            );
            sendConfirmation(in.senderAddress, msg.queryId, TAG_VOTE_PROCESSED_BASE + result);
        }

        else => throw ERROR_INVALID_MESSAGE,
    }
}

fun onExternalMessage(inMsgBody: slice) {
    val msg = ExternalSignedMessage.fromSlice(inMsgBody);
    val header = ExternalActionHeader.fromSlice(msg.signedBody);

    assert (header.validUntil >= blockchain.now()) throw ERROR_VALID_UNTIL_EXPIRED;
    assert (msg.signedBody.depth() <= 128) throw ERROR_EXTERNAL_BODY_TOO_DEEP;

    var storage = lazy Storage.load();
    assert (header.msgSeqno == storage.storedSeqno) throw ERROR_BAD_SEQNO;

    if (header.action == OP_VOTE_FOR_PROPOSAL) {
        val vote = ExternalVoteAction.fromSlice(
            msg.signedBody,
            { throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE },
        );

        val (validatorDescr, _) = getValidatorDescr(vote.validatorIndex);
        val (validatorPubkey, weight) = unpackValidatorDescr(validatorDescr);

        assert (
            isSliceSignatureValid(msg.signedBody, msg.signature as slice, validatorPubkey)
        ) throw ERROR_INVALID_SIGNATURE;

        acceptExternalMessage();

        storage.incrementSeqno();
        storage.save();
        commitContractDataAndActions();

        proceedRegisterVote(vote.proposalHash, vote.validatorIndex, weight);
    }
}

fun onRunTickTock() {
    var storage = lazy Storage.load();
    var cfgDict = storage.loadConfigDict();
    var updated = false;

    val nextVset = cfgDict.getById(CONFIG_PARAM_NEXT_VALIDATOR_SET);
    if (nextVset != null) {
        var ds = nextVset!.beginParse();
        if (ds.remainingBitsCount() >= 40) {
            val tag = ds.loadUint(8);
            val since = ds.preloadUint(32);

            if (since <= blockchain.now() && tag == OP_VALIDATOR_SET_EXT) {
                val oldCurrentVset = cfgDict.setByIdAndGetPrevious(
                    CONFIG_PARAM_CURRENT_VALIDATOR_SET,
                    nextVset!,
                );

                if (oldCurrentVset != null) {
                    cfgDict.setById(CONFIG_PARAM_PREVIOUS_VALIDATOR_SET, oldCurrentVset!);
                } else {
                    cfgDict.deleteById(CONFIG_PARAM_PREVIOUS_VALIDATOR_SET);
                }

                cfgDict.deleteById(CONFIG_PARAM_NEXT_VALIDATOR_SET);
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

fun unpackProposal(statusSlice: slice): tuple {
    val status = ConfigProposalStatus.fromSlice(
        statusSlice,
        { throwIfOpcodeDoesNotMatch: ERROR_INVALID_PROPOSAL_STATUS },
    );
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

    val cparam11 = cfgDict.getById(CONFIG_PARAM_VOTING_SETUP);
    assert (cparam11 != null) throw ERROR_INVALID_PROPOSAL_STATUS;

    val voteCfg = getVoteConfigInternal(critical != 0, cparam11!);
    if (seconds < voteCfg.minStoreSec) {
        return -1;
    }

    seconds = min(seconds, voteCfg.maxStoreSec);
    return voteCfg.calculateStoragePrice(seconds, bits, refs);
}
