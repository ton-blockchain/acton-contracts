import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/types/message"
import "../../contracts/types"
import "../../contracts/messages"
import "../../contracts/types"

struct NftCollectionContract {
    address: address
    init: ContractState? = null
}

/// Creates a contract wrapper instance from the storage data
fun NftCollectionContract.fromStorage(storage: NftCollectionStorage) {
    val init = ContractState {
        code: build("nft-collection"),
        data: storage.toCell(),
    };
    val address = AutoDeployAddress { stateInit: init }.calculateAddress();
    return NftCollectionContract { address, init }
}

/// Creates a contract wrapper instance from the address
fun NftCollectionContract.fromAddress(address: address) {
    return NftCollectionContract { address }
}

/// Deploys the contract to the blockchain
fun NftCollectionContract.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.init == null) {
        Assert.fail("Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment");
    }
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: {
            stateInit: self.init,
        },
    });
    return net.send(from, msg)
}

fun NftCollectionContract.sendDeployNft(self, from: address, queryId: uint64, itemIndex: uint64, attachTonAmount: coins, initParams: NftItemInitAtDeployment, config: SendParams = {}): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: DeployNft {
            queryId,
            itemIndex,
            attachTonAmount,
            initParams: initParams.toCell(),
        },
    });
    return net.send(from, msg)
}

fun NftCollectionContract.sendRequestRoyaltyParams(self, from: address, queryId: uint64, config: SendParams = {}): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: RequestRoyaltyParams {
            queryId,
        },
    });
    return net.send(from, msg);
}

fun NftCollectionContract.sendBatchDeployNfts(self, from: address, queryId: uint64, deployList: map<uint64, BatchDeployDictItem>, config: SendParams = {}): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: BatchDeployNfts {
            queryId,
            deployList,
        },
    });
    return net.send(from, msg);
}

fun NftCollectionContract.sendChangeCollectionAdmin(self, from: address, queryId: uint64, newAdminAddress: address, config: SendParams = {}): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ChangeCollectionAdmin {
            queryId,
            newAdminAddress,
        },
    });
    return net.send(from, msg);
}

/// Send message to the contract with a custom body cell
fun NftCollectionContract.sendAny(self, from: address, body: cell, config: SendParams = {}): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, msg);
}

fun NftCollectionContract.get_collection_data(self): CollectionDataReply {
    return net.runGetMethod(self.address, "get_collection_data")
}

fun NftCollectionContract.get_nft_address_by_index(self, itemIndex: int): address {
    return net.runGetMethod(self.address, "get_nft_address_by_index", itemIndex)
}

fun NftCollectionContract.royalty_params(self): RoyaltyParams {
    return net.runGetMethod(self.address, "royalty_params")
}

fun NftCollectionContract.get_nft_content(self, itemIndex: int, individualNftContent: SnakeString): Cell<OffchainMetadataReply> {
    return net.runGetMethod(self.address, "get_nft_content", [itemIndex, individualNftContent.toCell()] as tuple)
}
