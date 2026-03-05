import "types"

const COMMENT_APPROVE = "approve".literalSlice()

struct (0x00000000) Op0WithRemainder {
    remainder: RemainingBitsAndRefs
}

// if signer wants to approve, he will provide his index;
// just false otherwise
type SignerIndexOnInit = uint8?

struct (0xf1381e5b) SendMessageAction {
    mode: uint8
    message: cell
}

struct (0x1d0cfbd3) UpdateMultisigParamsAction {
    threshold: uint8
    signers: NonEmptyIndexedAddressMap
    proposers: IndexedAddressMap
}

struct (0xf718510f) NewOrderRequest {
    queryId: uint64
    orderSeqno: uint256
    signer: bool
    index: uint8
    expirationDate: uint48
    order: NonEmptyOrderActionsMap
}

struct (0x75097f5d) ExecuteOrderRequest {
    queryId: uint64
    orderSeqno: uint256
    expirationDate: uint48
    approvalsNum: uint8
    signersHash: uint256
    order: NonEmptyOrderActionsMap
}

struct (0xa32c59bf) ExecuteInternalRequest {
    queryId: uint64
    order: NonEmptyOrderActionsMap
}

struct (0x9c73fba2) InitOrderRequest {
    queryId: uint64
    threshold: uint8
    signers: NonEmptyIndexedAddressMap
    expirationDate: uint48
    order: NonEmptyOrderActionsMap
    signerIndexOnInit: SignerIndexOnInit
}

struct (0xa762230f) ApproveRequest {
    queryId: uint64
    signerIndex: uint8
}

struct (0x82609bf6) ApproveAccepted {
    queryId: uint64
}

struct (0xafaf283e) ApproveRejected {
    queryId: uint64
    exitCode: uint32
}
