import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "../../contracts/messages"
import "../../contracts/storage"

struct CollectionDataReply {
    nextItemIndex: int
    content: cell
    ownerAddress: address?
}

struct NftCollectionContract {
    address: address
    stateInit: ContractState? = null
}

/// Creates a contract wrapper instance from the storage data
fun NftCollectionContract.fromStorage(
    storage: CollectionStorage,
    toShard: AddressShardingOptions? = null,
) {
    val stateInit = ContractState { code: build("dns_collection"), data: storage.toCell() };
    val address = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return NftCollectionContract { address, stateInit };
}

/// Creates a contract wrapper instance from the address
fun NftCollectionContract.fromAddress(address: address) {
    return NftCollectionContract { address };
}

/// Deploys the contract to the blockchain
fun NftCollectionContract.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail(
            "Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment",
        );
    }
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit },
    });
    return net.send(from, outMessage);
}

fun NftCollectionContract.sendDeployDnsDomain(
    self,
    from: address,
    payload: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: DeployDnsDomain { payload },
    });
    return net.send(from, outMessage);
}

fun NftCollectionContract.sendFillUp(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: FillUp { queryId },
    });
    return net.send(from, outMessage);
}

/// Send outMessage to the contract with a custom body cell
fun NftCollectionContract.sendAny(
    self,
    from: address,
    body: cell,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, outMessage);
}

fun NftCollectionContract.getCollectionData(self): CollectionDataReply {
    return net.runGetMethod(self.address, "get_collection_data");
}

fun NftCollectionContract.getNftAddressByIndex(self, index: int): address {
    return net.runGetMethod(self.address, "get_nft_address_by_index", index);
}

fun NftCollectionContract.getNftContent(self, index: int, individualNftContent: cell): cell {
    return net.runGetMethod(
        self.address,
        "get_nft_content",
        [index, individualNftContent] as tuple,
    );
}

fun NftCollectionContract.dnsresolve(self, subdomain: slice, category: int): DnsResolveResponse {
    return net.runGetMethod(self.address, "dnsresolve", [subdomain, category] as tuple);
}
