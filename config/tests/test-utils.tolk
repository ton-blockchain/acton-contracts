import "@stdlib/exotic-cells"
import "@stdlib/lisp-lists"
import "@acton/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "@acton/types/out_actions"
import "@acton/types/transaction"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/Config.gen"

const CUSTOM_SLOT_1 = -1024
const CUSTOM_SLOT_2 = -1025
const DEFAULT_QUERY_ID = 0
const DEFAULT_PROPOSAL_VALUE = ton("100")
const DEFAULT_VOTE_VALUE = ton("10")

const VOTE_HASH_CODE_PROPOSAL = 0x1001
const VOTE_HASH_REGULAR_PARAM = 0x1002
const VOTE_HASH_CUSTOM_SLOT_1 = 0x1003
const VOTE_HASH_CUSTOM_SLOT_2 = 0x1004
const VOTE_HASH_DUPLICATE_CASE = 0x1005
const VOTE_HASH_UNKNOWN_CASE = 0xDEAD

const EXTERNAL_VALID_UNTIL_FUTURE = 1710003600
const EXTERNAL_VALID_UNTIL_PAST = 1709990000
const UINT256_MAX = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

struct ValidatorFixture {
    keyPair: KeyPair
    weight: int
}

struct ConfigTestContext {
    contract: Config
    deployer: Treasury
    outsider: Treasury
    proposer: address
    validatorSender: address
    validators: array<ValidatorFixture>
    electorAddress: address
}

struct ProposalTupleView {
    expires: int
    critical: bool
    paramId: int
    value: cell?
    expectedHash: int
}

struct ProposalFullView {
    expires: int
    critical: bool
    paramId: int
    value: cell?
    expectedHash: int
    validatorSetId: int
    voters: lisp_list<int>
    remainingWeight: int
    roundsRemaining: int
    wins: int
    losses: int
}

fun customSlots(): array<int32> {
    return [CUSTOM_SLOT_1, CUSTOM_SLOT_2];
}

fun buildVotingSetup(): cell {
    val normal = ConfigProposalSetup {
        minTotalRounds: 2,
        maxTotalRounds: 12,
        minWins: 2,
        maxLosses: 10,
        minStoreSec: 30,
        maxStoreSec: 3 * 86400,
        bitPrice: 1,
        cellPrice: 1,
    };

    val critical = ConfigProposalSetup {
        minTotalRounds: 3,
        maxTotalRounds: 16,
        minWins: 3,
        maxLosses: 14,
        minStoreSec: 30,
        maxStoreSec: 3 * 86400,
        bitPrice: 1,
        cellPrice: 1,
    };

    return ConfigVotingSetup {
        normalParams: normal.toCell(),
        criticalParams: critical.toCell(),
    }.toCell();
}

fun buildVotingSetupWith(normal: ConfigProposalSetup, critical: ConfigProposalSetup): cell {
    return ConfigVotingSetup {
        normalParams: normal.toCell(),
        criticalParams: critical.toCell(),
    }.toCell();
}

fun buildCriticalParamsCell(): cell {
    var criticalMap: map<int32, slice> = [];
    criticalMap.set(-1000, beginCell().toSlice());
    return criticalMap.toLowLevelDict()!;
}

fun buildValidators(count: int = 1): array<ValidatorFixture> {
    var validators = array<ValidatorFixture> [];
    var i = 0;
    while (i < count) {
        validators.push(ValidatorFixture {
            keyPair: crypto.seedToKeyPair((i + 1)),
            weight: 1,
        });
        i += 1;
    }
    return validators;
}

fun buildValidatorsWithWeights(weights: array<int>): array<ValidatorFixture> {
    var validators = array<ValidatorFixture> [];
    var i = 0;
    while (i < weights.size()) {
        validators.push(ValidatorFixture {
            keyPair: crypto.seedToKeyPair((i + 1)),
            weight: weights.get(i),
        });
        i += 1;
    }
    return validators;
}

fun totalValidatorWeight(validators: array<ValidatorFixture>): int {
    var total = 0;
    var i = 0;
    while (i < validators.size()) {
        total += validators.get(i).weight;
        i += 1;
    }
    return total;
}

