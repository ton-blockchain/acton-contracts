import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "test-utils"
import "../contracts/messages"
import "../wrappers/Config.gen"

const OP_ELECTOR_CODE_CHANGE_ACTION = 0x4e436f64
const TEST_SPECIAL_PUBKEY_INT = 0x123456789abcdef
const TEST_SPECIAL_PUBKEY_EXT = 0xfedcba987654321

get fun `test special params int: should apply -999 proposal and update stored public key`() {
    val ctx = setupConfigTest();
    val pubCell = beginCell().storeUint(TEST_SPECIAL_PUBKEY_INT, 256).endCell();
    val current = getConfigParam(ctx.contract, -999);
    val expectedHash: uint256 = current == null ? 0 : current!.hash();

    val proposal = createProposal(-999, pubCell, expectedHash);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (testing.getNow() + 7200),
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val before = getStorage(ctx.contract);
    expect(before.publicKey).toEqual(0);

    voteUntilAccepted(ctx, hash);
    expect(ctx.contract.getProposal(hash)).toBeNull();
    assertConfigParam(ctx.contract, -999, pubCell);

    val after = getStorage(ctx.contract);
    expect(after.publicKey).toEqual(TEST_SPECIAL_PUBKEY_INT);
}

get fun `test special params ext: should apply -999 proposal and update stored public key`() {
    val ctx = setupConfigTest();
    val pubCell = beginCell().storeUint(TEST_SPECIAL_PUBKEY_EXT, 256).endCell();
    val current = getConfigParam(ctx.contract, -999);
    val expectedHash: uint256 = current == null ? 0 : current!.hash();

    val proposal = createProposal(-999, pubCell, expectedHash);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (testing.getNow() + 7200),
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    applyCurrentValidatorSet(ctx.validators, 1);
    sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);

    expect(ctx.contract.getProposal(hash)).toBeNull();
    assertConfigParam(ctx.contract, -999, pubCell);
    val after = getStorage(ctx.contract);
    expect(after.publicKey).toEqual(TEST_SPECIAL_PUBKEY_EXT);
}

get fun `test special params int: should emit elector code-change action for -1001`() {
    val ctx = setupConfigTest();
    val newCodeBody = beginCell().storeSlice("elector-int".beginParse()).endCell();
    val proposal = createProposal(-1001, newCodeBody, 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (testing.getNow() + 7200),
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    val accepted = voteUntilAccepted(ctx, hash);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: OP_ELECTOR_CODE_CHANGE_ACTION,
    });
}

get fun `test special params ext: should emit elector code-change action for -1001`() {
    val ctx = setupConfigTest();
    val newCodeBody = beginCell().storeSlice("elector-ext".beginParse()).endCell();
    val proposal = createProposal(-1001, newCodeBody, 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (testing.getNow() + 7200),
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    applyCurrentValidatorSet(ctx.validators, 1);
    val accepted = sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);

    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: OP_ELECTOR_CODE_CHANGE_ACTION,
    });
}

get fun `test special params ext: should execute -1000 code upgrade action`() {
    val ctx = setupConfigTest();
    setVotingSetup(
        ctx.contract,
        ConfigProposalSetup {
            minTotalRounds: 2,
            maxTotalRounds: 12,
            minWins: 2,
            maxLosses: 10,
            minStoreSec: 30,
            maxStoreSec: 3 * 86400,
            bitPrice: 1,
            cellPrice: 1,
        },
        ConfigProposalSetup {
            minTotalRounds: 2,
            maxTotalRounds: 12,
            minWins: 2,
            maxLosses: 10,
            minStoreSec: 30,
            maxStoreSec: 3 * 86400,
            bitPrice: 1,
            cellPrice: 1,
        },
    );

    val codeValue = beginCell().storeRef(activeCode(ctx.contract.address)).endCell();
    val proposal = createProposal(-1000, codeValue, 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        true,
        (testing.getNow() + 7200),
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    sendExternalVote(ctx, 0, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);
    applyCurrentValidatorSet(ctx.validators, 1);
    val accepted = sendExternalVote(ctx, 1, EXTERNAL_VALID_UNTIL_FUTURE, 0, hash);

    expect(ctx.contract.getProposal(hash)).toBeNull();
    expect(hasSetCodeAction(accepted, ctx.contract.address)).toEqual(true);
}
