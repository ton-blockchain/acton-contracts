import "@stdlib/exotic-cells"
import "@stdlib/gas-payments"
import "@stdlib/lisp-lists"
import "config-helpers"
import "errors"
import "messages"
import "storage"

type AllowedInternalMessage =
    | SetNextValidatorSetRequest
    | SetCustomParamRequest
    | NewVotingProposalRequest
    | VoteForProposalRequest

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

    if (tag == 0 || (tag & INTERNAL_QUERY_HIGH_BIT) != 0) {
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
                    val validatorSetWindow = checkValidatorSet(msg.vset);
                    val now = blockchain.now();
                    ok = (validatorSetWindow.utimeSince > now) &&
                    (validatorSetWindow.utimeUntil > validatorSetWindow.utimeSince);
                }
            }

            if (ok) {
                Storage.setConfigParam(CONFIG_PARAM_NEXT_VALIDATOR_SET, msg.vset);
                sendConfirmation(in.senderAddress, msg.queryId, TAG_SET_NEXT_VALIDATORS_ACCEPTED);
            } else {
                sendError(in.senderAddress, msg.queryId, TAG_SET_NEXT_VALIDATORS_REJECTED);
            }
        }

        SetCustomParamRequest => {
            val (_, isExotic) = msg.value.beginParseSpecial();
            val isCustomParam = msg.paramId == CUSTOM_PARAM_1 || msg.paramId == CUSTOM_PARAM_2;

            if (!isExotic && msg.value.depth() == 0 && isCustomParam && isAdminOfCustomParam) {
                Storage.setConfigParam(msg.paramId as int, msg.value);
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

            val answerMsg = createMessage({
                bounce: true,
                dest: in.senderAddress,
                value: 0,
                body: AnswerBody {
                    ansTag: (ansTag & 0xffffffff),
                    queryId: msg.queryId,
                },
            });

            answerMsg.send(mode);
        }

        VoteForProposalRequest => {
            val signedVote = msg.loadSignedVotePayload(ERROR_INVALID_MESSAGE);
            val validatorContext = getCurrentValidatorContext(signedVote.validatorIndex);

            assert (
                isSliceSignatureValid(
                    msg.signedVoteBody,
                    msg.signature as slice,
                    validatorContext.publicKey,
                )
            ) throw ERROR_INVALID_SIGNATURE;

            val result = proceedRegisterVote(
                signedVote.proposalHash,
                signedVote.validatorIndex,
                validatorContext.weight,
                validatorContext.validatorSetId,
                validatorContext.totalWeight,
            );
            sendConfirmation(in.senderAddress, msg.queryId, TAG_VOTE_PROCESSED_BASE + result);
        }

        else => throw ERROR_INVALID_MESSAGE,
    }
}

fun onExternalMessage(inMsgBody: slice) {
    assert (inMsgBody.depth() <= 128) throw ERROR_EXTERNAL_BODY_TOO_DEEP;

    // TODO: lazy bench
    val msg = lazy ExternalSignedMessage.fromSlice(inMsgBody, { throwIfOpcodeDoesNotMatch: 0 });

    assert (msg.action.validUntil >= blockchain.now()) throw ERROR_VALID_UNTIL_EXPIRED;

    var storage = lazy Storage.load();
    assert (msg.action.msgSeqno == storage.storedSeqno) throw ERROR_BAD_SEQNO;

    val validatorContext = getCurrentValidatorContext(msg.action.validatorIndex);

    // TODO: bench skip vs RemainingBits vs skip val
    assert (
        isSliceSignatureValid(
            inMsgBody.skipBits(512),
            msg.signature as slice,
            validatorContext.publicKey,
        )
    ) throw ERROR_INVALID_SIGNATURE;

    acceptExternalMessage();

    storage.incrementSeqno();
    storage.save();
    commitContractDataAndActions();

    proceedRegisterVote(
        msg.action.proposalHash,
        msg.action.validatorIndex,
        validatorContext.weight,
        validatorContext.validatorSetId,
        validatorContext.totalWeight,
    );
}