fun validatorsToRawDict(validators: array<ValidatorFixture>): dict {
    var validatorMap: map<uint16, slice> = [];

    var i = 0;
    while (i < validators.size()) {
        val validator = validators.get(i);
        validatorMap.set(
            i,
            ValidatorDescrSimple {
                pubkeyTag: OP_ED25519_PUBKEY,
                publicKey: validator.keyPair.publicKey,
                weight: validator.weight,
            }.toCell()
                .beginParse(),
        );
        i += 1;
    }

    return validatorMap.toLowLevelDict();
}

fun buildValidatorSetCell(validators: array<ValidatorFixture>, round: int = 0): cell {
    val now = testing.getNow();
    val since = now + 100 + (round * 100);
    val until = since + 65536;

    return ValidatorSetExt {
        utimeSince: since,
        utimeUntil: until,
        total: validators.size(),
        main: validators.size(),
        totalWeight: totalValidatorWeight(validators),
        validators: validatorsToRawDict(validators),
    }.toCell();
}

fun applyCurrentValidatorSet(validators: array<ValidatorFixture>, round: int = 0): cell {
    var config = testing.getConfig();
    val vset = buildValidatorSetCell(validators, round);
    config.setParamRaw(CONFIG_PARAM_CURRENT_VALIDATOR_SET, vset);
    expect(testing.setConfig(config)).toEqual(true);
    return vset;
}

fun currentThreshold(): int {
    val currentVset = testing.getConfig().getParamRaw(CONFIG_PARAM_CURRENT_VALIDATOR_SET);
    val parsed = ValidatorSetExt.fromCell(currentVset);
    return (parsed.totalWeight * VOTE_WEIGHT_THRESHOLD_NUMERATOR) /
    VOTE_WEIGHT_THRESHOLD_DENOMINATOR;
}

fun getElectorAddress(config: BlockchainConfigMap): address {
    val electorHash = config
        .getParamRaw(CONFIG_PARAM_ELECTOR_ADDRESS)
        .beginParse()
        .preloadUint(256);
    return address.fromWorkchainAndHash(MASTERCHAIN, electorHash);
}

