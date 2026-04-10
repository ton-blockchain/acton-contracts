import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/types/big_array"
import "test_utils"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/ConfigContract"

const CONFIG_E2E_REGULAR_PARAM = -420
const CONFIG_E2E_SPECIAL_PARAM = -999
const CONFIG_E2E_EXTERNAL_PUBLIC_KEY = 0x123456789abcdef

const CONFIG_E2E_INTERNAL_PROPOSAL_HASH = 0x95284c3f71134cc17c671d2c70f1dca970c822d2bb2a1754c5a18081c26dd80b
const CONFIG_E2E_EXTERNAL_PROPOSAL_HASH = 0xa4de818dea6c76d3a31f139f000c52660ebe6d6032bb0ed2d8c9848d0a887563

const CONFIG_E2E_CUSTOM_QUERY_ID = 9101
const CONFIG_E2E_INTERNAL_PROPOSAL_QUERY_ID = 9102
const CONFIG_E2E_FIRST_INTERNAL_VOTE_QUERY_ID = 9103
const CONFIG_E2E_FINAL_INTERNAL_VOTE_QUERY_ID = 9104
const CONFIG_E2E_SET_NEXT_VALIDATORS_QUERY_ID = 9105
const CONFIG_E2E_EXTERNAL_PROPOSAL_QUERY_ID = 9106
const CONFIG_E2E_SET_SECOND_NEXT_VALIDATORS_QUERY_ID = 9107

const CONFIG_E2E_EXTERNAL_VALID_UNTIL_FIRST = 1710004400
const CONFIG_E2E_EXTERNAL_VALID_UNTIL_SECOND = 1710004600

const CONFIG_E2E_INTERNAL_SIGNATURE_HI = 0x33f9689d00020f7b3e16917fa3832d496b79c0694414783d7f44e34130c68069
const CONFIG_E2E_INTERNAL_SIGNATURE_LO = 0x9efb2f9bbcdc151af8239fbffc1f63c775c817e26bc9c51a7f61cc875d141103
const CONFIG_E2E_EXTERNAL_SIGNATURE_FIRST_HI = 0xca7a0bb5983b1b04fe76bf755748807e6a23879b89cbeebe3220b3137896a589
const CONFIG_E2E_EXTERNAL_SIGNATURE_FIRST_LO = 0xf701bb436594d781e8dd05c72f56aa64514a65b02b3e2107051a34e195edfb08
const CONFIG_E2E_EXTERNAL_SIGNATURE_SECOND_HI = 0x9e27ce0930f1a8570299d273f751ed80fee7bef7956881a68237ee154f578b85
const CONFIG_E2E_EXTERNAL_SIGNATURE_SECOND_LO = 0xf564d1bea192f3c96731de007750e8b35d0228403c0f174d06062a15b544f50a

struct ConfigE2eProposalFixture {
    proposalHash: uint256
    paramId: int32
    value: cell
}

fun signatureSlice(hi: uint256, lo: uint256): slice {
    return beginCell().storeUint(hi, 256).storeUint(lo, 256).endCell().beginParse();
}

fun deployConfigStage(): ConfigTestContext {
    val ctx = setupConfigTest();

    expect(ctx.contract.seqno()).toEqual(0);
    expect(proposalCount(ctx.contract)).toEqual(0);
    expect(getConfigParam(ctx.contract, CONFIG_PARAM_CURRENT_VALIDATOR_SET)).toBeNotNull();
    expect(getStorage(ctx.contract).publicKey).toEqual(0);

    return ctx;
}

fun setCustomSlotStage(ctx: ConfigTestContext): cell {
    val customValue = beginCell().storeSlice("config-e2e-custom".beginParse()).endCell();

    val res = ctx
        .contract
        .sendSetCustomParamRequest(
            ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
            CONFIG_E2E_CUSTOM_QUERY_ID,
            CUSTOM_SLOT_1,
            ctx.deployer.address,
            customValue,
            { value: ton("10"), bounce: true },
        );

    expect(res).toHaveSuccessfulTx<SetCustomParamRequest>({
        from: ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
        to: ctx.contract.address,
    });
    expect(res).toHaveTx({
        from: ctx.contract.address,
        to: ctx.deployer.address,
        opcode: TAG_SET_CUSTOM_PARAM_ACCEPTED,
    });

    assertConfigParam(ctx.contract, CUSTOM_SLOT_1, customValue);
    expect(proposalCount(ctx.contract)).toEqual(0);

    return customValue;
}

