import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/storage"

fun assertProposalCreateOutcome(
    ctx: ConfigTestContext,
    paramIds: array<int>,
    value: cell,
    expectedTag: int,
) {
    var i = 0;
    while (i < paramIds.size()) {
        val paramId = paramIds.get(i);
        val beforeData = contractDataHash(ctx.contract);

        val currentValue = getConfigParam(ctx.contract, paramId as int32);
        var expectedHash: uint256 = 0;
        if (currentValue != null) {
            expectedHash = currentValue!.hash();
        }

        val proposal = createProposal(paramId as int32, value, expectedHash);
        val hash = proposalHash(proposal);

        expect(ctx.contract.get_proposal(hash as int)).toBeNull();

        val res = ctx
            .contract
            .sendNewVotingProposalRequest(
                ctx.proposer,
                i as uint64,
                (net.now() + 86400) as uint32,
                false,
                proposal,
                { value: ton("100"), bounce: true },
            );

        expect(res).toHaveTx<NewVotingProposalRequest>({
            from: ctx.proposer,
            to: ctx.contract.address,
            aborted: false,
        });

        expect(res).toHaveTx({
            from: ctx.contract.address,
            to: ctx.proposer,
            opcode: expectedTag as uint32,
        });

        if (expectedTag == TAG_NEW_VOTING_CREATED) {
            expect(ctx.contract.get_proposal(hash as int) == null).toEqual(false);
        } else {
            expect(contractDataHash(ctx.contract)).toEqual(beforeData);
        }

        i += 1;
    }
}

get fun `test proposals: should not allow voting creation for -1024 and -1025`() {
    val ctx = setupConfigTest();

    val testCell = beginCell().storeSlice("Hop hey La La Ley".beginParse()).endCell();

    val regularParams = [
        10,
        11,
        16,
        17,
        40,
        -1,
        -42,
        -94,
    ] as array<int>;
    assertProposalCreateOutcome(ctx, regularParams, testCell, TAG_NEW_VOTING_CREATED);

    val slotParams = [CUSTOM_SLOT_1, CUSTOM_SLOT_2] as array<int>;
    assertProposalCreateOutcome(ctx, slotParams, testCell, -ERROR_TAG_CUSTOM_SLOT_VOTING_REJECTED);

    var i = 0;
    while (i < slotParams.size()) {
        val slot = slotParams.get(i);

        val slotValue = beginCell().storeInt(slot, 32).storeUint(testCell.hash(), 256).endCell();
        val setRes = ctx
            .contract
            .sendSetCustomParamRequest(
                ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
                i as uint64,
                slot as int32,
                ctx.deployer.address,
                slotValue,
                { value: ton("10"), bounce: true },
            );

        expect(setRes).toHaveTx({
            from: ctx.contract.address,
            to: ctx.deployer.address,
            opcode: TAG_SET_CUSTOM_PARAM_ACCEPTED,
        });
        assertConfigParam(ctx.contract, slot as int32, slotValue);

        i += 1;
    }

    assertProposalCreateOutcome(ctx, slotParams, testCell, -ERROR_TAG_CUSTOM_SLOT_VOTING_REJECTED);
}

get fun `test proposals invariant: proposal list should track creation and avoid growth on reject`() {
    val ctx = setupConfigTest();

    val before = proposalCount(ctx.contract);

    val validProposal = createProposal(-42, beginCell().storeSlice("v1".beginParse()).endCell(), 0);
    val (created, createdHash) = submitProposal(ctx, validProposal, false, 7200, 1);

    expect(created).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });
    expect(proposalCount(ctx.contract)).toEqual(before + 1);
    expect(ctx.contract.get_proposal(createdHash as int) == null).toEqual(false);

    val rejectBefore = proposalCount(ctx.contract);
    val rejectedProposal = createProposal(
        CUSTOM_SLOT_1,
        beginCell().storeSlice("v2".beginParse()).endCell(),
        0,
    );
    val (rejected, rejectedHash) = submitProposal(ctx, rejectedProposal, false, 7200, 2);

    expect(rejected).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_CUSTOM_SLOT_VOTING_REJECTED) as uint32,
    });
    expect(proposalCount(ctx.contract)).toEqual(rejectBefore);
    expect(ctx.contract.get_proposal(rejectedHash as int)).toBeNull();
}

get fun `test proposals invariant: duplicate proposal should be rejected when expiration is not extended`() {
    val ctx = setupConfigTest();

    val payload = beginCell().storeSlice("dup".beginParse()).endCell();
    val proposal = createProposal(-43, payload, 0);

    val first = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            1,
            (net.now() + 2000) as uint32,
            false,
            proposal,
            { value: ton("100"), bounce: true },
        );

    expect(first).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: TAG_NEW_VOTING_CREATED,
    });

    val second = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            2,
            (net.now() + 2000) as uint32,
            false,
            proposal,
            { value: ton("100"), bounce: true },
        );

    expect(second).toHaveTx({
        from: ctx.contract.address,
        to: ctx.proposer,
        opcode: (-ERROR_TAG_PROPOSAL_ALREADY_EXISTS) as uint32,
    });
}

get fun `test proposals unit: proposal_storage_price should respect min-store boundary`() {
    val ctx = setupConfigTest();

    val tooShort = ctx.contract.proposal_storage_price(0, 10, 0, 0);
    val valid = ctx.contract.proposal_storage_price(0, 100, 100, 1);

    expect(tooShort).toEqual(-1);
    expect(valid > 0).toEqual(true);
}
