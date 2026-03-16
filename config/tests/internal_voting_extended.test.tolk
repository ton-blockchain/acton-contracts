import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/messages"

fun singleIndexDictCell(idx: int32): cell {
    var m = createEmptyMap<int32, slice>();
    m.set(idx, beginCell().toSlice());
    return m.toLowLevelDict()!;
}

fun zeroSignature(): slice {
    return beginCell().storeUint(0, 256).storeUint(0, 256).endCell().beginParse();
}

get fun `test voting int: should reject malformed signed-vote payload tag`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(
        -301,
        beginCell().storeSlice("malformed".beginParse()).endCell(),
        0,
    );
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 3600) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val malformed = beginCell()
        .storeUint(OP_VOTE_FOR_PROPOSAL, 32)
        .storeUint(1, 64)
        .storeSlice(zeroSignature())
        .storeUint(0x12345678, 32)
        .storeUint(0, 16)
        .storeUint(hash, 256)
        .endCell();

    val res = ctx
        .contract
        .sendAny(ctx.validatorSender, malformed, { value: ton("10"), bounce: true });

    expect(res).toHaveTx({
        from: ctx.validatorSender,
        to: ctx.contract.address,
        opcode: OP_VOTE_FOR_PROPOSAL,
        aborted: true,
    });
    expect(ctx.contract.getProposal(hash as int) == null).toEqual(false);
}

get fun `test voting int: should reject bad signature`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(-302, beginCell().storeSlice("badsig".beginParse()).endCell(), 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 3600) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val payload = SignedVotePayload {
        validatorIndex: 0,
        proposalHash: hash,
    }.toCell();
    val bad = beginCell()
        .storeUint(OP_VOTE_FOR_PROPOSAL, 32)
        .storeUint(2, 64)
        .storeSlice(zeroSignature())
        .storeSlice(payload.beginParse())
        .endCell();

    val res = ctx.contract.sendAny(ctx.validatorSender, bad, { value: ton("10"), bounce: true });

    expect(res).toHaveTx({
        from: ctx.validatorSender,
        to: ctx.contract.address,
        opcode: OP_VOTE_FOR_PROPOSAL,
        aborted: true,
    });
    expect(res).toNotHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE + 2) as uint32,
    });
}

get fun `test voting int: should return not-found status for unknown proposal`() {
    val ctx = setupConfigTest();

    val res = sendSignedVote(ctx, 0, VOTE_HASH_REGULAR_PARAM, 3);
    expect(res).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE - 1) as uint32,
    });
}

get fun `test voting int: should remove expired proposal on vote attempt`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(
        -303,
        beginCell().storeSlice("expired".beginParse()).endCell(),
        0,
    );
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() - 1) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val res = sendSignedVote(ctx, 0, hash, 4);
    expect(res).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE - 1) as uint32,
    });
    expect(ctx.contract.getProposal(hash as int)).toBeNull();
}

get fun `test voting int invariant: round transition on vote should reset voters and bump losses`() {
    val ctx = setupConfigTest();
    val weighted = buildValidatorsWithWeights([1, 5] as array<int>);

    val firstVset = applyCurrentValidatorSet(weighted, 0);
    val proposal = createProposal(
        -304,
        beginCell().storeSlice("round-vote".beginParse()).endCell(),
        0,
    );
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        true,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val firstVote = sendSignedVote(ctx, 0, hash, 10);
    expect(firstVote).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE + 2) as uint32,
    });

    val before = getProposalFullOrNull(ctx.contract, hash);
    expect(before == null).toEqual(false);
    expect(before!.validatorSetId).toEqual(firstVset.hash() as int);
    expect(before!.remainingWeight).toEqual(3);
    expect(before!.losses).toEqual(0);
    expect(proposalVotersCount(before!)).toEqual(1);

    val secondVset = applyCurrentValidatorSet(weighted, 1);
    val secondVote = sendSignedVote(ctx, 0, hash, 11);
    expect(secondVote).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE + 2) as uint32,
    });

    val after = getProposalFullOrNull(ctx.contract, hash);
    expect(after == null).toEqual(false);
    expect(after!.validatorSetId).toEqual(secondVset.hash() as int);
    expect(after!.remainingWeight).toEqual(3);
    expect(after!.roundsRemaining).toEqual(before!.roundsRemaining - 1);
    expect(after!.losses).toEqual(before!.losses + 1);
    expect(proposalVotersCount(after!)).toEqual(1);
}

