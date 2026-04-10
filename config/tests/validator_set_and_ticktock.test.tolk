import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/types/big_array"
import "test_utils"
import "../contracts/messages"
import "../wrappers/ConfigContract"

get fun `test vset: should reject already-current set and accept future set`() {
    val ctx = setupConfigTest();

    val now = net.now();

    val currentLike = ValidatorSetExt {
        utimeSince: now,
        utimeUntil: (now + 4000),
        total: 1,
        main: 1,
        totalWeight: 1,
        validators: validatorsToRawDict(ctx.validators),
    }.toCell();

    val reject = ctx
        .contract
        .sendSetNextValidatorSetRequest(
            ctx.electorAddress,
            1,
            currentLike,
            { value: ton("10"), bounce: true },
        );

    expect(reject).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: TAG_SET_NEXT_VALIDATORS_REJECTED,
    });
    expect(getConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET)).toBeNull();

    val future = ValidatorSetExt {
        utimeSince: (now + 1000),
        utimeUntil: (now + 5000),
        total: 1,
        main: 1,
        totalWeight: 1,
        validators: validatorsToRawDict(ctx.validators),
    }.toCell();

    val accept = ctx
        .contract
        .sendSetNextValidatorSetRequest(
            ctx.electorAddress,
            2,
            future,
            { value: ton("10"), bounce: true },
        );

    expect(accept).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: TAG_SET_NEXT_VALIDATORS_ACCEPTED,
    });
    assertConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET, future);
}

get fun `test vset: should reject expired window and accept valid window`() {
    val ctx = setupConfigTest();

    val now = net.now();

    val badWindow = ValidatorSetExt {
        utimeSince: (now + 1000),
        utimeUntil: (now + 999),
        total: 1,
        main: 1,
        totalWeight: 1,
        validators: validatorsToRawDict(ctx.validators),
    }.toCell();

    val reject = ctx
        .contract
        .sendSetNextValidatorSetRequest(
            ctx.electorAddress,
            3,
            badWindow,
            { value: ton("10"), bounce: true },
        );

    expect(reject).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: TAG_SET_NEXT_VALIDATORS_REJECTED,
    });
    expect(getConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET)).toBeNull();

    val validWindow = ValidatorSetExt {
        utimeSince: (now + 1200),
        utimeUntil: (now + 6200),
        total: 1,
        main: 1,
        totalWeight: 1,
        validators: validatorsToRawDict(ctx.validators),
    }.toCell();

    val accept = ctx
        .contract
        .sendSetNextValidatorSetRequest(
            ctx.electorAddress,
            4,
            validWindow,
            { value: ton("10"), bounce: true },
        );

    expect(accept).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: TAG_SET_NEXT_VALIDATORS_ACCEPTED,
    });
    assertConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET, validWindow);
}

get fun `test ticktock invariant: should roll proposal round on validator-set change`() {
    val ctx = setupConfigTest();

    val customValidators = buildValidatorsWithWeights([1, 5]);
    val beforeVset = applyCurrentValidatorSet(customValidators, 0);

    val proposal = createProposal(-81, beginCell().storeSlice("tick".beginParse()).endCell(), 0);
    val hash = injectProposalStatus(
        ctx.contract,
        proposal,
        false,
        (net.now() + 3600),
        0,
        UINT256_MAX,
    );

    val before = getProposalFullOrNull(ctx.contract, hash);
    expect(before == null).toEqual(false);
    expect(before!.validatorSetId).toEqual(beforeVset.hash());
    expect(before!.losses).toEqual(0);

    val afterVset = applyCurrentValidatorSet(customValidators, 1);
    net.runTickTock(ctx.contract.address, false);

    val after = getProposalFullOrNull(ctx.contract, hash);
    expect(after == null).toEqual(false);
    expect(after!.validatorSetId).toEqual(afterVset.hash());
    expect(after!.roundsRemaining).toEqual(before!.roundsRemaining - 1);
    expect(after!.losses).toEqual(before!.losses + 1);
    expect(proposalVotersCount(after!)).toEqual(0);
}
