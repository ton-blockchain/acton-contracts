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

fun startLoadingOrderStorage(): OrderStorageMaybeNotInitialized {
    return { contractData: contract.getData().beginParse() };
}

fun OrderStorageMaybeNotInitialized.parseBase(self): (address, uint256, slice) {
    var s = self.contractData;
    val multisigAddress = s.loadAddress();
    val orderSeqno = s.loadUint(ORDER_SEQNO_SIZE) as uint256;
    return (multisigAddress, orderSeqno, s);
}

fun OrderStorageMaybeNotInitialized.isInitialized(self): bool {
    val (_, _, s) = self.parseBase();
    return s.remainingBitsCount() > 0;
}

fun OrderStorageMaybeNotInitialized.parseNotInitialized(self): (address, uint256) {
    val (multisigAddress, orderSeqno, s) = self.parseBase();
    s.assertEnd();
    return (multisigAddress, orderSeqno);
}

fun OrderStorageMaybeNotInitialized.parseInitialized(self): OrderStorageInitialized {
    return OrderStorageInitialized.fromSlice(self.contractData);
}
