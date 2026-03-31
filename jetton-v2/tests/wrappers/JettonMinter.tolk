import "@acton/build/build"
import "@acton/emulation/network"
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
    val outMessage = createMessage({
        bounce: false,
        value,
        dest: self.address,
        body: RequestWalletAddress {
            queryId: 0,
            ownerAddress,
            includeOwnerAddress,
        },
    });
    return net.send(from, outMessage);
}

fun JettonMinter.fromStorage(storage: MinterStorage) {
    val init = ContractState {
        code: build("jetton_v2_minter"),
        data: storage.toCell(),
    };
    val addr = AutoDeployAddress { stateInit: init }.calculateAddress();
    return JettonMinter {
        address: addr,
        init,
    };
}

fun JettonMinter.sendDeploy(self, from: address, params: SendParams) {
    val outMessage = createMessage({
        bounce: false,
        value: params.value,
        dest: { workchain: 0, stateInit: self.init },
        body: TopUpTons {},
    });
    return net.send(from, outMessage);
}

fun JettonMinter.sendMint(
    self,
    from: address,
    recipient: address,
    jettonAmount: int,
    forwardTonAmount: int,
    totalTonAmount: int,
    customPayload: cell? = null,
) {
    val forwardPayload = beginCell().storeMaybeRef(customPayload).endCell().beginParse();
    val outMessage = createMessage({
        bounce: false,
        value: totalTonAmount + ton("0.015"),
        dest: self.address,
        body: MintNewJettons {
            queryId: 0,
            mintRecipient: recipient,
            tonAmount: totalTonAmount,
            internalTransferMsg: InternalTransferStep {
                queryId: 0,
                jettonAmount,
                transferInitiator: null,
                sendExcessesTo: self.address,
                forwardTonAmount,
                forwardPayload,
            }.toCell(),
        },
    });
    return net.send(from, outMessage);
}

fun JettonMinter.sendChangeAdmin(self, from: address, newOwner: address) {
    val outMessage = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: ChangeMinterAdmin {
            queryId: 0,
            newAdminAddress: newOwner,
        },
    });
    return net.send(from, outMessage);
}

fun JettonMinter.sendClaimAdmin(self, from: address) {
    val outMessage = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: ClaimMinterAdmin { queryId: 0 },
    });
    return net.send(from, outMessage);
}

fun JettonMinter.sendDropAdmin(self, from: address) {
    val outMessage = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: DropMinterAdmin { queryId: 0 },
    });
    return net.send(from, outMessage);
}

fun JettonMinter.sendChangeMetadata(self, from: address, newMetadata: string) {
    val outMessage = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: self.address,
        body: ChangeMinterMetadataUri {
            queryId: 0,
            newMetadataUri: newMetadata,
        },
    });
    return net.send(from, outMessage);
}

fun JettonMinter.sendUpgrade(self, from: address, newCode: cell, newData: cell) {
    val outMessage = createMessage({
        bounce: false,
        value: ton("0.2"),
        dest: self.address,
        body: UpgradeMinterCode {
            queryId: 0,
            newData,
            newCode,
        },
    });
    return net.send(from, outMessage);
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
