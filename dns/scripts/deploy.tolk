import "@acton/build/build"
import "@acton/emulation/network"
import "../contracts/storage"

fun makeCollectionContentCell(): cell {
    return beginCell()
        .storeUint(1, 8)
        .storeSlice("https://ton.org/collection.json".beginParse())
        .endCell();
}

fun deployCollection(deployer: Wallet) {
    val collectionStorage: CollectionStorage = {
        content: makeCollectionContentCell(),
        nftItemCode: build("dns_item"),
    };

    val stateInit = ContractState {
        code: build("dns_collection"),
        data: collectionStorage.toCell(),
    };

    val msg = createMessage({
        bounce: true,
        value: ton("1"),
        dest: { stateInit },
    });

    return net.send(deployer.address, msg);
}

fun deployRoot(
    deployer: Wallet,
    tonResolver: address,
    tMeResolver: address,
    tonWwwResolver: address,
) {
    val rootStorage: RootDnsStorage = {
        tonAddress: tonResolver,
        tMeAddress: tMeResolver,
        tonWwwAddress: tonWwwResolver,
    };

    val stateInit = ContractState { code: build("dns_root"), data: rootStorage.toCell() };

    val msg = createMessage({
        bounce: true,
        value: ton("1"),
        dest: { stateInit },
    });

    return net.send(deployer.address, msg);
}

fun main() {
    val deployer = net.wallet("deployer");

    val collectionTxs = deployCollection(deployer);
    println1("Collection deploy txs: {}", collectionTxs.size());

    // Replace these placeholders with real resolver addresses for your deployment topology.
    val sampleTonResolver = address("0:0000000000000000000000000000000000000000000000000000000000000000");
    val sampleTMeResolver = address("0:0000000000000000000000000000000000000000000000000000000000000000");
    val sampleTonWwwResolver = address("0:0000000000000000000000000000000000000000000000000000000000000000");

    val rootTxs = deployRoot(deployer, sampleTonResolver, sampleTMeResolver, sampleTonWwwResolver);
    println1("Root deploy txs: {}", rootTxs.size());
}
