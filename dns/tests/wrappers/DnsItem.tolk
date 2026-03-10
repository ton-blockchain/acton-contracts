import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "../../contracts/messages"
import "../../contracts/storage"

struct NftDataReply {
    isInitialized: bool
    index: uint256
    collectionAddress: address
    ownerAddress: address?
    content: Cell<DnsRecords>?
}

struct NftItemContract {
    address: address
    stateInit: ContractState? = null
}

/// Creates a contract wrapper instance from the storage data
fun NftItemContract.fromStorage(
    storage: ItemStorageNotInitialized,
    toShard: AddressShardingOptions? = null,
) {
    val stateInit = ContractState {
        code: build("dns_item"),
        data: storage.toCell(),
    };
    val address = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return NftItemContract { address, stateInit };
}

/// Creates a contract wrapper instance from the address
fun NftItemContract.fromAddress(address: address) {
    return NftItemContract { address };
}

/// Deploys the contract to the blockchain
fun NftItemContract.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment");
    }
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendTransferOwnership(
    self,
    from: address,
    queryId: uint64,
    transferData: TransferOwnershipData,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: TransferOwnership { queryId, transferData },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendEditContent(
    self,
    from: address,
    queryId: uint64,
    newContent: DnsRecords,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: EditContent {
            queryId,
            newContent: newContent.toCell(),
        },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendChangeDnsRecord(
    self,
    from: address,
    queryId: uint64,
    key: uint256,
    value: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ChangeDnsRecord { queryId, key, value },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendProcessGovernanceDecision(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ProcessGovernanceDecision { queryId },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendDnsRecordRelease(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: DnsRecordRelease { queryId },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendGetStaticData(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: GetStaticData { queryId },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendGovernanceTransfer(
    self,
    from: address,
    transferData: TransferOwnershipData,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: GovernanceTransfer { transferData },
    });
    return net.send(from, outMessage);
}

fun NftItemContract.sendGovernanceRelease(
    self,
    from: address,
    config: SendParams = {},
): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: GovernanceRelease {},
    });
    return net.send(from, outMessage);
}

/// Send outMessage to the contract with a custom body cell
fun NftItemContract.sendAny(
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

fun NftItemContract.getNftData(self): NftDataReply {
    return net.runGetMethod(self.address, "get_nft_data");
}

fun NftItemContract.getEditor(self): address? {
    return net.runGetMethod(self.address, "get_editor");
}

fun NftItemContract.getDomain(self): slice {
    return net.runGetMethod(self.address, "get_domain");
}

fun NftItemContract.getAuctionInfo(self): AuctionState {
    return net.runGetMethod(self.address, "get_auction_info");
}

fun NftItemContract.getLastFillUpTime(self): int {
    return net.runGetMethod(self.address, "get_last_fill_up_time");
}

fun NftItemContract.dnsresolve(self, subdomain: slice, category: uint256): DnsResolveResponse {
    return net.runGetMethod(self.address, "dnsresolve", [subdomain, category] as tuple);
}
