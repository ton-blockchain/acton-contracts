import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../tests/test_utils"
import "../tests/wrappers/DnsCollection"
import "../tests/wrappers/DnsItem"
import "../tests/wrappers/DnsRoot"

fun main() {
    val rootAddress: address? = env("ROOT_ADDRESS");
    val collectionAddress: address? = env("COLLECTION_ADDRESS");
    val itemAddress: address? = env("ITEM_ADDRESS");
    val domain: string? = env("DNS_DOMAIN");

    if ((rootAddress ?? collectionAddress ?? itemAddress) == null) {
        println("Set ROOT_ADDRESS, COLLECTION_ADDRESS, or ITEM_ADDRESS before running this script.");
        return;
    }

    if (rootAddress != null) {
        val root = RootDnsContract.fromAddress(rootAddress!);
        if (!net.isDeployed(root.address)) {
            println1("Root is not deployed in the current execution context: {}", root.address);
        } else {
            val ton = root.dnsresolve(makeTonDomainSlice(), 0);
            val tonWww = root.dnsresolve(makeTonWwwDomainSlice(), 0);
            val tMe = root.dnsresolve(makeTMeDomainSlice(), 0);

            println1("Root address: {}", root.address);
            println1(
                ".ton resolver: {}",
                ton.resolvedRecord == null ? null : parseNextResolverCell(ton.resolvedRecord!),
            );
            println1(
                ".ton.www resolver: {}",
                tonWww.resolvedRecord == null
                    ? null
                    : parseNextResolverCell(tonWww.resolvedRecord!),
            );
            println1(
                ".t.me resolver: {}",
                tMe.resolvedRecord == null ? null : parseNextResolverCell(tMe.resolvedRecord!),
            );
        }
    }

    if (collectionAddress != null) {
        val collection = NftCollectionContract.fromAddress(collectionAddress!);

        if (!net.isDeployed(collection.address)) {
            println1(
                "Collection is not deployed in the current execution context: {}",
                collection.address,
            );
        } else {
            val data = collection.getCollectionData();

            println1("Collection address: {}", collection.address);
            println1("Next item index: {}", data.nextItemIndex);
            println1("Content hash: {}", data.content.hash());

            if (domain != null) {
                println1(
                    "Predicted item address: {}",
                    collection.getNftAddressByIndex(domain!.beginParse().hash()),
                );
            }
        }
    }

    if (itemAddress != null) {
        val item = NftItemContract.fromAddress(itemAddress!);

        if (!net.isDeployed(item.address)) {
            println1("Item is not deployed in the current execution context: {}", item.address);
        } else {
            val data = item.getNftData();

            println1("Item address: {}", item.address);
            println1("Initialized: {}", data.isInitialized);
            println1("Index: {}", data.index);
            println1("Collection: {}", data.collectionAddress);
            println1("Owner: {}", data.ownerAddress);

            if (data.isInitialized) {
                val walletRecord = item.dnsresolve(makeDotSlice(), "wallet".toBase256());
                println1("Editor: {}", item.getEditor());
                println1("Last fill up time: {}", item.getLastFillUpTime());
                println1("Auction: {}", item.getAuctionInfo());
                println1("Wallet record present: {}", walletRecord.resolvedRecord != null);
            }
        }
    }
}
