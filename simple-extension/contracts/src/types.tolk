struct ExtensionStorage {
    walletAddress: address
    admin: address
    subscriptionAmount: coins
    lastPaymentTime: uint32?
    paymentTimeInterval: uint32
}

fun ExtensionStorage.load(): ExtensionStorage {
    return ExtensionStorage.fromCell(contract.getData());
}

fun ExtensionStorage.save(self) {
    contract.setData(self.toCell());
}

struct (0x7e8764df) TopUp {}

// external
struct (0x7e8764ef) CollectPaymentFromWallet {
    queryId: uint64
}

struct (0x7e2364ef) WithdrawExtensionBalance {}

struct (0x283b4c3f) CancelSubscription {
    queryId: uint64
}

struct (0x7e8364ef) ReceivePaymentFromWallet {}
