import "errors"

type DnsRecords = map<uint256, cell>
type DnsContent = DnsRecords
type DomainName = slice

fun DnsContent.packToBuilder(self, mutate b: builder) {
    b.storeUint(0, 8);
    b.storeDict(self.toLowLevelDict());
}

fun DnsContent.unpackFromSlice(mutate s: slice): DnsContent {
    assert (s.loadUint(8) == 0) throw ERROR_CONTENT_TAG_INVALID;
    return createMapFromLowLevelDict<uint256, cell>(s.loadDict());
}

fun DomainName.packToBuilder(self, mutate b: builder) {
    b.storeSlice(self);
}

fun DomainName.unpackFromSlice(mutate s: slice): DomainName {
    return s;
}

type DnsConfigMap = map<uint256, RemainingBitsAndRefs>

fun loadDnsConfigMap(configCell: cell): DnsConfigMap {
    var configSlice = configCell.beginParse();
    return createMapFromLowLevelDict<uint256, RemainingBitsAndRefs>(configSlice.loadDict());
}

struct CollectionStorage {
    content: cell
    nftItemCode: cell
}

fun CollectionStorage.load() {
    return CollectionStorage.fromCell(contract.getData());
}

fun CollectionStorage.save(self) {
    contract.setData(self.toCell());
}

struct ItemStorageNotInitialized {
    index: uint256
    collectionAddress: address
}

@overflow1023_policy("suppress")
struct ItemStorageInitialized {
    index: uint256
    collectionAddress: address
    ownerAddress: address?
    content: Cell<DnsContent>
    domain: Cell<DomainName>
    auction: dict
    lastFillUpTime: uint64
}

fun ItemStorageInitialized.save(self) {
    contract.setData(self.toCell());
}

struct ItemStorageMaybeNotInitialized {
    contractData: slice
}

fun startLoadingItemStorage(): ItemStorageMaybeNotInitialized {
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

fun unpackAuction(auction: dict): AuctionState {
    if (auction == null) {
        return {
            maxBidAddress: null,
            maxBidAmount: 0,
            auctionEndTime: 0,
        };
    }

    return AuctionState.fromCell(auction!!);
}

fun packAuction(maxBidAddress: address?, maxBidAmount: coins, auctionEndTime: int): cell {
    return AuctionState {
        maxBidAddress,
        maxBidAmount,
        auctionEndTime: auctionEndTime as uint64,
    }.toCell();
}

@overflow1023_policy("suppress")
struct RootDnsStorage {
    tonAddress: address
    tMeAddress: address
    tonWwwAddress: address
}

fun RootDnsStorage.load() {
    return RootDnsStorage.fromCell(contract.getData());
}

fun RootDnsStorage.save(self) {
    contract.setData(self.toCell());
}
