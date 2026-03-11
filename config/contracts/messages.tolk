import "types"

const OP_SET_CUSTOM_PARAM = 0x6e43536c
const OP_SET_NEXT_VALIDATOR_SET = 0x4e565354
const OP_NEW_VOTING_PROPOSAL = 0x6e565052
const OP_VOTE_FOR_PROPOSAL = 0x566f7465
const OP_SIGNED_VOTE = 0x566f7445

const OP_ACTION_CHANGE_PARAM = 0x43665021
const OP_ACTION_CHANGE_CONFIG_CODE = 0x4e436f64
const OP_ACTION_CHANGE_MASTER_PUBKEY = 0x50624b21
const OP_ACTION_CHANGE_ELECTOR_CODE = 0x4e43ef05

const OP_CFG_PROPOSAL = 0xf3
const OP_CFG_VOTING_SETUP = 0x91
const OP_CFG_PROPOSAL_SETUP = 0x36
const OP_CFG_PROPOSAL_STATUS = 0xce

const OP_VALIDATOR_SET_EXT = 0x12
const OP_VALIDATOR_SIMPLE = 0x53
const OP_VALIDATOR_ADDR = 0x73
const OP_ED25519_PUBKEY = 0x8e81278a

const TAG_SET_NEXT_VALIDATORS_ACCEPTED = 0xee764f4b
const TAG_SET_NEXT_VALIDATORS_REJECTED = 0xee764f6f
const TAG_SET_CUSTOM_PARAM_ACCEPTED = 0xef764f4b
const TAG_SET_CUSTOM_PARAM_REJECTED = 0xef764f6f
const TAG_NEW_VOTING_CREATED = 0xee565052
const TAG_VOTE_PROCESSED_BASE = 0xd6745240

const ERROR_TAG_CUSTOM_SLOT_VOTING_REJECTED = -0xc3726956
const ERROR_TAG_BAD_CURRENT_VALUE_HASH = -0xe2646356
const ERROR_TAG_MANDATORY_PARAM_CANNOT_BE_NULL = -0xcd506e6c
const ERROR_TAG_BAD_VALUE = -0xc2616456
const ERROR_TAG_CRITICAL_FLAG_REQUIRED = -0xc3726954
const ERROR_TAG_CANNOT_DOWNGRADE_CRITICALITY = -0xc3726955
const ERROR_TAG_PROPOSAL_ALREADY_EXISTS = -0xc16c7245
const ERROR_TAG_PROPOSAL_EXPIRED = -0xc5787069
const ERROR_TAG_NOT_ENOUGH_FUNDS = -0xf0617924

const CONFIG_PARAM_ELECTOR_ADDRESS = 1
const CONFIG_PARAM_MANDATORY_PARAMS = 9
const CONFIG_PARAM_CRITICAL_PARAMS = 10
const CONFIG_PARAM_VOTING_SETUP = 11
const CONFIG_PARAM_PREVIOUS_VALIDATOR_SET = 32
const CONFIG_PARAM_CURRENT_VALIDATOR_SET = 34
const CONFIG_PARAM_NEXT_VALIDATOR_SET = 36

const PROPOSAL_EXTENSION_GRACE_PERIOD = 16384
const PROPOSAL_BITS_OVERHEAD = 1024
const PROPOSAL_REFS_OVERHEAD = 2

const VOTE_WEIGHT_THRESHOLD_NUMERATOR = 3
const VOTE_WEIGHT_THRESHOLD_DENOMINATOR = 4

const MIN_INTERNAL_MESSAGE_VALUE = 1 << 30
const INTERNAL_QUERY_HIGH_BIT = 1 << 31
const EXTERNAL_SEQNO_MODULO = 1 << 32

struct (0xf3) ConfigProposal {
    paramId: int32
    paramValue: cell?
    ifHashEqual: uint256?
}

struct (0x4e565354) SetNextValidatorSetRequest {
    queryId: uint64
    vset: cell
}

struct (0x6e43536c) SetCustomParamRequest {
    queryId: uint64
    paramId: int32
    receiverAddress: address
    value: cell
}

struct (0x6e565052) NewVotingProposalRequest {
    queryId: uint64
    expireAt: uint32
    critical: bool
    proposal: Cell<ConfigProposal>
}

struct (0x566f7445) SignedVotePayload {
    validatorIndex: uint16
    proposalHash: uint256
}

struct (0x566f7465) VoteForProposalRequest {
    queryId: uint64
    signature: bits512
    signedVoteBody: RemainingBitsAndRefs
}

fun VoteForProposalRequest.loadSignedVotePayload(self, throwCode: int): SignedVotePayload {
    return SignedVotePayload.fromSlice(
        self.signedVoteBody,
        { throwIfOpcodeDoesNotMatch: throwCode }
    );
}

type AllowedInternalMessage =
    | SetNextValidatorSetRequest
    | SetCustomParamRequest
    | NewVotingProposalRequest
    | VoteForProposalRequest

struct ExternalSignedMessage {
    signature: bits512
    signedBody: RemainingBitsAndRefs
}

struct ExternalActionHeader {
    action: uint32
    msgSeqno: uint32
    validUntil: uint32
}

struct (0x566f7465) ExternalVoteAction {
    msgSeqno: uint32
    validUntil: uint32
    validatorIndex: uint16
    proposalHash: uint256
}

struct (0x36) ConfigProposalSetup {
    minTotalRounds: uint8
    maxTotalRounds: uint8
    minWins: uint8
    maxLosses: uint8
    minStoreSec: uint32
    maxStoreSec: uint32
    bitPrice: uint32
    cellPrice: uint32
}

fun ConfigProposalSetup.calculateStoragePrice(self, seconds: int, bits: int, refs: int): int {
    return (self.bitPrice * (bits + PROPOSAL_BITS_OVERHEAD) +
    self.cellPrice * (refs + PROPOSAL_REFS_OVERHEAD)) *
    seconds;
}

struct (0x91) ConfigVotingSetup {
    normalParams: Cell<ConfigProposalSetup>
    criticalParams: Cell<ConfigProposalSetup>
}

fun ConfigVotingSetup.selectProposalSetup(self, critical: bool): ConfigProposalSetup {
    return critical ? self.criticalParams.load() : self.normalParams.load();
}

struct (0xce) ConfigProposalStatus {
    expires: uint32
    proposal: Cell<ConfigProposal>
    isCritical: bool
    voters: VotersDict
    remainingWeight: int64
    validatorSetId: uint256
    roundsRemaining: uint8
    wins: uint8
    losses: uint8
}

struct (0x12) ValidatorSetExt {
    utimeSince: uint32
    utimeUntil: uint32
    total: uint16
    main: uint16
    totalWeight: uint64
    validators: dict
}

struct (0x53) ValidatorDescrSimple {
    pubkeyTag: uint32
    publicKey: uint256
    weight: uint64
}

struct (0x73) ValidatorDescrWithAdnl {
    pubkeyTag: uint32
    publicKey: uint256
    weight: uint64
    adnlAddress: uint256
}

type ValidatorDescr = ValidatorDescrSimple | ValidatorDescrWithAdnl

struct (0x4e436f64) ElectorCodeChangeAction {
    queryId: uint64
    payload: RemainingBitsAndRefs
}

struct AnswerBody {
    ansTag: uint32
    queryId: uint64
}
