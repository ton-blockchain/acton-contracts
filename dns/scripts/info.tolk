import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../tests/test_utils"
import "../wrappers/DnsCollection"
import "../wrappers/DnsItem"
import "../wrappers/DnsRoot"

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
            println("Root is not deployed in the current execution context: {}", root.address);
        } else {
            val ton = root.dnsresolve(makeTonDomainSlice(), 0);
            val tonWww = root.dnsresolve(makeTonWwwDomainSlice(), 0);
            val tMe = root.dnsresolve(makeTMeDomainSlice(), 0);

            println("Root address: {}", root.address);
            println(
                ".ton resolver: {}",
                ton.resolvedRecord == null ? null : parseNextResolverCell(ton.resolvedRecord!),
            );
            println(
                ".ton.www resolver: {}",
                tonWww.resolvedRecord == null
                    ? null
                    : parseNextResolverCell(tonWww.resolvedRecord!),
            );
            println(
                ".t.me resolver: {}",
                tMe.resolvedRecord == null ? null : parseNextResolverCell(tMe.resolvedRecord!),
            );
        }
    }

    if (collectionAddress != null) {
        val collection = NftCollectionContract.fromAddress(collectionAddress!);

        if (!net.isDeployed(collection.address)) {
            println(
                "Collection is not deployed in the current execution context: {}",
                collection.address,
            );
        } else {
            val data = collection.getCollectionData();

            println("Collection address: {}", collection.address);
            println("Next item index: {}", data.nextItemIndex);
            println("Content hash: {}", data.content.hash());

            if (domain != null) {
                println(
                    "Predicted item address: {}",
                    collection.getNftAddressByIndex(domain!.beginParse().hash()),
                );
            }
        }
    }

    if (itemAddress != null) {
        val item = NftItemContract.fromAddress(itemAddress!);

        if (!net.isDeployed(item.address)) {
            println("Item is not deployed in the current execution context: {}", item.address);
        } else {
            val data = item.getNftData();

            println("Item address: {}", item.address);
            println("Initialized: {}", data.isInitialized);
            println("Index: {}", data.index);
            println("Collection: {}", data.collectionAddress);
            println("Owner: {}", data.ownerAddress);

            if (data.isInitialized) {
                val walletRecord = item.dnsresolve(makeDotSlice(), "wallet".toBase256());
                println("Editor: {}", item.getEditor());
                println("Last fill up time: {}", item.getLastFillUpTime());
                println("Auction: {}", item.getAuctionInfo());
                println("Wallet record present: {}", walletRecord.resolvedRecord != null);
            }
        }
    }
}
