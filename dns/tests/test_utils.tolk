import "wrappers/DnsCollection"
import "wrappers/DnsItem"
import "wrappers/DnsRoot"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/dns-utils"
import "../contracts/messages"
import "../contracts/storage"

const ROOT_TON_RESOLVER_HASH = 0x348bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f
const ROOT_TME_RESOLVER_HASH = 0xa48bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f
const ROOT_TON_WWW_RESOLVER_HASH = 0xb48bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f

const DEFAULT_DOMAIN = "alice"
const DNS_NEXT_RESOLVER_CATEGORY = "dns_next_resolver".toBase256()
const DNS_NAME_CATEGORY = "dns_name".toBase256()
const DNS_WALLET_CATEGORY = "wallet".toBase256()

fun addrFromHash(hash: uint256): address {
    return address.fromWorkchainAndHash(BASECHAIN, hash);
}

fun rootTonResolverAddress(): address {
    return addrFromHash(ROOT_TON_RESOLVER_HASH);
}

fun rootTMeResolverAddress(): address {
    return addrFromHash(ROOT_TME_RESOLVER_HASH);
}

fun rootTonWwwResolverAddress(): address {
    return addrFromHash(ROOT_TON_WWW_RESOLVER_HASH);
}

fun parseNextResolverCell(data: cell): address {
    return DnsNextResolver.fromCell(data).resolver;
}

fun newActor(name: string, extraTopUp: coins = 0): Treasury {
    val actor = net.treasury(name);
    if (extraTopUp > 0) {
        net.topUp(actor.address, extraTopUp);
    }
    return actor;
}

fun makeCollectionContentCell(): cell {
    return beginCell().storeUint(1, BYTE_SIZE).storeSlice("https://ton.org/collection.json"
        .beginParse())
        .endCell();
}

fun makeCollectionStorage(): CollectionStorage {
    return { content: makeCollectionContentCell(), nftItemCode: build("dns_item") };
}

fun makeDnsTextRecord(value: string): cell {
    return beginCell().storeUint(0, BYTE_SIZE).storeSlice(value.beginParse()).endCell();
}

fun makeRecordMapWithName(value: string = "alice.ton"): DnsRecords {
    var records: map<uint256, cell> = [];
    records.set(DNS_NAME_CATEGORY, makeDnsTextRecord(value));
    return records;
}

fun makeDomainCell(domain: string): cell {
    return beginCell().storeSlice(domain.beginParse()).endCell();
}

fun domainIndex(domain: string): uint256 {
    return domain.beginParse().hash();
}

fun makeItemStorageNonInit(collectionAddress: address, domain: string = DEFAULT_DOMAIN) {
    return ItemStorageNotInitialized { index: domainIndex(domain), collectionAddress };
}

fun makeItemInitBody(fromAddress: address, domain: string): cell {
    val domainSlice = domain.beginParse();
    return ItemInitData { fromAddress, domain: domainSlice.toCell() }.toCell();
}

fun repeatAsciiChar(charCode: int, count: int): slice {
    var b = beginCell();
    repeat (count) {
        b.storeUint(charCode, BYTE_SIZE);
    }
    return b.endCell().beginParse();
}

fun makeSnakeTail(mutate remainder: slice): cell {
    if (remainder.remainingBitsCount() <= 1023) {
        return beginCell().storeSlice(remainder).endCell();
    }

    val head = remainder.loadBits(1023);
    val tail = makeSnakeTail(mutate remainder);
    return beginCell().storeSlice(head).storeRef(tail).endCell();
}

