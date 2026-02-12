import "wrappers/DnsCollection"
import "wrappers/DnsItem"
import "wrappers/RootDns"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/constants"
import "../contracts/storage"
import "../contracts/messages"

const COLLECTION_HASH_1 = 0x348bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f
const COLLECTION_HASH_2 = 0xa48bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f
const COLLECTION_HASH_3 = 0xb48bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f
const OWNER_HASH = 0x448bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f
const USER_HASH = 0x548bcf827469c5fc38541c77fdd91d4e347eac200f6f2d9fd62dc08885f0415f

const ALICE_INDEX = "alice".sha256()
const DNS_NEXT_RESOLVER_CATEGORY = "dns_next_resolver".toBase256()
const DNS_CATEGORY_WALLET = 0xe8d44050873dba865aa7c170ab4cce64d90839a34dcfd6cf71d14e0205443b1b

const DNS_NAME_CATEGORY_KEY = 0x82a3537ff0dbce7eec35d69edc3a189ee6f17d82f353a553f9aa96cb0be3ce89
const DNS_DESCRIPTION_CATEGORY_KEY = 0xc9046f7a37ad0ea7cee73355984fa5428982f8b37c8f7bcec91f7ac71a7cd104
const DNS_ICON_CATEGORY_KEY = 0x6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d

fun addrFromHash(hash: uint256): address {
    return address.fromWorkchainAndHash(BASECHAIN, hash);
}

fun collectionAddress1(): address {
    return addrFromHash(COLLECTION_HASH_1);
}

fun collectionAddress2(): address {
    return addrFromHash(COLLECTION_HASH_2);
}

fun collectionAddress3(): address {
    return addrFromHash(COLLECTION_HASH_3);
}

fun ownerAddress(): address {
    return addrFromHash(OWNER_HASH);
}

fun userAddress(): address {
    return addrFromHash(USER_HASH);
}

fun makeRootStorage(): RootDnsStorage {
    return {
        tonAddress: collectionAddress1(),
        tMeAddress: collectionAddress2(),
        tonWwwAddress: collectionAddress3(),
    };
}

fun makeCollectionContentCell(): cell {
    return beginCell().storeUint(1, 8).storeSlice("https://ton.org/collection.json".beginParse())
        .endCell();
}

fun makeCollectionStorage(): CollectionStorage {
    return {
        content: makeCollectionContentCell(),
        nftItemCode: build("dns_item"),
    };
}

fun makeDnsTextRecord(text: string): cell {
    return beginCell().storeUint(0, 8).storeSlice(text.beginParse()).endCell();
}

fun makeDefaultDnsRecords(): map<uint256, cell> {
    var m = createEmptyMap<uint256, cell>();
    m.set(DNS_NAME_CATEGORY_KEY, makeDnsTextRecord("alice.ton"));
    m.set(DNS_DESCRIPTION_CATEGORY_KEY, makeDnsTextRecord("TON Domain"));
    m.set(DNS_ICON_CATEGORY_KEY, makeDnsTextRecord("https://dns.ton.org/icon.png#alice"));
    return m;
}

fun makeDefaultDnsContentCell(): cell {
    return beginCell().storeUint(0, 8).storeDict(makeDefaultDnsRecords().toLowLevelDict()).endCell();
}

fun makeDomainCell(domain: string): cell {
    return beginCell().storeSlice(domain.beginParse()).endCell();
}

fun makeItemStorageNonInit(collectionAddress: address) {
    return ItemStorageNotInitialized {
        index: ALICE_INDEX,
        collectionAddress,
    };
}

fun makeItemInitBody(fromAddress: address, domain: string): cell {
    val domainName: DomainName = domain.beginParse();
    return ItemInitData {
        fromAddress,
        domain: domainName.toCell(),
    }.toCell();
}

fun makeSnakeTail(mutate remainder: slice): cell {
    if (remainder.remainingBitsCount() <= 1023) {
        return beginCell().storeSlice(remainder).endCell();
    }

    val head = remainder.loadBits(1023);
    val tail = makeSnakeTail(mutate remainder);
    return beginCell().storeSlice(head).storeRef(tail).endCell();
}

fun makeDeployBodyFromDomain(mutate domain: slice): cell {
    val firstChunkBits = domain.remainingBitsCount() > 991 ? 991 : domain.remainingBitsCount();
    var body = beginCell().storeUint(0, 32).storeSlice(domain.loadBits(firstChunkBits));

    if (domain.remainingBitsCount() > 0) {
        body.storeRef(makeSnakeTail(mutate domain));
    }

    return body.endCell();
}

fun makeDeployBody(domain: string): cell {
    var s = domain.beginParse();
    return makeDeployBodyFromDomain(mutate s);
}

fun repeatAsciiChar(charCode: int, count: int): slice {
    var b = beginCell();
    repeat (count) {
        b.storeUint(charCode, 8);
    }
    return b.endCell().beginParse();
}

fun parseNextResolver(cellValue: cell): (int, address) {
    val parsed = DnsNextResolver.fromCell(cellValue);
    return (DNS_NEXT_RESOLVER_PREFIX, parsed.resolver);
}

fun setDnsConfigEntry(index: uint256, value: slice) {
    var config = net.getConfig();
    var paramMap = createEmptyMap<uint256, RemainingBitsAndRefs>();
    paramMap.set(index, value);
    val paramCell = beginCell().storeDict(paramMap.toLowLevelDict()).endCell();
    config.setParamRaw(DNS_CONFIG_ID, paramCell);
    expect(net.setConfig(config)).toEqual(true);
}