fun onRunTickTock() {
    var storage = lazy Storage.load();
    var configDict = storage.config;
    var updated = false;

    val nextVset = configDict.getById(CONFIG_PARAM_NEXT_VALIDATOR_SET);
    if (nextVset != null) {
        var ds = nextVset!.beginParse();
        if (ds.remainingBitsCount() >= 40) {
            val tag = ds.loadUint(8);
            val since = ds.preloadUint(32);

            if (since <= blockchain.now() && tag == OP_VALIDATOR_SET_EXT) {
                val oldCurrentVset = configDict.setByIdAndGetPrevious(
                    CONFIG_PARAM_CURRENT_VALIDATOR_SET,
                    nextVset!,
                );

                if (oldCurrentVset != null) {
                    configDict.setById(CONFIG_PARAM_PREVIOUS_VALIDATOR_SET, oldCurrentVset!);
                } else {
                    configDict.deleteById(CONFIG_PARAM_PREVIOUS_VALIDATOR_SET);
                }

                configDict.deleteById(CONFIG_PARAM_NEXT_VALIDATOR_SET);
                updated = true;
            }
        }
    }

    if (!updated) {
        // TODO: mutate?
        scanRandomProposal(mutate storage.voteDict);
    }

    storage.config = configDict;
    storage.save();
}

get fun seqno(): int {
    val storage = lazy Storage.load();
    return storage.storedSeqno;
}

struct ProposalParameterView {
    paramId: int32
    paramValue: cell?
    paramHash: int
}

struct ProposalView {
    expires: uint32
    isCritical: bool
    proposal: ProposalParameterView
    validatorSetId: uint256
    voters: lisp_list<int>
    remainingWeight: int64
    roundsRemaining: uint8
    wins: uint8
    losses: uint8
}

struct ProposalListEntry {
    proposalHash: uint256
    proposal: ProposalView
}

fun unpackProposal(statusSlice: slice): ProposalView {
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

    return ProposalView {
        expires: status.expires,
        isCritical: status.isCritical,
        proposal: ProposalParameterView {
            paramId: proposal.paramId,
            paramValue: proposal.paramValue,
            paramHash,
        },
        validatorSetId: status.validatorSetId,
        voters: votersList,
        remainingWeight: status.remainingWeight,
        roundsRemaining: status.roundsRemaining,
        wins: status.wins,
        losses: status.losses,
    };
}

fun proposalParameterViewToTuple(proposal: ProposalParameterView): tuple {
    return [proposal.paramId, proposal.paramValue, proposal.paramHash] as tuple;
}

fun proposalViewToTuple(proposal: ProposalView): tuple {
    return [
        proposal.expires,
        proposal.isCritical,
        proposalParameterViewToTuple(proposal.proposal),
        proposal.validatorSetId,
        proposal.voters,
        proposal.remainingWeight,
        proposal.roundsRemaining,
        proposal.wins,
        proposal.losses,
    ] as tuple;
}

get fun get_proposal(proposalHash: int): tuple? {
    val storage = lazy Storage.load();
    val lookup = storage.voteDict.get(proposalHash as uint256);
    if (!lookup.isFound) {
        return null;
    }
    return proposalViewToTuple(unpackProposal(lookup.loadValue()));
}

get fun list_proposals(): lisp_list<tuple> {
    val storage = lazy Storage.load();

    var list = [] as lisp_list<tuple>;
    var entry = storage.voteDict.findLast();
    while (entry.isFound) {
        list.prependHead(
            [entry.getKey(), proposalViewToTuple(unpackProposal(entry.loadValue()))] as tuple,
        );
        entry = storage.voteDict.iteratePrev(entry);
    }

    return list;
}

get fun proposal_storage_price(critical: int, seconds: int, bits: int, refs: int): int {
    val storage = lazy Storage.load();
    val configDict = storage.config;

    val cparam11 = configDict.getById(CONFIG_PARAM_VOTING_SETUP);
    assert (cparam11 != null) throw ERROR_INVALID_PROPOSAL_STATUS;

    val voteCfg = getVoteConfigInternal(critical != 0, cparam11!);
    if (seconds < voteCfg.minStoreSec) {
        return -1;
    }

    seconds = min(seconds, voteCfg.maxStoreSec);
    return voteCfg.calculateStoragePrice(seconds, bits, refs);
}
