import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "../../contracts/messages"
import "../../contracts/storage"
import "../../contracts/types"

struct JettonMinter {
    address: address
    init: ContractState
}

fun JettonMinter.sendDiscovery(
    self,
    from: address,
    ownerAddress: address,
    includeOwnerAddress: bool,
    value: coins = ton("0.1"),
) {
    val msg = createMessage({
        bounce: false,
        value,
        dest: self.address,
        body: RequestWalletAddress {
            queryId: 0,
            ownerAddress,
            includeOwnerAddress,
        },
    });
    return net.send(from, msg);
}

fun JettonMinter.fromStorage(storage: MinterStorage) {
    val init = ContractState { code: build("acton_jetton_minter"), data: storage.toCell() };
    val addr = AutoDeployAddress { stateInit: init }.calculateAddress();
    return JettonMinter { address: addr, init };
}

fun JettonMinter.sendDeploy(self, from: address, params: SendParams) {
    val msg = createMessage({
        bounce: false,
        value: params.value,
        dest: { workchain: 0, stateInit: self.init },
        body: TopUpTons {},
    });
    return net.send(from, msg);
}

fun JettonMinter.sendMint(
    self,
    from: address,
    recipient: address,
    jetton_amount: int,
    forward_ton_amount: int,
    total_ton_amount: int,
    custom_payload: cell? = null,
) {
    val forwardPayload = beginCell().storeMaybeRef(custom_payload).endCell().beginParse();
    val msg = createMessage({
        bounce: false,
        value: total_ton_amount + ton("0.015"),
        dest: self.address,
        body: MintNewJettons {
            queryId: 0,
            mintRecipient: recipient,
            tonAmount: total_ton_amount,
            internalTransferMsg: InternalTransferStep {
                queryId: 0,
                jettonAmount: jetton_amount,
                transferInitiator: null,
                sendExcessesTo: self.address,
                forwardTonAmount: forward_ton_amount,
                forwardPayload,
            }.toCell(),
        },
    });
    return net.send(from, msg);
}

fun JettonMinter.sendChangeAdmin(self, from: address, new_owner: address) {
    val msg = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: ChangeMinterAdmin { queryId: 0, newAdminAddress: new_owner },
    });
    return net.send(from, msg);
}

fun JettonMinter.sendClaimAdmin(self, from: address) {
    val msg = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: ClaimMinterAdmin { queryId: 0 },
    });
    return net.send(from, msg);
}

fun JettonMinter.sendDropAdmin(self, from: address) {
    val msg = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: DropMinterAdmin { queryId: 0 },
    });
    return net.send(from, msg);
}

fun JettonMinter.sendChangeMetadata(self, from: address, new_metadata: string) {
    val msg = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: ChangeMinterMetadataUri { queryId: 0, newMetadataUri: new_metadata },
    });
    return net.send(from, msg);
}

fun JettonMinter.sendUpgrade(self, from: address, new_code: cell, new_data: cell) {
    val msg = createMessage({
        bounce: false,
        value: ton("0.2"),
        dest: self.address,
        body: UpgradeMinterCode {
            queryId: 0,
            newData: new_data,
            newCode: new_code,
        },
    });
    return net.send(from, msg);
}

fun JettonMinter.getJettonData(self): JettonDataReply {
    return net.runGetMethod(self.address, "get_jetton_data");
}

fun JettonMinter.getTotalSupply(self): int {
    return self.getJettonData().totalSupply;
}

fun JettonMinter.getAdminAddress(self): address? {
    return self.getJettonData().adminAddress;
}

fun JettonMinter.getContent(self): cell {
    return self.getJettonData().jettonContent;
}

fun JettonMinter.getWalletAddress(self, owner: address): address {
    return net.runGetMethod(self.address, "get_wallet_address", owner);
}
