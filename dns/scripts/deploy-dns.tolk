import "@stdlib/strings"
import "@acton/env"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "../contracts/messages"
import "../contracts/storage"
import "../tests/wrappers/DnsCollection"

fun main() {
    val deployer = net.wallet("deployer-2");

    val collectionUri: string = env("DNS_COLLECTION_CONTENT_URI") ??
    "https://example.com/dns/collection.json";

    val collection = NftCollectionContract.fromStorage(CollectionStorage {
        content: collectionUri.prefixWith01().toCell(),
        nftItemCode: build("dns_item"),
    });

    println("Using wallet: deployer-2");
    println1("Collection URI: {}", collectionUri);

    val deployResult = net.send(
        deployer.address,
        createMessage({
            bounce: false,
            value: ton("0.05"),
            dest: { stateInit: collection.stateInit! },
            body: FillUp { queryId: 0 },
        }),
    );
    if (!deployResult.wait()) {
        println("Collection deployment was not confirmed");
        return;
    }

    println1("Collection deployed at {}", collection.address);
    println1("COLLECTION_ADDRESS={}", collection.address);

    val data = collection.getCollectionData();

    println1("Collection address: {}", collection.address);
    println1("Next item index: {}", data.nextItemIndex);
    println1("Content hash: {}", data.content.hash());
}