fun createProposalStage(
    ctx: ConfigTestContext,
    paramId: int32,
    value: cell,
    expectedHash: uint256,
    queryId: uint64,
): ConfigE2eProposalFixture {
    val proposal = createProposal(paramId, value, 0);
    val (res, proposalHash) = submitProposal(ctx, proposal, false, 7200, queryId);

    expect(proposalHash).toEqual(expectedHash);
    expect(res).toHaveSuccessfulTx<NewVotingProposalRequest>({
        from: ctx.proposer,
        to: ctx.contract.address,
    });

    val stored = getProposalFullOrNull(ctx.contract, proposalHash);
    expect(stored!.value).toEqual(value);
    expect(stored!.wins).toEqual(0);
    expect(stored!.losses).toEqual(0);
    expect(proposalVotersCount(stored!)).toEqual(0);

    return {
        proposalHash,
        paramId,
        value,
    };
}

fun sendPrecomputedInternalVote(
    ctx: ConfigTestContext,
    proposalHash: uint256,
    queryId: uint64,
): SendResultList {
    val payload = SignedVotePayload {
        validatorIndex: 0,
        proposalHash,
    }.toCell();
    val body = beginCell()
        .storeUint(OP_VOTE_FOR_PROPOSAL, 32)
        .storeUint(queryId, 64)
        .storeSlice(
            signatureSlice(CONFIG_E2E_INTERNAL_SIGNATURE_HI, CONFIG_E2E_INTERNAL_SIGNATURE_LO),
        )
        .storeSlice(payload.beginParse())
        .endCell();

    return ctx
        .contract
        .sendAny(ctx.validatorSender, body, { value: DEFAULT_VOTE_VALUE, bounce: true });
}

fun sendPrecomputedExternalVote(
    ctx: ConfigTestContext,
    seqno: int,
    validUntil: int,
    proposalHash: uint256,
    signatureHi: uint256,
    signatureLo: uint256,
): SendResultList {
    return sendExternalVoteWithSignature(
        ctx,
        seqno,
        validUntil,
        0,
        proposalHash,
        signatureSlice(signatureHi, signatureLo),
    );
}

fun castFirstInternalVoteStage(ctx: ConfigTestContext, fixture: ConfigE2eProposalFixture) {
    val res = sendPrecomputedInternalVote(
        ctx,
        fixture.proposalHash,
        CONFIG_E2E_FIRST_INTERNAL_VOTE_QUERY_ID,
    );

    expect(res).toHaveTx({
        from: ctx.validatorSender,
        to: ctx.contract.address,
        opcode: OP_VOTE_FOR_PROPOSAL,
    });
    expect(res).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE + 2),
    });

    val proposal = getProposalFullOrNull(ctx.contract, fixture.proposalHash);
    expect(proposal == null).toEqual(false);
    expect(proposal!.wins).toEqual(1);
    expect(proposal!.losses).toEqual(0);
    expect(proposalVotersCount(proposal!)).toEqual(1);
    expect(proposal!.remainingWeight < 0).toEqual(true);
}

fun rotateValidatorSetStage(ctx: ConfigTestContext, round: int, queryId: uint64): cell {
    val previousCurrent = getConfigParam(ctx.contract, CONFIG_PARAM_CURRENT_VALIDATOR_SET);
    expect(previousCurrent).toBeNotNull();

    val nextVset = buildValidatorSetCell(ctx.validators, round);
    val setNext = ctx
        .contract
        .sendSetNextValidatorSetRequest(
            ctx.electorAddress,
            queryId,
            nextVset,
            { value: ton("10"), bounce: true },
        );

    expect(setNext).toHaveSuccessfulTx<SetNextValidatorSetRequest>({
        from: ctx.electorAddress,
        to: ctx.contract.address,
    });
    expect(setNext).toHaveTx({
        from: ctx.contract.address,
        to: ctx.electorAddress,
        opcode: TAG_SET_NEXT_VALIDATORS_ACCEPTED,
    });

    assertConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET, nextVset);

    val parsed = ValidatorSetExt.fromCell(nextVset);
    net.setNow((parsed.utimeSince) + 1);
    net.runTickTock(ctx.contract.address, false);

    assertConfigParam(ctx.contract, CONFIG_PARAM_CURRENT_VALIDATOR_SET, nextVset);
    assertConfigParam(ctx.contract, CONFIG_PARAM_PREVIOUS_VALIDATOR_SET, previousCurrent!);
    expect(getConfigParam(ctx.contract, CONFIG_PARAM_NEXT_VALIDATOR_SET)).toBeNull();

    // Keep global validator config aligned with the contract's current round.
    setGlobalConfigParam(CONFIG_PARAM_CURRENT_VALIDATOR_SET, nextVset);

    return nextVset;
}

