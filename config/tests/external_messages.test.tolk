import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/messages"

fun zeroSignature(): slice {
    return beginCell().storeUint(0, 256).storeUint(0, 256).endCell().beginParse();
}

fun veryDeepCell(depth: int): cell {
    var c = beginCell().storeUint(1, 1).endCell();
    var i = 0;
    while (i < depth) {
        c = beginCell().storeRef(c).endCell();
        i += 1;
    }
    return c;
}

get fun `test external msg: should reject expired vote and accept non-expired vote`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(-91, beginCell().storeSlice("ext-exp".beginParse()).endCell(), 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val expired = buildExternalVoteBody(
        0,
        EXTERNAL_VALID_UNTIL_PAST,
        0,
        hash,
        precomputedExternalVoteSignature(hash, 0, EXTERNAL_VALID_UNTIL_PAST, 0),
    );
    val rejected = trySendExternalRaw(ctx.contract, expired);
    expect(rejected).toBeNull();
    expect(ctx.contract.seqno()).toEqual(0);

    val accepted = sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(accepted.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(1);
}

get fun `test external msg: should reject too-deep body before parsing`() {
    val ctx = setupConfigTest();

    val deepBody = veryDeepCell(129);
    val rejected = trySendExternalRaw(ctx.contract, deepBody);
    expect(rejected).toBeNull();
    expect(ctx.contract.seqno()).toEqual(0);

    val proposal = createProposal(
        -92,
        beginCell().storeSlice("ext-depth".beginParse()).endCell(),
        0,
    );
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );
    val accepted = sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(accepted.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(1);
}

get fun `test external msg: should reject bad signature`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(-93, beginCell().storeSlice("ext-sig".beginParse()).endCell(), 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
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

get fun `test external msg invariant: should track seqno strictly`() {
    val ctx = setupConfigTest();
    val proposal = createProposal(-94, beginCell().storeSlice("ext-seq".beginParse()).endCell(), 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 7200) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val first = sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(first.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(1);

    val second = sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    expect(second.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(2);

    val badSeqBody = buildExternalVoteBody(
        5,
        EXTERNAL_VALID_UNTIL_FUTURE,
        0,
        hash,
        precomputedExternalVoteSignature(hash, 5, EXTERNAL_VALID_UNTIL_FUTURE, 0),
    );
    val rejected = trySendExternalRaw(ctx.contract, badSeqBody);
    expect(rejected).toBeNull();
    expect(ctx.contract.seqno()).toEqual(2);
}
