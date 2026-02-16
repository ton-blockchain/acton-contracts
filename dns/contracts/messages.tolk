import "storage"

type TransferForwardPayload = RemainingBitsAndRefs

// type InlineString = string

// fun InlineString.unpackFromSlice(mutate s: slice): InlineString {
//     return s.loadRef().beginParse() as InlineString;
// }

struct (0x00000000) DeployDnsDomain {
    payload: RemainingBitsAndRefs
}

struct (0x370fec51) FillUp {
    queryId: uint64
}

struct (0x557cea20) OutbidNotification {
    queryId: uint64
}

struct (0x05138d91) OwnershipAssigned {
    queryId: uint64
    oldOwnerAddress: address?
    payload: TransferForwardPayload
}

struct (0xd53276db) Excesses {
    queryId: uint64
}

struct (0x2fcb26a2) GetStaticData {
    queryId: uint64
}

struct (0x8b771735) ReportStaticData {
    queryId: uint64
    itemIndex: uint256
    collectionAddress: address
}

struct (0xba93) DnsNextResolver {
    resolver: address
}

struct TransferOwnershipData {
    newOwnerAddress: address
    responseDestination: address?
    customPayload: cell?
    forwardAmount: coins
    forwardPayload: TransferForwardPayload
}

struct (0x5fcc3d14) TransferOwnership {
    queryId: uint64
    transferData: TransferOwnershipData
}

struct (0x1a0b9d51) EditContent {
    queryId: uint64
    newContent: Cell<DnsRecords>
}

struct (0x4eb1f0f9) ChangeDnsRecord {
    queryId: uint64
    key: uint256
    // func impl uses imperative parsing here
    // value: cell?
    value: RemainingBitsAndRefs
}

struct (0x44beae41) ProcessGovernanceDecision {
    queryId: uint64
}

struct (0x4ed14b65) DnsRecordRelease {
    queryId: uint64
}

struct ItemInitData {
    fromAddress: address
    domain: Cell<slice>
}

struct (0x00) GovernanceTransfer {
    transferData: TransferOwnershipData
}

struct (0x01) GovernanceRelease {}

struct (0x00000000) Op0WithQuery {
    queryId: uint64
}

struct MessageHeader {
    op: uint32
    queryId: uint64
    rest: RemainingBitsAndRefs
}
