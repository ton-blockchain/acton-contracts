import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = dnsSenderAddress();
    val wallet = dnsWallet();

    val rootTonResolver = envAddressOrNull("ROOT_TON_RESOLVER");
    val rootTMeResolver = envAddressOrNull("ROOT_TME_RESOLVER");
    val rootTonWwwResolver = envAddressOrNull("ROOT_TON_WWW_RESOLVER");
    val tonResolver = rootTonResolver == null
        ? net.randomAddress("dns-root-ton-resolver")
        : rootTonResolver;
    val tMeResolver = rootTMeResolver == null
        ? net.randomAddress("dns-root-tme-resolver")
        : rootTMeResolver;
    val tonWwwResolver = rootTonWwwResolver == null
        ? net.randomAddress("dns-root-ton-www-resolver")
        : rootTonWwwResolver;
    val collectionUri = envString("DNS_COLLECTION_CONTENT_URI", DNS_DEFAULT_COLLECTION_URI);
    val domain = envString("DNS_DOMAIN", DNS_DEFAULT_DOMAIN);
    val bid = dnsDomainBid();

    println1("DEPLOYER_WALLET={}", dnsWalletName());
    println1("DEPLOYER_ADDRESS={}", wallet.address);
    println1("ROOT_TON_RESOLVER={}", tonResolver);
    println1("ROOT_TME_RESOLVER={}", tMeResolver);
    println1("ROOT_TON_WWW_RESOLVER={}", tonWwwResolver);
    println1("DNS_ROOT_DEPLOY_NANO={}", dnsRootDeployValue());
    println1("DNS_COLLECTION_DEPLOY_NANO={}", dnsCollectionDeployValue());
    println1("DNS_COLLECTION_CONTENT_URI={}", collectionUri);
    println1("DNS_DOMAIN={}", domain);
    println1("DNS_DOMAIN_BID_NANO={}", bid);
    println1("DNS_DEPLOY_ITEM={}", dnsShouldDeployItem());

    val root = deployDnsRootContract(deployer, tonResolver, tMeResolver, tonWwwResolver);
    val collection = deployDnsCollectionContract(deployer, collectionUri);

    printRootInfo(root, "DNS");
    printCollectionInfo(collection, "DNS");
    println1("ROOT_ADDRESS={}", root.address);
    println1("COLLECTION_ADDRESS={}", collection.address);
    println1("PREDICTED_ITEM_ADDRESS={}", collection.getNftAddressByIndex(dnsDomainIndex(domain)));

    if (!dnsShouldDeployItem()) {
        println("DNS item deployment is opt-in because it requires a >=10 TON auction bid and still fails in current emulation.");
        return;
    }

    val item = deployDnsDomainContract(collection, deployer, domain, bid);
    println1("ITEM_ADDRESS={}", item.address);
    printDnsItemInfo(item, "DNS");
}