fun makeDeployBodyFromDomain(domain: slice): cell {
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

fun makeDeployBody(domain: string): cell {
    return makeDeployBodyFromDomain(domain.beginParse());
}

fun makeDotSlice(): slice {
    return beginCell().storeUint(0, BYTE_SIZE).endCell().beginParse();
}

fun makeLabelDomainSlice(label: string): slice {
    return beginCell().storeSlice(label.beginParse()).storeUint(0, BYTE_SIZE).endCell().beginParse();
}

fun makeLabelAndTailSlice(label: string, tail: string): slice {
    return beginCell().storeSlice(label.beginParse()).storeUint(0, BYTE_SIZE).storeSlice(tail
        .beginParse())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeRelativeSubdomainSlice(subdomain: string): slice {
    return beginCell().storeUint(0, BYTE_SIZE).storeSlice(subdomain.beginParse()).storeUint(
        0,
        BYTE_SIZE
    )
        .endCell()
        .beginParse();
}

fun makeLeadingZero(domain: slice): slice {
    return beginCell().storeUint(0, BYTE_SIZE).storeSlice(domain).endCell().beginParse();
}

fun makeTonDomainSlice(): slice {
    return beginCell().storeSlice("ton".literalSlice()).storeUint(0, BYTE_SIZE).endCell().beginParse();
}

fun makeTonWwwDomainSlice(): slice {
    return beginCell().storeSlice("ton".literalSlice()).storeUint(0, BYTE_SIZE).storeSlice("www"
        .literalSlice())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeTMeDomainSlice(): slice {
    return beginCell().storeSlice("me".literalSlice()).storeUint(0, BYTE_SIZE).storeSlice("t"
        .literalSlice())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun setDnsBlacklist(index: uint256) {
    var config = net.getConfig();
    var blacklist: map<uint256, RemainingBitsAndRefs> = [];
    blacklist.set(index, beginCell().storeUint(1, BYTE_SIZE).endCell().beginParse());

    val paramCell = beginCell().storeDict(blacklist.toLowLevelDict()).endCell();
    config.setParamRaw(DNS_CONFIG_ID, paramCell);
    expect(net.setConfig(config)).toEqual(true);
}

fun deployRootContract() {
    val deployer = newActor("dns_root_deployer", ton("100"));
    val root = RootDnsContract.fromStorage({
        tonAddress: rootTonResolverAddress(),
        tMeAddress: rootTMeResolverAddress(),
        tonWwwAddress: rootTonWwwResolverAddress(),
    });

    val res = root.deploy(deployer.address, { value: ton("10"), bounce: true });
    expect(res).toHaveSuccessfulDeploy({ to: root.address });
    return (root, deployer);
}

fun deployCollectionContract() {
    net.setNow((AUCTION_START_TIME - 1000) as uint32);
    val deployer = newActor("dns_collection_deployer", ton("100000"));
    val user = newActor("dns_collection_user", ton("100000"));

    val collection = NftCollectionContract.fromStorage(makeCollectionStorage());
    expect(collection.stateInit).toBeNotNull();
    val deployMsg = createMessage({
        bounce: false,
        value: ton("10"),
        dest: { stateInit: collection.stateInit! },
        body: FillUp { queryId: 0 },
    });
    val res = net.send(deployer.address, deployMsg);

    expect(res).toHaveSuccessfulDeploy<FillUp>({ to: collection.address });
    expect(res).toHaveSuccessfulTx<FillUp>({ from: deployer.address, to: collection.address });
    expect(net.isDeployed(collection.address)).toEqual(true);

    return (collection, deployer, user);
}

fun deployItemThroughCollection(domain: string = DEFAULT_DOMAIN, value: coins = ton("1000")) {
    val (collection, deployer, bidder) = deployCollectionContract();
    net.setNow((AUCTION_START_TIME + 1) as uint32);

    val deployRes = collection.sendAny(
        deployer.address,
        makeDeployBody(domain),
        { value, bounce: true }
    );
    expect(deployRes).toHaveSuccessfulTx({ to: collection.address });

    val itemDeployTx = deployRes.findTransaction({ from: collection.address, deploy: true });
    expect(itemDeployTx).toBeDefined();

    val itemAddress = itemDeployTx.unwrap().getAccountAddress();
    val item = NftItemContract.fromAddress(itemAddress);

    return (item, collection, deployer, bidder);
}

fun completeAuction(item: NftItemContract, sender: address, queryId: int = 1): SendResultList {
    val auction = item.getAuctionInfo();
    net.setNow((auction.auctionEndTime + 1) as uint32);

    return item.sendGetStaticData(sender, queryId as uint64, { value: ton("1"), bounce: true });
}

fun makeTransferData(
    newOwnerAddress: address,
    responseDestination: address?,
    forwardAmount: coins,
    forwardPayload: RemainingBitsAndRefs,
): TransferOwnershipData {
    return {
        newOwnerAddress,
        responseDestination,
        customPayload: null,
        forwardAmount,
        forwardPayload,
    };
}

fun makeWalletRecord(wallet: address): cell {
    return beginCell().storeUint(0x9fd3, 16).storeAddress(wallet).storeUint(0, 1).endCell();
}

fun expectedAuctionDurationAt(nowTime: int): int {
    var months = (nowTime - AUCTION_START_TIME) / ONE_MONTH;
    if (months > 12) {
        months = 12;
    }

    return AUCTION_START_DURATION - (AUCTION_START_DURATION - AUCTION_END_DURATION) * months / 12;
}