fun setupConfigTest(): ConfigTestContext {
    testing.setNow(1710000000);

    val deployer = testing.treasury("cfg-deployer");
    val outsider = testing.treasury("cfg-outsider");
    val proposer = randomAddress("cfg_proposer", MASTERCHAIN);
    val validatorSender = randomAddress("cfg_validator_sender", MASTERCHAIN);

    val validators = buildValidators();

    var config = testing.getConfig();
    config.setParamRaw(CONFIG_PARAM_VOTING_SETUP, buildVotingSetup());
    config.setParamRaw(CONFIG_PARAM_CRITICAL_PARAMS, buildCriticalParamsCell());
    config.setParamRaw(CONFIG_PARAM_CURRENT_VALIDATOR_SET, buildValidatorSetCell(validators, 0));
    expect(testing.setConfig(config)).toEqual(true);

    val electorAddress = getElectorAddress(config);

    testing.topUp(ADMIN_ADDRESS_FOR_CUSTOM_PARAMS, ton("1000"));
    testing.topUp(electorAddress, ton("1000"));
    testing.topUp(proposer, ton("1000"));
    testing.topUp(validatorSender, ton("1000"));

    val storageConfig = createMapFromLowLevelDict<int32, cell>(config.toLowLevelDict());
    val contract = Config.fromStorage(Storage {
        config: storageConfig,
        storedSeqno: 0,
        publicKey: 0,
        voteDict: [],
    });

    val deploy = contract.deploy(deployer.address, { value: ton("1000"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: contract.address });

    return ConfigTestContext {
        contract,
        deployer,
        outsider,
        proposer,
        validatorSender,
        validators,
        electorAddress,
    };
}

fun activeShardAccount(addr: address): TlbShardAccount {
    val shard = testing.getShardAccount(addr);
    if (shard != null) {
        return shard!;
    }
    Assert.fail("Expected TlbShardAccount");
}

fun activeAccountInfo(addr: address): TlbAccountInfo {
    val account = activeShardAccount(addr).account.load();
    if (account is TlbAccountInfo) {
        return account;
    }
    Assert.fail("Expected TlbAccountInfo");
}

fun activeCode(addr: address): cell {
    val info = activeAccountInfo(addr);
    if (info.storage.state is TlbAccountStateActive) {
        return info.storage.state.stateInit.code!;
    }
    Assert.fail("Expected active account state");
}

fun activeDataCell(addr: address): cell {
    val info = activeAccountInfo(addr);
    if (info.storage.state is TlbAccountStateActive) {
        val active = info.storage.state;
        if (active.stateInit.data == null) {
            Assert.fail("Expected active state data");
        }
        return active.stateInit.data!;
    }
    Assert.fail("Expected active account state");
}

fun setActiveDataCell(addr: address, newData: cell) {
    var updatedShard = activeShardAccount(addr);
    val account = updatedShard.account.load();
    if (account !is TlbAccountInfo) {
        Assert.fail("Expected TlbAccountInfo when setting data");
    }

    var info = account;
    if (info.storage.state !is TlbAccountStateActive) {
        Assert.fail("Expected TlbAccountStateActive when setting data");
    }

    var active = info.storage.state;
    active.stateInit.data = newData;
    info.storage.state = active;
    updatedShard.account = info.toCell() as cell as Cell<TlbAccount>;
    testing.setShardAccount(addr, updatedShard);
}

fun getStorage(contract: Config): Storage {
    return Storage.fromCell(activeDataCell(contract.address));
}

fun setStorage(contract: Config, storage: Storage) {
    setActiveDataCell(contract.address, storage.toCell());
}

fun contractDataHash(contract: Config): uint256 {
    return activeDataCell(contract.address).hash();
}

fun getConfigParam(contract: Config, paramId: int32): cell? {
    val storage = getStorage(contract);
    return storage.config.getById(paramId);
}

fun assertConfigParam(contract: Config, paramId: int32, expected: cell) {
    val value = getConfigParam(contract, paramId);
    expect(value).toEqual(expected);
}

fun differentAddress(addr: address): address {
    var candidate = randomAddress(null, addr.getWorkchain());
    while (candidate == addr) {
        candidate = randomAddress(null, addr.getWorkchain());
    }
    return candidate;
}

fun proposalHash(proposal: ConfigProposal): uint256 {
    return proposal.toCell().hash();
}

fun parseProposal(raw: tuple): ProposalTupleView {
    val paramTuple = raw.get(2) as tuple;

    return ProposalTupleView {
        expires: raw.get(0) as int,
        critical: raw.get(1) as bool,
        paramId: paramTuple.get(0) as int,
        value: paramTuple.get(1) as cell?,
        expectedHash: paramTuple.get(2) as int,
    };
}

fun parseProposalFull(raw: tuple): ProposalFullView {
    val paramTuple = raw.get(2) as tuple;
    return ProposalFullView {
        expires: raw.get(0) as int,
        critical: raw.get(1) as bool,
        paramId: paramTuple.get(0) as int,
        value: paramTuple.get(1) as cell?,
        expectedHash: paramTuple.get(2) as int,
        validatorSetId: raw.get(3) as int,
        voters: raw.get(4) as lisp_list<int>,
        remainingWeight: raw.get(5) as int,
        roundsRemaining: raw.get(6) as int,
        wins: raw.get(7) as int,
        losses: raw.get(8) as int,
    };
}

fun getProposalOrNull(contract: Config, hash: uint256): ProposalTupleView? {
    val raw = contract.getProposal(hash);
    if (raw == null) {
        return null;
    }
    return parseProposal(raw!);
}

fun getProposalFullOrNull(contract: Config, hash: uint256): ProposalFullView? {
    val raw = contract.getProposal(hash);
    if (raw == null) {
        return null;
    }
    return parseProposalFull(raw!);
}

fun proposalVotersCount(view: ProposalFullView): int {
    return view.voters.calculateSize();
}

fun createProposal(paramId: int32, value: cell?, expectedHash: uint256? = null): ConfigProposal {
    return ConfigProposal {
        paramId,
        paramValue: value,
        ifHashEqual: expectedHash,
    };
}

fun submitProposal(
    ctx: ConfigTestContext,
    proposal: ConfigProposal,
    critical: bool,
    expireInSec: int = 86400,
    queryId: uint64 = DEFAULT_QUERY_ID,
): (SendResultList, uint256) {
    val res = ctx
        .contract
        .sendNewVotingProposalRequest(
            ctx.proposer,
            queryId,
            (testing.getNow() + expireInSec),
            critical,
            proposal,
            { value: DEFAULT_PROPOSAL_VALUE, bounce: true },
        );
    return (res, proposalHash(proposal));
}

fun buildSignedVoteMessage(
    privateKey: int,
    validatorIndex: int,
    hash: uint256,
    queryId: uint64,
): cell {
    val signedPayload = SignedVotePayload {
        validatorIndex: validatorIndex as uint16,
        proposalHash: hash,
    }.toCell();

    val signature = crypto.rawSign(privateKey, signedPayload.beginParse().bitsHash());

    return beginCell()
        .storeUint(OP_VOTE_FOR_PROPOSAL, 32)
        .storeUint(queryId, 64)
        .storeSlice(signature)
        .storeSlice(signedPayload.beginParse())
        .endCell();
}

fun precomputedVoteSignature(hash: uint256, validatorIndex: int): slice {
    if (validatorIndex != 0) {
        Assert.fail("Only validator index 0 is supported for precomputed signatures");
    }

    var hi = 0;
    var lo = 0;

    if (hash == VOTE_HASH_CODE_PROPOSAL) {
        hi = 0x2111629a827d8f81861aa03ba9d9780514ea1c4dff6a06b5a7a788e4de9f34b1;
        lo = 0x1ede6ab9321d26e2c30cec0ee27b4ccdc3aab3d82f93fc7bdc0e173b77ee9509;
    } else if (hash == VOTE_HASH_REGULAR_PARAM) {
        hi = 0xf9a5213cfd071575a5dfd930428cd93b34d23e5419d11f540ba7fb9f23515597;
        lo = 0x5524a9bd700df0277f1c4081d501d1fc0469dd6838b0f1aa167d1c890f26a20b;
    } else if (hash == VOTE_HASH_CUSTOM_SLOT_1) {
        hi = 0x03458b2d8f384d5d647a211e49bde55ff035b7cd376d8c3c7f00feaef3a20085;
        lo = 0xe529f1bc4cb72a16f984a2450f8f38c52de32db9adc4bec789a0c7b29d7e500a;
    } else if (hash == VOTE_HASH_CUSTOM_SLOT_2) {
        hi = 0xe5d60028e3997e1fb62258c771378cc21cb8723fc9edbf8b8256a6edf8426d4d;
        lo = 0x9c7eb1da11da13578b9b2139c722251928a7c25b97a7695ffe9f41485e50610d;
    } else if (hash == VOTE_HASH_DUPLICATE_CASE) {
        hi = 0x05bf993c6655a388752969c3b9ad1d3eae03df3d8407598483a0ac9f62e769d4;
        lo = 0x45f35f6d6c21a5ab2de723d976d0dab7fdf1aa6017a71eca26c85389a8a5e80d;
    } else if (hash == VOTE_HASH_UNKNOWN_CASE) {
        hi = 0xdbf1698bed7a613a43e53a4f3314b569fcb28124e0ee60daac6be0f5fc722ac7;
        lo = 0x4cd70bab475144fa4e8bd93575671b551d0fe2d150216a4adf24af70e0950d05;
    } else {
        Assert.fail("Missing precomputed signature for proposal hash");
    }

    return beginCell().storeUint(hi, 256).storeUint(lo, 256).endCell().beginParse();
}

fun precomputedExternalVoteSignature(
    hash: uint256,
    seqno: int,
    validUntil: int,
    validatorIndex: int,
): slice {
    if (validatorIndex != 0) {
        Assert.fail("Only validator index 0 is supported for precomputed signatures");
    }

    var hi = 0;
    var lo = 0;

    if (
        hash == VOTE_HASH_CODE_PROPOSAL && seqno == 0 && validUntil == EXTERNAL_VALID_UNTIL_FUTURE
    ) {
        hi = 0x916e4641b5409c9e35b3cd245355c6b993e06bd5f0227a487cf9647673899e09;
        lo = 0xde69aec6109acc3f5c01368217003a1bdf0b0217952307d6269333e49210fd06;
    } else if (
        hash == VOTE_HASH_REGULAR_PARAM && seqno == 0 && validUntil == EXTERNAL_VALID_UNTIL_FUTURE
    ) {
        hi = 0x46d092a6441a254062f676cb5653a44d0b2371dedfc847a3fb97bb260828c107;
        lo = 0x74fa40e215f6cb9f36c228e3622ec4f48010c30db6fffd602425446f25cf6103;
    } else if (
        hash == VOTE_HASH_REGULAR_PARAM && seqno == 1 && validUntil == EXTERNAL_VALID_UNTIL_FUTURE
    ) {
        hi = 0x79c38aec1c1690cb7844f608c8fe2dc93f82ea7ad7b6a9f27c009a6d8850cfe6;
        lo = 0x5948752936a95d89bcb7b6712b0a5a676c20fc02dcfcc4bd41094c8c4e9a1107;
    } else if (
        hash == VOTE_HASH_REGULAR_PARAM && seqno == 5 && validUntil == EXTERNAL_VALID_UNTIL_FUTURE
    ) {
        hi = 0x23e6382c073c3e0842008cd6d49095557b3aeb8cdb5f3e1691bd7ba4e59787e9;
        lo = 0x67b439a9f93434e255b57cec1d4f9c9149448802cdd8d56e621b7ece9f719101;
    } else if (
        hash == VOTE_HASH_REGULAR_PARAM && seqno == 0 && validUntil == EXTERNAL_VALID_UNTIL_PAST
    ) {
        hi = 0x71e3881eb85fb4fe6e60f10cb246b00a4df8cc220681b7ff0a9510a01c84cd4c;
        lo = 0xd292df882d68ad96220baa86642fa54cdcfe81cd8ff24e40dc0ff332bd7a590a;
    } else if (
        hash == VOTE_HASH_CUSTOM_SLOT_1 && seqno == 0 && validUntil == EXTERNAL_VALID_UNTIL_FUTURE
    ) {
        hi = 0x2e878ac7b84d6bab5beab3ed61aed1f73626670361a161f9457d311a6f6fe71b;
        lo = 0xc7cd06f6a23fa289ab7359eb9fe43be0cfa9ce215a61a770a8c15e6b515a8208;
    } else if (
        hash == VOTE_HASH_CUSTOM_SLOT_2 && seqno == 0 && validUntil == EXTERNAL_VALID_UNTIL_FUTURE
    ) {
        hi = 0xc5866eb9440444a7cf067aa391a65327a0bb841dbddba539948da06f574ba08e;
        lo = 0x214495a967c1dbf343f51af2526a980d09c228c9b919278a8fdb4d4f45e95507;
    } else if (
        hash == VOTE_HASH_UNKNOWN_CASE && seqno == 0 && validUntil == EXTERNAL_VALID_UNTIL_FUTURE
    ) {
        hi = 0xdbf1698bed7a613a43e53a4f3314b569fcb28124e0ee60daac6be0f5fc722ac7;
        lo = 0x4cd70bab475144fa4e8bd93575671b551d0fe2d150216a4adf24af70e0950d05;
    } else {
        Assert.fail("Missing precomputed external signature vector");
    }

    return beginCell().storeUint(hi, 256).storeUint(lo, 256).endCell().beginParse();
}

fun buildExternalVoteBody(
    seqno: int,
    validUntil: int,
    validatorIndex: int,
    hash: uint256,
    signature: slice,
): cell {
    return beginCell()
        .storeSlice(signature)
        .storeUint(OP_VOTE_FOR_PROPOSAL, 32)
        .storeUint(seqno, 32)
        .storeUint(validUntil, 32)
        .storeUint(validatorIndex, 16)
        .storeUint(hash, 256)
        .endCell();
}

fun sendExternalRaw(contract: Config, body: cell): SendResultList {
    val res = trySendExternalRaw(contract, body);
    if (res == null) {
        Assert.fail("External message was not accepted for execution");
    }
    return res!;
}

fun trySendExternalRaw(contract: Config, body: cell): SendResultList? {
    val msg = net.createExternalMessage(contract.address, body.beginParse());
    return net.sendExternal(msg);
}

fun sendExternalVote(
    ctx: ConfigTestContext,
    seqno: int,
    validUntil: int,
    validatorIndex: int,
    hash: uint256,
): SendResultList {
    val sig = precomputedExternalVoteSignature(hash, seqno, validUntil, validatorIndex);
    val body = buildExternalVoteBody(seqno, validUntil, validatorIndex, hash, sig);
    return sendExternalRaw(ctx.contract, body);
}

fun sendExternalVoteWithSignature(
    ctx: ConfigTestContext,
    seqno: int,
    validUntil: int,
    validatorIndex: int,
    hash: uint256,
    signature: slice,
): SendResultList {
    val body = buildExternalVoteBody(seqno, validUntil, validatorIndex, hash, signature);
    return sendExternalRaw(ctx.contract, body);
}

fun sendSignedVote(
    ctx: ConfigTestContext,
    validatorIndex: int,
    hash: uint256,
    queryId: uint64 = DEFAULT_QUERY_ID,
): SendResultList {
    val signature = precomputedVoteSignature(hash, validatorIndex);
    val payload = SignedVotePayload {
        validatorIndex: validatorIndex as uint16,
        proposalHash: hash,
    }.toCell();

    val msgBody = beginCell()
        .storeUint(OP_VOTE_FOR_PROPOSAL, 32)
        .storeUint(queryId, 64)
        .storeSlice(signature)
        .storeSlice(payload.beginParse())
        .endCell();

    return ctx
        .contract
        .sendAny(ctx.validatorSender, msgBody, { value: DEFAULT_VOTE_VALUE, bounce: true });
}

fun voteUntilAccepted(ctx: ConfigTestContext, hash: uint256): SendResultList {
    var round = 0;
    var guard = 0;

    while (guard < 128) {
        var i = 0;
        while (i < ctx.validators.size()) {
            val res = sendSignedVote(ctx, i, hash, ((round << 16) + i));
            expect(res).toHaveTx({
                from: ctx.validatorSender,
                to: ctx.contract.address,
                opcode: OP_VOTE_FOR_PROPOSAL,
            });

            if (ctx.contract.getProposal(hash) == null) {
                return res;
            }

            guard += 1;
            i += 1;
        }

        round += 1;
        applyCurrentValidatorSet(ctx.validators, round);
    }

    Assert.fail("voteUntilAccepted guard limit reached");
}

fun hasSetCodeAction(res: SendResultList, account: address): bool {
    var i = 0;
    while (i < res.size()) {
        val item = res.at(i);
        val tx = item.tx.load();

        if (tx.getAccountAddress() == account) {
            val actions = item.allOutActions();
            var j = 0;
            while (j < actions.size()) {
                if (actions.at(j) is TlbOutActionSetCode) {
                    return true;
                }
                j += 1;
            }
        }

        i += 1;
    }

    return false;
}

fun injectProposalStatus(
    contract: Config,
    proposal: ConfigProposal,
    isCritical: bool,
    expiresAt: uint32,
    wins: uint8 = 0,
    fixedHash: uint256? = null,
    roundsRemaining: uint8 = 20,
    losses: uint8 = 0,
): uint256 {
    val hash = fixedHash == null ? proposalHash(proposal) : fixedHash!;

    var storage = getStorage(contract);
    val currentVset = testing.getConfig().getParamRaw(CONFIG_PARAM_CURRENT_VALIDATOR_SET);

    storage
        .voteDict
        .set(
            hash,
            ConfigProposalStatus {
                expires: expiresAt,
                proposal: proposal.toCell(),
                isCritical,
                voters: [],
                remainingWeight: currentThreshold(),
                validatorSetId: currentVset.hash(),
                roundsRemaining,
                wins,
                losses,
            }.toCell()
                .beginParse(),
        );

    setStorage(contract, storage);

    return hash;
}

fun setGlobalConfigParam(index: uint32, value: cell) {
    var config = testing.getConfig();
    config.setParamRaw(index, value);
    expect(testing.setConfig(config)).toEqual(true);
}

fun setStorageConfigParam(contract: Config, index: int32, value: cell?) {
    var storage = getStorage(contract);
    if (value == null) {
        storage.config.deleteById(index);
    } else {
        storage.config.setById(index, value!);
    }
    setStorage(contract, storage);
}

fun setVotingSetup(
    contract: Config,
    normal: ConfigProposalSetup,
    critical: ConfigProposalSetup,
) {
    val setupCell = buildVotingSetupWith(normal, critical);
    setGlobalConfigParam(CONFIG_PARAM_VOTING_SETUP, setupCell);
    setStorageConfigParam(contract, CONFIG_PARAM_VOTING_SETUP, setupCell);
}

fun setCustomSlotBody(
    slot: int32,
    value: cell,
    receiverAddress: address,
    queryId: uint64 = DEFAULT_QUERY_ID,
): cell {
    return SetCustomParamRequest {
        queryId,
        paramId: slot,
        receiverAddress,
        value,
    }.toCell();
}

fun setNextValidatorsBody(vset: cell, queryId: uint64 = DEFAULT_QUERY_ID): cell {
    return SetNextValidatorSetRequest { queryId, vset }.toCell();
}

fun proposalCount(contract: Config): int {
    return contract.listProposals().calculateSize();
}

fun emptyOrDifferent(slotValue: cell?, expected: cell): bool {
    if (slotValue == null) {
        return true;
    }
    return slotValue!.hash() != expected.hash();
}
