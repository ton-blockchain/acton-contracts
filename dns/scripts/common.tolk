import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "../contracts/dns-utils"
import "../contracts/messages"
import "../contracts/storage"
import "../tests/wrappers/DnsCollection"
import "../tests/wrappers/DnsItem"
import "../tests/wrappers/DnsRoot"

const DNS_WALLET_CATEGORY = "wallet".toBase256()
const DNS_NAME_CATEGORY = "dns_name".toBase256()
const DNS_DEFAULT_DOMAIN = "abc"
const DNS_DEFAULT_COLLECTION_URI = "https://example.com/dns/collection.json"
const DNS_DEFAULT_DOMAIN_UPDATED_URI = "https://example.com/dns/benchflow-updated.json"

fun dnsWalletName(): string {
    return envOr<string>("DEPLOYER_WALLET", "deployer-1");
}

fun dnsWallet(): Wallet {
    return net.wallet(dnsWalletName());
}

fun dnsSenderAddress(): address {
    return dnsWallet().address;
}

fun envString(key: string, fallback: string): string {
    return envOr<string>(key, fallback);
}

fun envCoins(key: string, fallbackNanos: int): coins {
    return envOr<int>(key, fallbackNanos);
}

fun envAddressOrNull(key: string): address? {
    return env<address>(key);
}

fun dnsRootDeployValue(): coins {
    return envCoins("DNS_ROOT_DEPLOY_NANO", 100000000);
}

fun dnsCollectionDeployValue(): coins {
    return envCoins("DNS_COLLECTION_DEPLOY_NANO", 1000000000);
}

fun dnsDomainBid(): coins {
    return envCoins("DNS_DOMAIN_BID_NANO", 10000000000);
}

fun dnsShouldDeployItem(): bool {
    return envOr<int>("DNS_DEPLOY_ITEM", 0) != 0;
}

fun makeDnsCollectionContentCell(uri: string): cell {
    return beginCell().storeUint(1, BYTE_SIZE).storeSlice(uri.beginParse()).endCell();
}

fun makeDnsCollectionStorage(uri: string): CollectionStorage {
    return { content: makeDnsCollectionContentCell(uri), nftItemCode: build("dns_item") };
}

fun makeDnsRootStorage(
    tonResolver: address,
    tMeResolver: address,
    tonWwwResolver: address,
): RootDnsStorage {
    return {
        tonAddress: tonResolver,
        tMeAddress: tMeResolver,
        tonWwwAddress: tonWwwResolver,
    };
}

fun makeDnsDomainCell(domain: string): slice {
    return domain.beginParse();
}

fun dnsDomainIndex(domain: string): uint256 {
    return domain.beginParse().hash();
}

fun makeDnsDeployBodyFromDomain(domain: slice): cell {
    var remainingDomain = domain;
    val firstChunkBits = remainingDomain.remainingBitsCount() > 991
        ? 991
        : remainingDomain.remainingBitsCount();
    var body = beginCell().storeUint(0, 32).storeSlice(remainingDomain.loadBits(firstChunkBits));

    if (remainingDomain.remainingBitsCount() > 0) {
        body.storeRef(makeSnakeTail(mutate remainingDomain));
    }

    return body.endCell();
}

fun makeSnakeTail(mutate remainder: slice): cell {
    if (remainder.remainingBitsCount() <= 1023) {
        return beginCell().storeSlice(remainder).endCell();
    }

    val head = remainder.loadBits(1023);
    val tail = makeSnakeTail(mutate remainder);
    return beginCell().storeSlice(head).storeRef(tail).endCell();
}

fun makeDnsTextRecord(value: string): cell {
    return beginCell().storeUint(0, BYTE_SIZE).storeSlice(value.beginParse()).endCell();
}

fun makeDnsWalletRecord(wallet: address): cell {
    return beginCell().storeUint(0x9fd3, 16).storeAddress(wallet).storeUint(0, 1).endCell();
}

fun makeDnsRecords(label: string): DnsRecords {
    var records: map<uint256, cell> = [];
    records.set(DNS_NAME_CATEGORY, makeDnsTextRecord(label));
    return records;
}

fun makeDnsTransferData(
    newOwner: address,
    responseDestination: address?,
    forwardAmount: coins,
    forwardPayload: RemainingBitsAndRefs,
): TransferOwnershipData {
    return {
        newOwnerAddress: newOwner,
        responseDestination,
        customPayload: null,
        forwardAmount,
        forwardPayload,
    };
}

fun makeZeroForwardPayload(): RemainingBitsAndRefs {
    return beginCell().storeBool(false).toSlice();
}

