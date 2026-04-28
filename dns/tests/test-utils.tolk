import "@acton/build"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/tlb/maybe"
import "@acton/types/message"
import "@acton/types/transaction"
import "../contracts/dns-utils"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/DnsCollection.gen"
import "../wrappers/DnsItem.gen"
import "../wrappers/RootDns.gen"

// values from actual dns config
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

fun masterchainAddressOf(addr: address): address {
    val (_, hash) = addr.getWorkchainAndHash();
    return address.fromWorkchainAndHash(MASTERCHAIN, hash);
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
    val actor = testing.treasury(name);
    if (extraTopUp > 0) {
        testing.topUp(actor.address, extraTopUp);
    }
    return actor;
}

fun makeCollectionContentCell(): cell {
    return beginCell()
        .storeUint(1, BYTE_SIZE)
        .storeSlice("https://ton.org/collection.json".beginParse())
        .endCell();
}

fun makeCollectionStorage(): CollectionStorage {
    return { content: makeCollectionContentCell(), nftItemCode: build("DnsItem") };
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
    return ItemStorageNotInitialized {
        index: domainIndex(domain),
        collectionAddress,
    };
}

fun makeItemInitBody(fromAddress: address, domain: string): cell {
    val domainSlice = domain.beginParse();
    return ItemInitData {
        fromAddress,
        domain: domainSlice.toCell(),
    }.toCell();
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
    return beginCell()
        .storeSlice(label.beginParse())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeLabelAndTailSlice(label: string, tail: string): slice {
    return beginCell()
        .storeSlice(label.beginParse())
        .storeUint(0, BYTE_SIZE)
        .storeSlice(tail.beginParse())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeRelativeSubdomainSlice(subdomain: string): slice {
    return beginCell()
        .storeUint(0, BYTE_SIZE)
        .storeSlice(subdomain.beginParse())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();
}

fun makeLeadingZero(domain: slice): slice {
    return beginCell().storeUint(0, BYTE_SIZE).storeSlice(domain).endCell().beginParse();
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

fun setDnsBlacklist(index: uint256) {
    var config = testing.getConfig();
    var blacklist: map<uint256, RemainingBitsAndRefs> = [];
    blacklist.set(index, beginCell().storeUint(1, BYTE_SIZE).endCell().beginParse());

    val paramCell = beginCell().storeDict(blacklist.toLowLevelDict()).endCell();
    config.setParamRaw(DNS_CONFIG_ID, paramCell);
    expect(testing.setConfig(config)).toEqual(true);
}

fun deployRootContract() {
    val deployer = newActor("dns_root_deployer", ton("100"));
    val root = RootDns.fromStorage({
        tonAddress: rootTonResolverAddress(),
        tMeAddress: rootTMeResolverAddress(),
        tonWwwAddress: rootTonWwwResolverAddress(),
    });

    val res = root.deploy(deployer.address, { value: ton("10"), bounce: true });
    expect(res).toHaveSuccessfulDeploy({ to: root.address });
    return (root, deployer);
}

fun deployCollectionContract() {
    testing.setNow((AUCTION_START_TIME - 1000));
    val deployer = newActor("dns_collection_deployer", ton("100000"));
    val user = newActor("dns_collection_user", ton("100000"));

    val collection = DnsCollection.fromStorage(makeCollectionStorage());
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
    expect(testing.isDeployed(collection.address)).toEqual(true);

    return (collection, deployer, user);
}

fun deployItemThroughCollection(domain: string = DEFAULT_DOMAIN, value: coins = ton("1000")) {
    val (collection, deployer, bidder) = deployCollectionContract();
    testing.setNow((AUCTION_START_TIME + 1));

    val deployRes = collection.sendAny(
        deployer.address,
        makeDeployBody(domain),
        { value, bounce: true },
    );
    expect(deployRes).toHaveSuccessfulTx({ to: collection.address });

    val itemDeployTx = deployRes.findTransaction({ from: collection.address, deploy: true });
    expect(itemDeployTx).toBeNotNull();

    val itemAddress = itemDeployTx!.getAccountAddress();
    val item = DnsItem.fromAddress(itemAddress);

    return (item, collection, deployer, bidder);
}

fun activeShardAccount(addr: address): TlbShardAccount {
    val shard = testing.getShardAccount(addr);
    if (shard != null) {
        return shard!;
    }
    Assert.fail("Expected TlbShardAccount");
}

fun activeAccountInfo(addr: address): TlbAccountInfo {
    val account = activeShardAccount(addr).account.load();
    if (account is TlbAccountInfo) {
        return account;
    }
    Assert.fail("Expected TlbAccountInfo");
}

fun activeDataCell(addr: address): cell {
    val info = activeAccountInfo(addr);
    if (info.storage.state is TlbAccountStateActive) {
        val active = info.storage.state;
        if (active.stateInit.data == null) {
            Assert.fail("Expected active state data");
        }
        return active.stateInit.data!;
    }
    Assert.fail("Expected active account state");
}

fun setActiveDataCell(addr: address, newData: cell) {
    var updatedShard = activeShardAccount(addr);
    val account = updatedShard.account.load();
    if (account !is TlbAccountInfo) {
        Assert.fail("Expected TlbAccountInfo when setting data");
    }

    var info = account;
    if (info.storage.state !is TlbAccountStateActive) {
        Assert.fail("Expected TlbAccountStateActive when setting data");
    }

    var active = info.storage.state;
    active.stateInit.data = newData;
    info.storage.state = active;
    updatedShard.account = info.toCell() as cell as Cell<TlbAccount>;
    testing.setShardAccount(addr, updatedShard);
}

fun setGovernanceDecision(index: uint256, decision: RemainingBitsAndRefs) {
    var config = testing.getConfig();
    var governanceMap: map<uint256, RemainingBitsAndRefs> = [];
    governanceMap.set(index, decision);

    val paramCell = beginCell().storeDict(governanceMap.toLowLevelDict()).endCell();
    config.setParamRaw(DNS_CONFIG_ID, paramCell);
    expect(testing.setConfig(config)).toEqual(true);
}

fun completeAuction(item: DnsItem, sender: address, queryId: int = 1): SendResultList {
    val auction = item.getAuctionInfo();
    testing.setNow((auction.auctionEndTime + 1));

    return item.sendGetStaticData(sender, queryId, { value: ton("1"), bounce: true });
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

fun TlbCommonMessageInfo.toInternal(self): TlbInternalMessage {
    match (self) {
        TlbInternalMessage => {
            return self;
        }
        TlbExternalInMessageInfo => {
            Assert.fail("expected internal message info");
        }
        TlbExternalOutMessageInfo => {
            Assert.fail("expected internal message info");
        }
    }
}