fun setDnsBlacklist(index: uint256) {
    setDnsConfigEntry(index, beginCell().storeUint(1, 8).endCell().beginParse());
}

fun calcAuctionDurationForNow(nowTime: int): int {
    var months = (nowTime - AUCTION_START_TIME) / ONE_MONTH;
    if (months > 12) {
        months = 12;
    }

    return AUCTION_START_DURATION - (AUCTION_START_DURATION - AUCTION_END_DURATION) * months / 12;
}

fun newActor(name: string, extraTopUp: coins = 0): address {
    val actor = net.treasury(name).address;
    if (extraTopUp > 0) {
        net.topUp(actor, extraTopUp);
    }
    return actor;
}

fun deployRootContract() {
    val deployer = newActor("dns_root_deployer");
    val root = RootDnsContract.fromStorage(makeRootStorage());
    val res = root.deploy(deployer, { value: ton("10"), bounce: true });
    expect(res).toHaveSuccessfulDeploy({ to: root.address });
    return (root, deployer);
}

fun deployCollectionContract() {
    val deployer = newActor("dns_collection_deployer");
    val user = newActor("dns_collection_user");
    val collection = NftCollectionContract.fromStorage(makeCollectionStorage());
    val res = collection.deploy(deployer, { value: ton("10"), bounce: true });
    expect(res.size() > 0).toEqual(true);
    expect(res).toHaveSuccessfulDeploy({ to: collection.address });
    expect(net.isDeployed(collection.address)).toEqual(true);
    return (collection, deployer, user);
}

fun deployItemThroughCollection() {
    val (collection, owner, bidder) = deployCollectionContract();
    net.topUp(owner, ton("50000"));
    net.topUp(bidder, ton("50000"));

    val deployBody = makeDeployBody("alice");
    val deployRes = collection.sendAny(
        owner,
        deployBody,
        { value: ton("1000"), bounce: true },
    );
    expect(deployRes).toHaveSuccessfulTx({ from: owner, to: collection.address });

    val deployedItemTx = deployRes.findTransaction({ from: collection.address, deploy: true });
    expect(deployedItemTx).toBeDefined();
    val itemAddress = deployedItemTx.unwrap().getAccountAddress();
    val item = NftItemContract.fromAddress(itemAddress);
    return (item, collection, owner, bidder);
}

fun completeAuction(item: NftItemContract, sender: address, queryId: int = 1): SendResultList {
    val (_, _, auctionEndTime) = item.get_auction_info();
    net.setNow(auctionEndTime + 1);

    val body = beginCell().storeUint(OP_GET_STATIC_DATA, 32).storeUint(queryId, 64).endCell();
    return item.sendAny(sender, body, { value: ton("1"), bounce: true });
}

fun makeTransferBody(
    queryId: int,
    newOwnerAddress: address,
    responseDestination: address?,
    forwardTonAmount: coins,
): cell {
    val emptyForwardPayload = createEmptyCell().beginParse();
    return TransferOwnership {
        queryId: queryId as uint64,
        transferData: {
            newOwnerAddress,
            responseDestination,
            customPayload: null,
            forwardAmount: forwardTonAmount,
            forwardPayload: emptyForwardPayload,
        },
    }.toCell();
}

fun makeEditContentBody(queryId: int, newContent: cell): cell {
    return beginCell().storeUint(OP_EDIT_CONTENT, 32).storeUint(queryId, 64).storeRef(newContent)
        .endCell();
}

fun makeChangeDnsRecordBody(queryId: int, key: uint256, value: cell?): cell {
    var b = beginCell().storeUint(OP_CHANGE_DNS_RECORD, 32).storeUint(queryId, 64).storeUint(key, 256);
    if (value != null) {
        b.storeRef(value!!);
    }
    return b.endCell();
}

fun makeProcessGovernanceBody(queryId: int): cell {
    return beginCell().storeUint(OP_PROCESS_GOVERNANCE_DECISION, 32).storeUint(queryId, 64).endCell();
}

fun makeDnsBalanceReleaseBody(queryId: int): cell {
    return beginCell().storeUint(OP_DNS_BALANCE_RELEASE, 32).storeUint(queryId, 64).endCell();
}

fun makeGetStaticDataBody(queryId: int): cell {
    return beginCell().storeUint(OP_GET_STATIC_DATA, 32).storeUint(queryId, 64).endCell();
}

fun makeWalletDnsRecord(wallet: address): cell {
    return beginCell().storeUint(0x9fd3, 16).storeAddress(wallet).storeUint(0, 1).endCell();
}

fun makeTonDomainSlice(): slice {
    return beginCell().storeSlice("ton".literalSlice()).storeUint(0, 8).endCell().beginParse();
}

fun makeTonAliceDomainSlice(): slice {
    return beginCell().storeSlice("ton".literalSlice()).storeUint(0, 8).storeSlice(
        "alice".literalSlice()
    ).storeUint(0, 8).endCell().beginParse();
}

fun makeTonWwwDomainSlice(): slice {
    return beginCell().storeSlice("ton".literalSlice()).storeUint(0, 8).storeSlice(
        "www".literalSlice()
    ).storeUint(0, 8).endCell().beginParse();
}

fun makeTMeDomainSlice(): slice {
    return beginCell().storeSlice("me".literalSlice()).storeUint(0, 8).storeSlice("t".literalSlice())
        .storeUint(0, 8).endCell().beginParse();
}

fun makeDotSlice(): slice {
    return beginCell().storeUint(0, 8).endCell().beginParse();
}

fun makeLeadingDot(domain: slice): slice {
    return beginCell().storeUint(0, 8).storeSlice(domain).endCell().beginParse();
}
