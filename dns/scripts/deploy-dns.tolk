import "@stdlib/strings"
import "@acton/build"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/DnsCollection"

fun main() {
    val deployer = scripts.wallet("deployer-2");

    val collectionUri: string = env("DNS_COLLECTION_CONTENT_URI") ??
    "https://example.com/dns/collection.json";

    val collection = NftCollectionContract.fromStorage(CollectionStorage {
        content: collectionUri.prefixWith01().toCell(),
        nftItemCode: build("DnsItem"),
    });

    println("Using wallet: deployer-2");
    println("Collection URI: {}", collectionUri);

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

    println("Collection deployed at {}", collection.address);
    println("COLLECTION_ADDRESS={}", collection.address);

    val data = collection.getCollectionData();

    println("Collection address: {}", collection.address);
    println("Next item index: {}", data.nextItemIndex);
    println("Content hash: {}", data.content.hash());
}
