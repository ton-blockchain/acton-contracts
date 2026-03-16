import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/messages"
import "../contracts/storage"

get fun `test voting: should process votes for code update and regular parameter`() {
    val ctx = setupConfigTest();

    val currentCode = activeCode(ctx.contract.address);
    val codeProposalValue = beginCell().storeRef(currentCode).endCell();
    val codeProposal = createProposal(-1000, codeProposalValue, 0);
    val codeProposalHash = injectProposalStatus(
        ctx.contract,
        codeProposal,
        true,
        (net.now() + 86400) as uint32,
        0,
        VOTE_HASH_CODE_PROPOSAL,
    );

    val codeProposalView = getProposalOrNull(ctx.contract, codeProposalHash);
    expect(codeProposalView == null).toEqual(false);
    expect(codeProposalView!.value).toEqual(codeProposalValue);

    val acceptedCodeVote = voteUntilAccepted(ctx, codeProposalHash);
    expect(ctx.contract.getProposal(codeProposalHash as int)).toBeNull();
    expect(hasSetCodeAction(acceptedCodeVote, ctx.contract.address)).toEqual(true);

    val regularValue = beginCell()
        .storeSlice("Test Cell".beginParse())
        .storeUint(777, 32)
        .endCell();
    val regularProposal = createProposal(-42, regularValue, 0);
    val regularHash = injectProposalStatus(
        ctx.contract,
        regularProposal,
        false,
        (net.now() + 86400) as uint32,
        0,
        VOTE_HASH_REGULAR_PARAM,
    );

    voteUntilAccepted(ctx, regularHash);

    expect(ctx.contract.getProposal(regularHash as int)).toBeNull();
    assertConfigParam(ctx.contract, -42, regularValue);
}

get fun `test voting: custom-slot proposals should not change slots even if proposal statuses exist`() {
    val ctx = setupConfigTest();

    val slotProposalValue = beginCell().storeSlice("Hop hey!".beginParse()).endCell();
    val originalSlotValue = beginCell().storeSlice("Hop hey La La Ley!".beginParse()).endCell();

    var slotHashes = array<uint256> [];

    val slots = customSlots();
    var i = 0;
    while (i < slots.size()) {
        val slot = slots.get(i);
        val proposal = createProposal(slot, slotProposalValue, 0);
        val hash = injectProposalStatus(
            ctx.contract,
            proposal,
            false,
            (net.now() + 86400) as uint32,
            0,
            slot == CUSTOM_SLOT_1 ? VOTE_HASH_CUSTOM_SLOT_1 : VOTE_HASH_CUSTOM_SLOT_2,
        );
        slotHashes.push(hash);
        i += 1;
    }

    val codeProposal = createProposal(
        -1000,
        beginCell().storeRef(activeCode(ctx.contract.address)).endCell(),
        0,
    );

    val codeHash = injectProposalStatus(
        ctx.contract,
        codeProposal,
        true,
        (net.now() + 86400) as uint32,
        0,
        VOTE_HASH_CODE_PROPOSAL,
    );

    voteUntilAccepted(ctx, codeHash);
    expect(ctx.contract.getProposal(codeHash as int)).toBeNull();

    i = 0;
    while (i < slots.size()) {
        val slot = slots.get(i);
        val setSlotRes = ctx
            .contract
            .sendSetCustomParamRequest(
                ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
                i as uint64,
                slot,
                ctx.deployer.address,
                originalSlotValue,
                { value: ton("10"), bounce: true },
            );

        expect(setSlotRes).toHaveTx({
            from: ctx.contract.address,
            to: ctx.deployer.address,
            opcode: TAG_SET_CUSTOM_PARAM_ACCEPTED,
        });
        assertConfigParam(ctx.contract, slot, originalSlotValue);

        i += 1;
    }

    i = 0;
    while (i < slotHashes.size()) {
        val hash = slotHashes.get(i);
        val slot = slots.get(i);

        voteUntilAccepted(ctx, hash);
        expect(ctx.contract.getProposal(hash as int)).toBeNull();
        assertConfigParam(ctx.contract, slot, originalSlotValue);

        i += 1;
    }
}

get fun `test voting invariant: duplicate vote from same validator should return status -2`() {
    val ctx = setupConfigTest();

    val proposal = createProposal(
        -55,
        beginCell().storeSlice("dup-vote".beginParse()).endCell(),
        0,
    );
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 86400) as uint32,
        0,
        VOTE_HASH_DUPLICATE_CASE,
    );

    val first = sendSignedVote(ctx, 0, hash, 5);
    expect(first).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE + 2) as uint32,
    });

    val second = sendSignedVote(ctx, 0, hash, 6);
    expect(second).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE - 2) as uint32,
    });

    expect(ctx.contract.getProposal(hash as int) == null).toEqual(false);
}

get fun `test voting unit: set_next_validators should accept elector and reject non-elector in masterchain`() {
    val ctx = setupConfigTest();

    val newVset = buildValidatorSetCell(ctx.validators, 20);

    val fakeElector = differentAddress(ctx.electorAddress);
    net.topUp(fakeElector, ton("100"));

    val reject = ctx
        .contract
        .sendSetNextValidatorSetRequest(
            fakeElector,
            1,
            newVset,
            { value: ton("10"), bounce: true },
        );
    expect(reject).toHaveTx({
        from: ctx.contract.address,
        to: fakeElector,
        opcode: TAG_SET_NEXT_VALIDATORS_REJECTED,
    });

    val accepted = ctx
        .contract
        .sendSetNextValidatorSetRequest(
            ctx.electorAddress,
            2,
            newVset,
            { value: ton("10"), bounce: true },
        );

    expect(accepted).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: TAG_SET_NEXT_VALIDATORS_ACCEPTED,
    });

    assertConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET, newVset);

    net.setNow(net.now() + 5000);
    net.runTickTock(ctx.contract.address, false);

    assertConfigParam(ctx.contract, CONFIG_PARAM_CURRENT_VALIDATOR_SET, newVset);
    expect(getConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET)).toBeNull();
}