fun makeTonDomainSlice(): slice {
    return beginCell()
        .storeSlice("ton".literalSlice())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeTonWwwDomainSlice(): slice {
    return beginCell()
        .storeSlice("ton".literalSlice())
        .storeUint(0, BYTE_SIZE)
        .storeSlice("www".literalSlice())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeTMeDomainSlice(): slice {
    return beginCell()
        .storeSlice("me".literalSlice())
        .storeUint(0, BYTE_SIZE)
        .storeSlice("t".literalSlice())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeDotSlice(): slice {
    return beginCell().storeUint(0, BYTE_SIZE).endCell().beginParse();
}

fun makeNextResolverAddress(result: DnsResolveResponse): address? {
    if (result.resolvedRecord == null) {
        return null;
    }

    return DnsNextResolver.fromCell(result.resolvedRecord!).resolver;
}

fun deployDnsRootContract(
    deployer: address,
    tonResolver: address,
    tMeResolver: address,
    tonWwwResolver: address,
): RootDnsContract {
    val root = RootDnsContract.fromStorage(
        makeDnsRootStorage(tonResolver, tMeResolver, tonWwwResolver),
    );
    val res = root.deploy(deployer, { value: dnsRootDeployValue(), bounce: false });
    res.wait();
    return root;
}

fun deployDnsCollectionContract(deployer: address, collectionUri: string): NftCollectionContract {
    net.setNow((AUCTION_START_TIME - 1000) as uint32);
    val collection = NftCollectionContract.fromStorage(makeDnsCollectionStorage(collectionUri));
    val deployMsg = createMessage({
        bounce: false,
        value: dnsCollectionDeployValue(),
        dest: { stateInit: collection.stateInit! },
        body: FillUp { queryId: 0 },
    });
    val res = net.send(deployer, deployMsg);
    res.wait();
    return collection;
}

fun deployDnsDomainContract(
    collection: NftCollectionContract,
    deployer: address,
    domain: string,
    bid: coins,
): NftItemContract {
    net.setNow((AUCTION_START_TIME + 1) as uint32);
    val deployTx = collection.sendAny(
        deployer,
        makeDnsDeployBodyFromDomain(makeDnsDomainCell(domain)),
        { value: bid, bounce: true },
    );
    deployTx.wait();
    return NftItemContract.fromAddress(collection.getNftAddressByIndex(dnsDomainIndex(domain)));
}

fun completeDnsAuction(item: NftItemContract, requester: address): SendResultList {
    val auction = item.getAuctionInfo();
    net.setNow((auction.auctionEndTime + 1) as uint32);
    return item.sendGetStaticData(requester, 1, { value: ton("0.1"), bounce: true });
}

fun printRootInfo(root: RootDnsContract, label: string) {
    val ton = root.dnsresolve(makeTonDomainSlice(), 0);
    val tonWww = root.dnsresolve(makeTonWwwDomainSlice(), 0);
    val tMe = root.dnsresolve(makeTMeDomainSlice(), 0);

    println(format2("{} ROOT_ADDRESS={}", label, root.address));
    println(format2("{} TON_PREFIX_BITS={}", label, ton.resolvedPrefixLengthBits));
    println(format2("{} TON_RESOLVER={}", label, makeNextResolverAddress(ton)));
    println(format2("{} TON_WWW_PREFIX_BITS={}", label, tonWww.resolvedPrefixLengthBits));
    println(format2("{} TON_WWW_RESOLVER={}", label, makeNextResolverAddress(tonWww)));
    println(format2("{} TME_PREFIX_BITS={}", label, tMe.resolvedPrefixLengthBits));
    println(format2("{} TME_RESOLVER={}", label, makeNextResolverAddress(tMe)));
}

fun printCollectionInfo(collection: NftCollectionContract, label: string) {
    val data = collection.getCollectionData();
    println(format2("{} COLLECTION_ADDRESS={}", label, collection.address));
    println(format2("{} NEXT_ITEM_INDEX={}", label, data.nextItemIndex));
    println(format2("{} CONTENT_HASH={}", label, data.content.hash()));
}

fun printDnsItemInfo(item: NftItemContract, label: string) {
    val data = item.getNftData();
    println(format2("{} ITEM_ADDRESS={}", label, item.address));
    println(format2("{} INITIALIZED={}", label, data.isInitialized));
    println(format2("{} INDEX={}", label, data.index));
    println(format2("{} COLLECTION_ADDRESS={}", label, data.collectionAddress));
    println(format2("{} OWNER_ADDRESS={}", label, data.ownerAddress));
    println(format2("{} CONTENT_PRESENT={}", label, data.content != null));
    if (data.isInitialized) {
        println(format2("{} EDITOR={}", label, item.getEditor()));
        println(format2("{} LAST_FILL_UP_TIME={}", label, item.getLastFillUpTime()));
        println(format2("{} AUCTION_INFO={}", label, item.getAuctionInfo()));
    }
}
