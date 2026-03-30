import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"
import "../tests/wrappers/DnsCollection"
import "../tests/wrappers/DnsItem"
import "../tests/wrappers/DnsRoot"

fun main() {
    val deployer = dnsSenderAddress();
    val wallet = dnsWallet();

    val rootAddress = envAddressOrNull("ROOT_ADDRESS");
    val collectionAddress = envAddressOrNull("COLLECTION_ADDRESS");
    val itemAddress = envAddressOrNull("ITEM_ADDRESS");
    val domain = envString("DNS_DOMAIN", DNS_DEFAULT_DOMAIN);
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
        ? deployDnsCollectionContract(
            deployer,
            envString("DNS_COLLECTION_CONTENT_URI", DNS_DEFAULT_COLLECTION_URI),
        )
        : NftCollectionContract.fromAddress(collectionAddress);

    println1("DEPLOYER_WALLET={}", dnsWalletName());
    println1("DEPLOYER_ADDRESS={}", wallet.address);
    println1("ROOT_ADDRESS={}", root.address);
    println1("COLLECTION_ADDRESS={}", collection.address);
    println1("PREDICTED_ITEM_ADDRESS={}", collection.getNftAddressByIndex(dnsDomainIndex(domain)));

    printRootInfo(root, "DNS");
    printCollectionInfo(collection, "DNS");

    if (itemAddress != null) {
        val item = NftItemContract.fromAddress(itemAddress);
        if (!net.isDeployed(item.address)) {
            println1("ITEM_ADDRESS={}", item.address);
            println("Item is not deployed at the provided address");
            return;
        }
        println1("ITEM_ADDRESS={}", item.address);
        printDnsItemInfo(item, "DNS");
        return;
    }

    if (!dnsShouldDeployItem()) {
        println("Item inspection skipped. Set ITEM_ADDRESS or DNS_DEPLOY_ITEM=1 to inspect an item.");
        return;
    }

    val item = deployDnsDomainContract(collection, deployer, domain, dnsDomainBid());
    completeDnsAuction(item, deployer).wait();
    println1("ITEM_ADDRESS={}", item.address);
    printDnsItemInfo(item, "DNS");
}
