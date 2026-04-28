import "dns-utils"
import "errors"

type DnsRecords = map<uint256, cell>

fun DnsRecords.packToBuilder(self, mutate b: builder) {
    b.storeUint(0, BYTE_SIZE);
    b.storeDict(self.toLowLevelDict());
}

fun DnsRecords.unpackFromSlice(mutate s: slice): DnsRecords {
    assert (s.loadUint(BYTE_SIZE) == 0) throw ERROR_CONTENT_TAG_INVALID;
    return createMapFromLowLevelDict<uint256, cell>(s.loadDict());
}

type DnsConfigMap = map<uint256, slice>

fun loadDnsConfigMap(configCell: cell): DnsConfigMap {
    var configSlice = configCell.beginParse();
    return createMapFromLowLevelDict(configSlice.loadDict());
}

struct CollectionStorage {
    content: cell
    nftItemCode: cell
}

struct CollectionDataReply {
    nextItemIndex: int
    content: cell
    ownerAddress: address?
}

fun CollectionStorage.load() {
    return CollectionStorage.fromCell(contract.getData());
}

struct RootDnsStorage {
    tonAddress: address
    tMeAddress: address
    tonWwwAddress: address
}

struct DnsResolveResponse {
    resolvedPrefixLengthBits: int
    resolvedRecord: cell?
}

struct ItemStorageNotInitialized {
    index: uint256
    collectionAddress: address
}

fun calcDeployedNftItem(index: uint256, itemCode: cell): AutoDeployAddress {
    val itemStorage = ItemStorageNotInitialized {
        index,
        collectionAddress: contract.getAddress(),
    };

    return { workchain: BASECHAIN, stateInit: { code: itemCode, data: itemStorage.toCell() } };
}

struct ItemStorageInitialized {
    index: uint256
    collectionAddress: address
    ownerAddress: address?
    content: Cell<DnsRecords>
    domain: cell
    auction: Cell<AuctionState>?
    lastFillUpTime: uint64
}

struct NftDataReply {
    isInitialized: bool
    index: uint256
    collectionAddress: address
    ownerAddress: address?
    content: Cell<DnsRecords>?
}

fun ItemStorageInitialized.save(self) {
    contract.setData(self.toCell());
}

fun ItemStorageInitialized.unpackAuction(self): (bool, AuctionState) {
    var res: (bool, AuctionState);

    if (self.auction == null) {
        res = (
            true,
            {
                auctionEndTime: 0,
                maxBidAmount: 0,
                maxBidAddress: null,
            },
        );
    } else {
        res = (false, self.auction.load());
    }

    return res;
}

struct ItemStorageMaybeNotInitialized {
    contractData: slice
}

fun startLoadingDnsItemStorage(): ItemStorageMaybeNotInitialized {
    return { contractData: contract.getData().beginParse() };
}

fun ItemStorageMaybeNotInitialized.isInitialized(self): bool {
    return self.contractData.remainingRefsCount() > 0;
}

fun ItemStorageMaybeNotInitialized.parseNotInitialized(self): ItemStorageNotInitialized {
    return ItemStorageNotInitialized.fromSlice(self.contractData);
}

fun ItemStorageMaybeNotInitialized.parseInitialized(self): ItemStorageInitialized {
    return ItemStorageInitialized.fromSlice(self.contractData);
}

struct AuctionState {
    maxBidAddress: address?
    maxBidAmount: coins
    auctionEndTime: uint64
}
