struct WalletStorage {
    status: uint4
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
}

struct MinterStorage {
    totalSupply: coins
    adminAddress: address?
    nextAdminAddress: address?
    jettonWalletCode: cell
    metadataUri: string
}

fun MinterStorage.load() {
    return MinterStorage.fromCell(contract.getData());
}

fun MinterStorage.save(self) {
    contract.setData(self.toCell());
}

fun WalletStorage.load() {
    return WalletStorage.fromCell(contract.getData());
}

fun WalletStorage.save(self) {
    contract.setData(self.toCell());
}

struct JettonWalletDataReply {
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
    jettonWalletCode: cell
}

struct JettonDataReply {
    totalSupply: int
    mintable: bool
    adminAddress: address?
    jettonContent: Cell<OnchainMetadataReply>
    jettonWalletCode: cell
}

struct (0x00) OnchainMetadataReply {
    contentDict: map<uint256, Cell<SnakeDataReply>>
}

struct (0x00) SnakeDataReply {
    string: string
}
