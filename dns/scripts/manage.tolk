import "@acton/env"
import "@acton/io"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "common"
import "../contracts/dns-utils"
import "../contracts/messages"
import "../tests/wrappers/DnsCollection"
import "../tests/wrappers/DnsItem"
import "../tests/wrappers/DnsRoot"

fun setGovernanceDecision(index: uint256, decision: RemainingBitsAndRefs) {
    var config = net.getConfig();
    var governanceMap: map<uint256, RemainingBitsAndRefs> = [];
    governanceMap.set(index, decision);

    val paramCell = beginCell().storeDict(governanceMap.toLowLevelDict()).endCell();
    config.setParamRaw(DNS_CONFIG_ID, paramCell);
    net.setConfig(config);
}

fun main() {
    val deployer = dnsSenderAddress();
    val wallet = dnsWallet();
    val domain = envString("DNS_DOMAIN", DNS_DEFAULT_DOMAIN);
    val collectionUri = envString("DNS_COLLECTION_CONTENT_URI", DNS_DEFAULT_COLLECTION_URI);
    val bid = dnsDomainBid();
    val newContentUri = envString("DNS_NEW_CONTENT_URI", DNS_DEFAULT_DOMAIN_UPDATED_URI);
    val transferForwardTon = envCoins("DNS_TRANSFER_FORWARD_NANO", 10000000);
    val transferResponseTon = envCoins("DNS_TRANSFER_RESPONSE_NANO", 10000000);
    val releaseTon = envCoins("DNS_RELEASE_NANO", 2000000000);

    val rootAddress = envAddressOrNull("ROOT_ADDRESS");
    val collectionAddress = envAddressOrNull("COLLECTION_ADDRESS");
    val itemAddress = envAddressOrNull("ITEM_ADDRESS");
    val rootTonResolverMaybe = envAddressOrNull("ROOT_TON_RESOLVER");
    val rootTMeResolverMaybe = envAddressOrNull("ROOT_TME_RESOLVER");
    val rootTonWwwResolverMaybe = envAddressOrNull("ROOT_TON_WWW_RESOLVER");

    val root = rootAddress == null
        ? deployDnsRootContract(
            deployer,
            rootTonResolverMaybe == null
                ? net.randomAddress("dns-root-ton-resolver")
                : rootTonResolverMaybe,
            rootTMeResolverMaybe == null
                ? net.randomAddress("dns-root-tme-resolver")
                : rootTMeResolverMaybe,
            rootTonWwwResolverMaybe == null
                ? net.randomAddress("dns-root-ton-www-resolver")
                : rootTonWwwResolverMaybe,
        )
        : RootDnsContract.fromAddress(rootAddress);

    val collection = collectionAddress == null
        ? deployDnsCollectionContract(deployer, collectionUri)
        : NftCollectionContract.fromAddress(collectionAddress);

    println1("DEPLOYER_WALLET={}", dnsWalletName());
    println1("DEPLOYER_ADDRESS={}", wallet.address);
    println1("ROOT_ADDRESS={}", root.address);
    println1("COLLECTION_ADDRESS={}", collection.address);
    println1("PREDICTED_ITEM_ADDRESS={}", collection.getNftAddressByIndex(dnsDomainIndex(domain)));
    println1("DNS_NEW_CONTENT_URI={}", newContentUri);

    printRootInfo(root, "DNS");
    printCollectionInfo(collection, "DNS");

    if (itemAddress == null && !dnsShouldDeployItem()) {
        println("Item management skipped. Provide ITEM_ADDRESS or set DNS_DEPLOY_ITEM=1 and fund a >=10 TON bid.");
        return;
    }

    val item = itemAddress == null
        ? deployDnsDomainContract(collection, deployer, domain, bid)
        : NftItemContract.fromAddress(itemAddress);

    if (!net.isDeployed(item.address)) {
        println1("ITEM_ADDRESS={}", item.address);
        println("Item is not deployed at the requested address");
        return;
    }

    if (itemAddress == null) {
        completeDnsAuction(item, deployer).wait();
    }

    println1("ITEM_ADDRESS={}", item.address);

    val currentAuction = item.getAuctionInfo();
    println1("AUCTION_END_TIME={}", currentAuction.auctionEndTime);

    val domainOwner = deployer;
    val editResult = item.sendEditContent(
        domainOwner,
        11,
        makeDnsRecords(newContentUri),
        { value: ton("0.1"), bounce: true },
    );
    editResult.wait();

    val recordOwner = net.treasury("dns-record-owner");
    val transferResult = item.sendTransferOwnership(
        domainOwner,
        12,
        makeDnsTransferData(
            recordOwner.address,
            null,
            transferForwardTon,
            makeZeroForwardPayload(),
        ),
        { value: ton("0.2"), bounce: true },
    );
    transferResult.wait();

    val walletRecord = makeDnsWalletRecord(recordOwner.address);
    val changeRecord = item.sendChangeDnsRecord(
        recordOwner.address,
        13,
        DNS_WALLET_CATEGORY,
        beginCell().storeRef(walletRecord).endCell().beginParse(),
        { value: ton("0.1"), bounce: true },
    );
    changeRecord.wait();

    val governanceOwner = net.treasury("dns-governance-owner");
    val governanceCaller = net.treasury("dns-governance-caller");
    setGovernanceDecision(
        dnsDomainIndex(domain),
        GovernanceTransfer {
            transferData: makeDnsTransferData(
                governanceOwner.address,
                null,
                transferResponseTon,
                makeZeroForwardPayload(),
            ),
        }.toCell()
            .beginParse(),
    );

    val governanceResult = item.sendProcessGovernanceDecision(
        governanceCaller.address,
        14,
        { value: ton("0.1"), bounce: true },
    );
    governanceResult.wait();

    net.setNow((item.getLastFillUpTime() + ONE_YEAR + 1) as uint32);
    val releaseResult = item.sendDnsRecordRelease(
        governanceOwner.address,
        15,
        { value: releaseTon, bounce: true },
    );
    releaseResult.wait();

    printRootInfo(root, "DNS");
    printCollectionInfo(collection, "DNS");
    printDnsItemInfo(item, "DNS");
}
