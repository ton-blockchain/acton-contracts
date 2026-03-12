import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/storage"

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
    var dict = createEmptyMap<int32, slice>();
    dict.set(idx, beginCell().toSlice());
    setGlobalConfigParam(paramId as uint32, dict.toLowLevelDict()!);
}

get fun `test proposals ext: should reject hash mismatch and accept matching hash`() {
    val ctx = setupConfigTest();

    val current = net.getConfig().getParamRaw(CONFIG_PARAM_CURRENT_VALIDATOR_SET);
    val currentHash = current.hash();

    val newValue = beginCell().storeSlice("new-vset-like".beginParse()).endCell();

    val badProposal = createProposal(CONFIG_PARAM_CURRENT_VALIDATOR_SET, newValue, 0);
    val (rejected, _) = submitProposal(ctx, badProposal, false, 7200, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_BAD_CURRENT_VALUE_HASH) as uint32,
    });

    val goodProposal = createProposal(CONFIG_PARAM_CURRENT_VALIDATOR_SET, newValue, currentHash);
    val (accepted, hash) = submitProposal(ctx, goodProposal, false, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.get_proposal(hash as int) == null).toEqual(false);
}

get fun `test proposals ext: should reject nullification of mandatory param`() {
    val ctx = setupConfigTest();
    setSingleIndexDictConfig(CONFIG_PARAM_MANDATORY_PARAMS, CONFIG_PARAM_CURRENT_VALIDATOR_SET);

    val mandatoryNull = createProposal(CONFIG_PARAM_CURRENT_VALIDATOR_SET, null, null);
    val (rejected, _) = submitProposal(ctx, mandatoryNull, false, 7200, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_MANDATORY_PARAM_CANNOT_BE_NULL) as uint32,
    });

    val nonMandatoryNull = createProposal(-200, null, null);
    val (accepted, hash) = submitProposal(ctx, nonMandatoryNull, false, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.get_proposal(hash as int) == null).toEqual(false);
}

get fun `test proposals ext: should reject overly deep value`() {
    val ctx = setupConfigTest();

    val tooDeep = createProposal(-201, deepCell(256), 0);
    val (rejected, _) = submitProposal(ctx, tooDeep, false, 7200, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_BAD_VALUE) as uint32,
    });

    val acceptableDepth = createProposal(-202, deepCell(120), 0);
    val (accepted, hash) = submitProposal(ctx, acceptableDepth, false, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.get_proposal(hash as int) == null).toEqual(false);
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
        opcode: (-ERROR_TAG_CRITICAL_FLAG_REQUIRED) as uint32,
    });

    val (accepted, hash) = submitProposal(ctx, noCriticalFlag, true, 7200, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.get_proposal(hash as int) == null).toEqual(false);
}

get fun `test proposals ext: should enforce minimal storage duration`() {
    val ctx = setupConfigTest();

    val value = beginCell().storeSlice("ttl".beginParse()).endCell();
    val proposal = createProposal(-204, value, 0);

    val (rejected, _) = submitProposal(ctx, proposal, false, 29, 1);
    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_PROPOSAL_EXPIRED) as uint32,
    });

    val (accepted, hash) = submitProposal(ctx, proposal, false, 30, 2);
    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(ctx.contract.get_proposal(hash as int) == null).toEqual(false);
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
            (net.now() + 1200) as uint32,
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
            (net.now() + 2400) as uint32,
            true,
            proposal,
            { value: ton("100"), bounce: true },
        );
    expect(criticalMismatch).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_CANNOT_DOWNGRADE_CRITICALITY) as uint32,
    });

    val alreadyExists = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            3,
            (net.now() + 1200) as uint32,
            false,
            proposal,
            { value: ton("100"), bounce: true },
        );
    expect(alreadyExists).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_PROPOSAL_ALREADY_EXISTS) as uint32,
    });

    val lowFunds = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            4,
            (net.now() + 3600) as uint32,
            false,
            proposal,
            { value: ton("0.5"), bounce: true },
        );
    expect(lowFunds).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_NOT_ENOUGH_FUNDS) as uint32,
    });

    val extended = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            5,
            (net.now() + 3600) as uint32,
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
