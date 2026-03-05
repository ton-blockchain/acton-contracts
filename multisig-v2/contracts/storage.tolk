import "types"

struct MultisigStorage {
    nextOrderSeqno: uint256
    threshold: uint8
    signers: NonEmptyIndexedAddressMap
    signersNum: uint8
    proposers: IndexedAddressMap
    allowArbitraryOrderSeqno: bool
}

fun MultisigStorage.load() {
    return MultisigStorage.fromCell(contract.getData());
}

fun MultisigStorage.save(self) {
    contract.setData(self.toCell());
}

struct OrderStorageInitialized {
    multisigAddress: address
    orderSeqno: uint256
    remaining: OrderStorageRemaining
}

struct OrderStorageRemaining {
    threshold: uint8
    sentForExecution: bool
    signers: NonEmptyIndexedAddressMap
    approvalsMask: uint256
    approvalsNum: uint8
    expirationDate: uint48
    order: NonEmptyOrderActionsMap
}

fun OrderStorageInitialized.save(self) {
    contract.setData(self.toCell());
}

struct OrderStorageMaybeNotInitialized {
    contractData: slice
}

// TODO: load in place?
fun startLoadingOrderStorage(): OrderStorageMaybeNotInitialized {
    return { contractData: contract.getData().beginParse() };
}

struct OrderStorageHeader {
    multisigAddress: address
    orderSeqno: uint256
    remaining: RemainingBitsAndRefs
}

fun OrderStorageMaybeNotInitialized.loadHeader(self): OrderStorageHeader {
    return OrderStorageHeader.fromSlice(self.contractData);
}

fun OrderStorageHeader.isInitialized(self): bool {
    return self.remaining.remainingBitsCount() > 0;
}

fun OrderStorageHeader.loadInitialized(self): OrderStorageInitialized {
    val remaining = OrderStorageRemaining.fromSlice(self.remaining);

    return {
        multisigAddress: self.multisigAddress,
        orderSeqno: self.orderSeqno,
        remaining,
    };
}
