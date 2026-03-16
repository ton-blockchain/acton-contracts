import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/messages"

fun zeroSignature(): slice {
    return beginCell().storeUint(0, 256).storeUint(0, 256).endCell().beginParse();
}

get fun `test voting ext: should reject bad signature before acceptance`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(
        -401,
        beginCell().storeSlice("ext-bad-sig".beginParse()).endCell(),
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

    val badBody = buildExternalVoteBody(0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash, zeroSignature());
    val rejected = trySendExternalRaw(ctx.contract, badBody);
    expect(rejected).toBeNull();
    expect(ctx.contract.seqno()).toEqual(0);

    val accepted = sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(accepted.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(1);
}

get fun `test voting ext: should accept message and return not-found semantics for unknown proposal`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(
        -402,
        beginCell().storeSlice("ext-unknown".beginParse()).endCell(),
        0,
    );
    val knownHash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 3600) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val first = sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, VOTE_HASH_UNKNOWN_CASE);
    expect(first.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(1);

    val beforeKnown = getProposalFullOrNull(ctx.contract, knownHash);
    expect(beforeKnown == null).toEqual(false);
    expect(proposalVotersCount(beforeKnown!)).toEqual(0);

    val second = sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, knownHash);
    expect(second.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(2);

    val afterKnown = getProposalFullOrNull(ctx.contract, knownHash);
    expect(afterKnown == null).toEqual(false);
    expect(proposalVotersCount(afterKnown!)).toEqual(1);
}

get fun `test voting ext: should remove expired proposal on accepted external vote`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(
        -403,
        beginCell().storeSlice("ext-expired".beginParse()).endCell(),
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

    val res = sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(res.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(1);
    expect(ctx.contract.getProposal(hash as int)).toBeNull();
}

get fun `test voting ext invariant: duplicate vote should not mutate proposal status`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(
        -404,
        beginCell().storeSlice("ext-dup".beginParse()).endCell(),
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

    sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    val beforeDup = getProposalFullOrNull(ctx.contract, hash);
    expect(beforeDup == null).toEqual(false);
    expect(proposalVotersCount(beforeDup!)).toEqual(1);

    sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(ctx.contract.seqno()).toEqual(2);

    val afterDup = getProposalFullOrNull(ctx.contract, hash);
    expect(afterDup == null).toEqual(false);
    expect(proposalVotersCount(afterDup!)).toEqual(1);
    expect(afterDup!.remainingWeight).toEqual(beforeDup!.remainingWeight);
    expect(afterDup!.wins).toEqual(beforeDup!.wins);
    expect(afterDup!.losses).toEqual(beforeDup!.losses);
}

get fun `test voting ext invariant: round transition on vote should reset voters and bump losses`() {
    val ctx = setupConfigTest();
    val weighted = buildValidatorsWithWeights([1, 5] as array<int>);
    val firstVset = applyCurrentValidatorSet(weighted, 0);

    val proposal = createProposal(
        -405,
        beginCell().storeSlice("ext-round".beginParse()).endCell(),
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

    sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    val before = getProposalFullOrNull(ctx.contract, hash);
    expect(before == null).toEqual(false);
    expect(before!.validatorSetId).toEqual(firstVset.hash() as int);
    expect(before!.remainingWeight).toEqual(3);
    expect(before!.losses).toEqual(0);
    expect(proposalVotersCount(before!)).toEqual(1);

    val secondVset = applyCurrentValidatorSet(weighted, 1);
    sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(ctx.contract.seqno()).toEqual(2);

    val after = getProposalFullOrNull(ctx.contract, hash);
    expect(after == null).toEqual(false);
    expect(after!.validatorSetId).toEqual(secondVset.hash() as int);
    expect(after!.remainingWeight).toEqual(3);
    expect(after!.roundsRemaining).toEqual(before!.roundsRemaining - 1);
    expect(after!.losses).toEqual(before!.losses + 1);
    expect(proposalVotersCount(after!)).toEqual(1);
}

get fun `test voting ext: should accept proposal across rounds and apply config`() {
    val ctx = setupConfigTest();
    val value = beginCell().storeSlice("ext-accept".beginParse()).endCell();
    val proposal = createProposal(-406, value, 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    applyCurrentValidatorSet(ctx.validators, 1);
    sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);

    expect(ctx.contract.seqno()).toEqual(2);
    expect(ctx.contract.getProposal(hash as int)).toBeNull();
    assertConfigParam(ctx.contract, -406, value);
}