fun acceptInternalProposalStage(ctx: ConfigTestContext, fixture: ConfigE2eProposalFixture) {
    rotateValidatorSetStage(ctx, 1, CONFIG_E2E_SET_NEXT_VALIDATORS_QUERY_ID);

    val res = sendPrecomputedInternalVote(
        ctx,
        fixture.proposalHash,
        CONFIG_E2E_FINAL_INTERNAL_VOTE_QUERY_ID,
    );

    expect(res).toHaveTx({
        from: ctx.contract.address,
        to: ctx.validatorSender,
        opcode: (TAG_VOTE_PROCESSED_BASE + 6),
    });
    expect(ctx.contract.getProposal(fixture.proposalHash)).toBeNull();
    assertConfigParam(ctx.contract, fixture.paramId, fixture.value);
}

fun castFirstExternalVoteStage(ctx: ConfigTestContext, fixture: ConfigE2eProposalFixture) {
    val res = sendPrecomputedExternalVote(
        ctx,
        0,
        CONFIG_E2E_EXTERNAL_VALID_UNTIL_FIRST,
        fixture.proposalHash,
        CONFIG_E2E_EXTERNAL_SIGNATURE_FIRST_HI,
        CONFIG_E2E_EXTERNAL_SIGNATURE_FIRST_LO,
    );

    expect(res.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(1);

    val proposal = getProposalFullOrNull(ctx.contract, fixture.proposalHash);
    expect(proposal == null).toEqual(false);
    expect(proposal!.wins).toEqual(1);
    expect(proposalVotersCount(proposal!)).toEqual(1);
    expect(getStorage(ctx.contract).publicKey).toEqual(0);
}

fun acceptExternalSpecialProposalStage(ctx: ConfigTestContext, fixture: ConfigE2eProposalFixture) {
    rotateValidatorSetStage(ctx, 2, CONFIG_E2E_SET_SECOND_NEXT_VALIDATORS_QUERY_ID);

    val res = sendPrecomputedExternalVote(
        ctx,
        1,
        CONFIG_E2E_EXTERNAL_VALID_UNTIL_SECOND,
        fixture.proposalHash,
        CONFIG_E2E_EXTERNAL_SIGNATURE_SECOND_HI,
        CONFIG_E2E_EXTERNAL_SIGNATURE_SECOND_LO,
    );

    expect(res.size() > 0).toEqual(true);
    expect(ctx.contract.seqno()).toEqual(2);
    expect(ctx.contract.getProposal(fixture.proposalHash)).toBeNull();
    assertConfigParam(ctx.contract, fixture.paramId, fixture.value);
    expect(getStorage(ctx.contract).publicKey).toEqual(CONFIG_E2E_EXTERNAL_PUBLIC_KEY);
}

get fun `test config e2e bench: stage 1 deploy contract`() {
    deployConfigStage();
}

get fun `test config e2e bench: stage 2 set custom slot`() {
    val ctx = deployConfigStage();
    setCustomSlotStage(ctx);
}

get fun `test config e2e bench: stage 3 create proposal and record first internal vote`() {
    val ctx = deployConfigStage();
    setCustomSlotStage(ctx);

    val internalProposal = createProposalStage(
        ctx,
        CONFIG_E2E_REGULAR_PARAM,
        beginCell().storeSlice("config-e2e-internal".beginParse()).storeUint(7, 8).endCell(),
        CONFIG_E2E_INTERNAL_PROPOSAL_HASH,
        CONFIG_E2E_INTERNAL_PROPOSAL_QUERY_ID,
    );

    castFirstInternalVoteStage(ctx, internalProposal);
}
