import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "test-utils"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/ConfigContract"

fun deepCell(depth: int): cell {
    var c = beginCell().storeUint(1, 1).endCell();
    var i = 0;
    while (i < depth) {
        c = beginCell().storeRef(c).endCell();
        i += 1;
    }
    return c;
}

fun setSingleIndexDictConfig(paramId: int32, idx: int32) {
    var dict: map<int32, slice> = [];
    dict.set(idx, beginCell().toSlice());
    setGlobalConfigParam(paramId as uint32, dict.toLowLevelDict()!);
}

get fun `test proposals ext: should reject hash mismatch and accept matching hash`() {
    val ctx = setupConfigTest();

    val current = testing.getConfig().getParamRaw(CONFIG_PARAM_CURRENT_VALIDATOR_SET);
    val currentHash = current.hash();

    val newValue = beginCell().storeSlice("new-vset-like".beginParse()).endCell();

    val badProposal = createProposal(CONFIG_PARAM_CURRENT_VALIDATOR_SET, newValue, 0);
    val (rejected, _) = submitProposal(ctx, badProposal, false, 7200, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_BAD_CURRENT_VALUE_HASH),
    });

    val goodProposal = createProposal(CONFIG_PARAM_CURRENT_VALIDATOR_SET, newValue, currentHash);
    val (accepted, hash) = submitProposal(ctx, goodProposal, false, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.getProposal(hash) == null).toEqual(false);
}

get fun `test proposals ext: should reject nullification of mandatory param`() {
    val ctx = setupConfigTest();
    setSingleIndexDictConfig(CONFIG_PARAM_MANDATORY_PARAMS, CONFIG_PARAM_CURRENT_VALIDATOR_SET);

    val mandatoryNull = createProposal(CONFIG_PARAM_CURRENT_VALIDATOR_SET, null, null);
    val (rejected, _) = submitProposal(ctx, mandatoryNull, false, 7200, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_MANDATORY_PARAM_CANNOT_BE_NULL),
    });

    val nonMandatoryNull = createProposal(-200, null, null);
    val (accepted, hash) = submitProposal(ctx, nonMandatoryNull, false, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.getProposal(hash) == null).toEqual(false);
}

get fun `test proposals ext: should reject overly deep value`() {
    val ctx = setupConfigTest();

    val tooDeep = createProposal(-201, deepCell(256), 0);
    val (rejected, _) = submitProposal(ctx, tooDeep, false, 7200, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_BAD_VALUE),
    });

    val acceptableDepth = createProposal(-202, deepCell(120), 0);
    val (accepted, hash) = submitProposal(ctx, acceptableDepth, false, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.getProposal(hash) == null).toEqual(false);
}

get fun `test proposals ext: should enforce critical flag for critical params`() {
    val ctx = setupConfigTest();
    setSingleIndexDictConfig(CONFIG_PARAM_CRITICAL_PARAMS, -203);

    val value = beginCell().storeSlice("crit".beginParse()).endCell();
    val noCriticalFlag = createProposal(-203, value, 0);
    val (rejected, _) = submitProposal(ctx, noCriticalFlag, false, 7200, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_CRITICAL_FLAG_REQUIRED),
    });

    val (accepted, hash) = submitProposal(ctx, noCriticalFlag, true, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.getProposal(hash) == null).toEqual(false);
}

get fun `test proposals ext: should enforce minimal storage duration`() {
    val ctx = setupConfigTest();

    val value = beginCell().storeSlice("ttl".beginParse()).endCell();
    val proposal = createProposal(-204, value, 0);

    val (rejected, _) = submitProposal(ctx, proposal, false, 29, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_PROPOSAL_EXPIRED),
    });

    val (accepted, hash) = submitProposal(ctx, proposal, false, 30, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.getProposal(hash) == null).toEqual(false);
}

get fun `test proposals ext invariant: update requires matching criticality and enough funds`() {
    val ctx = setupConfigTest();

    val value = beginCell().storeSlice("extend".beginParse()).endCell();
    val proposal = createProposal(-205, value, 0);

    val first = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            1,
            (testing.getNow() + 1200),
            false,
            proposal,
            { value: ton("100"), bounce: true },
        );
    expect(first).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });

    val criticalMismatch = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            2,
            (testing.getNow() + 2400),
            true,
            proposal,
            { value: ton("100"), bounce: true },
        );
    expect(criticalMismatch).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_CANNOT_DOWNGRADE_CRITICALITY),
    });

    val alreadyExists = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            3,
            (testing.getNow() + 1200),
            false,
            proposal,
            { value: ton("100"), bounce: true },
        );
    expect(alreadyExists).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_PROPOSAL_ALREADY_EXISTS),
    });

    val lowFunds = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            4,
            (testing.getNow() + 3600),
            false,
            proposal,
            { value: ton("0.5"), bounce: true },
        );
    expect(lowFunds).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_NOT_ENOUGH_FUNDS),
    });

    val extended = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            5,
            (testing.getNow() + 3600),
            false,
            proposal,
            { value: ton("100"), bounce: true },
        );
    expect(extended).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
}