get fun `test voting int invariant: proposal should be removed after too many losses`() {
    val ctx = setupConfigTest();
    val weighted = buildValidatorsWithWeights([1, 5] as array<int>);
    applyCurrentValidatorSet(weighted, 0);

    setVotingSetup(
        ctx.contract,
        ConfigProposalSetup {
            minTotalRounds: 1,
            maxTotalRounds: 10,
            minWins: 5,
            maxLosses: 1,
            minStoreSec: 30,
            maxStoreSec: 3 * 86400,
            bitPrice: 1,
            cellPrice: 1,
        },
        ConfigProposalSetup {
            minTotalRounds: 1,
            maxTotalRounds: 10,
            minWins: 5,
            maxLosses: 1,
            minStoreSec: 30,
            maxStoreSec: 3 * 86400,
            bitPrice: 1,
            cellPrice: 1,
        },
    );

    val proposal = createProposal(-305, beginCell().storeSlice("losses".beginParse()).endCell(), 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
        1,
    );

    sendSignedVote(ctx, 0, hash, 20);
    applyCurrentValidatorSet(weighted, 1);
    sendSignedVote(ctx, 0, hash, 21);
    applyCurrentValidatorSet(weighted, 2);

    val removed = sendSignedVote(ctx, 0, hash, 22);
    expect(removed).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE - 1) as uint32,
    });
    expect(ctx.contract.getProposal(hash as int)).toBeNull();
}

get fun `test voting int invariant: proposal should be removed after too many rounds`() {
    val ctx = setupConfigTest();
    val weighted = buildValidatorsWithWeights([1, 5] as array<int>);
    applyCurrentValidatorSet(weighted, 0);

    setVotingSetup(
        ctx.contract,
        ConfigProposalSetup {
            minTotalRounds: 1,
            maxTotalRounds: 1,
            minWins: 5,
            maxLosses: 10,
            minStoreSec: 30,
            maxStoreSec: 3 * 86400,
            bitPrice: 1,
            cellPrice: 1,
        },
        ConfigProposalSetup {
            minTotalRounds: 1,
            maxTotalRounds: 1,
            minWins: 5,
            maxLosses: 10,
            minStoreSec: 30,
            maxStoreSec: 3 * 86400,
            bitPrice: 1,
            cellPrice: 1,
        },
    );

    val proposal = createProposal(-306, beginCell().storeSlice("rounds".beginParse()).endCell(), 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
        1,
    );

    var storage = getStorage(ctx.contract);
    val lookup = storage.voteDict.get(hash);
    expect(lookup.isFound).toEqual(true);
    var status = ConfigProposalStatus.fromSlice(lookup.loadValue());
    status.validatorSetId = (hash + 1) as uint256;
    status.roundsRemaining = 0;
    storage.voteDict.set(hash, status.toCell().beginParse());
    setStorage(ctx.contract, storage);

    val removed = sendSignedVote(ctx, 0, hash, 30);
    expect(removed).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE - 1) as uint32,
    });
    expect(ctx.contract.getProposal(hash as int)).toBeNull();
}

get fun `test voting int acceptance invariant: should not apply value when current hash changed`() {
    val ctx = setupConfigTest();
    val idx = -307 as int32;
    val newVal = beginCell().storeSlice("new".beginParse()).endCell();
    val changedVal = beginCell().storeSlice("changed".beginParse()).endCell();

    setStorageConfigParam(ctx.contract, idx, null);
    val proposal = createProposal(idx, newVal, 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    setStorageConfigParam(ctx.contract, idx, changedVal);
    voteUntilAccepted(ctx, hash);

    expect(ctx.contract.getProposal(hash as int)).toBeNull();
    assertConfigParam(ctx.contract, idx, changedVal);
}

get fun `test voting int acceptance invariant: should not nullify param that became mandatory`() {
    val ctx = setupConfigTest();
    val idx = -308 as int32;
    val prevVal = beginCell().storeSlice("prev".beginParse()).endCell();

    setStorageConfigParam(ctx.contract, idx, prevVal);
    val proposal = createProposal(idx, null, null);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    setStorageConfigParam(ctx.contract, CONFIG_PARAM_MANDATORY_PARAMS, singleIndexDictCell(idx));
    voteUntilAccepted(ctx, hash);

    expect(ctx.contract.getProposal(hash as int)).toBeNull();
    assertConfigParam(ctx.contract, idx, prevVal);
}

get fun `test voting int acceptance invariant: should not apply non-critical vote after param became critical`() {
    val ctx = setupConfigTest();
    val idx = -309 as int32;
    val prevVal = beginCell().storeSlice("prev-crit".beginParse()).endCell();

    setStorageConfigParam(ctx.contract, idx, prevVal);
    val proposal = createProposal(idx, null, null);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    setStorageConfigParam(ctx.contract, CONFIG_PARAM_CRITICAL_PARAMS, singleIndexDictCell(idx));
    voteUntilAccepted(ctx, hash);

    expect(ctx.contract.getProposal(hash as int)).toBeNull();
    assertConfigParam(ctx.contract, idx, prevVal);
}
