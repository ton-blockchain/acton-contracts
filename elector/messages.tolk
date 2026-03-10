import "types"

struct(0x00000000) SimpleTransfer { }

struct(0x4e73744b) NewStakeMessage {
    queryId: uint64;
    validatorPubkey: uint256;
    stakeAt: uint32;
    maxFactor: uint32;
    adnlAddr: uint256;
    signature: Cell<bits512>
}

struct(0x47657424) RecoverStakeRequest {
    queryId: uint64;
}

struct(0x4e436f64) UpgradeCode {
    queryId: uint64;
    newCode: cell;
    remaining: RemainingBitsAndRefs;
}

// There are two possible opcodes for the same message
struct(0xee764f4b) ConfigConfirmed {
    queryId: uint64;
}

struct(0xee764f6f) ConfigConfirmedAlt {
    queryId: uint64;
}

struct(0x52674370) NewComplaint {
    queryId: uint64;
    electionId: uint32;
    rawComplaint: RemainingBitsAndRefs;
}

struct(0x56744370) SignedVoteForComplaint {
    queryId: uint64;
    signature: bits512;
    // Actually it is VoteForComplaint
    vote: RemainingBitsAndRefs;
}

struct VoteForComplaint {
    signTag: uint32;
    idx: uint16;
    electId: uint32;
    chash: uint256;
}

struct(0b0) FallbackMessage {
    // 31 because header is 1 bit
    opcodeBits: uint31;
    queryId: uint64;
}