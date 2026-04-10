import "@acton/env"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "../contracts/messages"
import "../contracts/types"
import "../wrappers/NftCollectionContract"
import "../wrappers/NftItemContract"

const NFT_DEFAULT_COLLECTION_METADATA_URI = "https://example.com/nft/collection.json"
const NFT_DEFAULT_COMMON_CONTENT = "https://example.com/nft/"
const NFT_DEFAULT_ITEM_CONTENT = "item-0.json"
const NFT_DEFAULT_BATCH_CONTENT_PREFIX = "batch-"

fun nftWalletName(): string {
    return envOr("DEPLOYER_WALLET", "deployer");
}

fun nftWallet(): Wallet {
    return net.wallet(nftWalletName());
}

fun nftString(key: string, fallback: string): string {
    return envOr(key, fallback);
}

fun nftAddressOrNull(key: string): address? {
    return env(key);
}

fun makeNftCollectionMetadataCell(uri: string): cell {
    return beginCell().storeUint(1, 8).storeSlice(uri.beginParse()).endCell();
}

fun makeNftCollectionStorage(admin: address, collectionMetadataUri: string): NftCollectionStorage {
    return {
        adminAddress: admin,
        nextItemIndex: 0,
        content: CollectionContent {
            collectionMetadata: makeNftCollectionMetadataCell(collectionMetadataUri),
            commonContent: NFT_DEFAULT_COMMON_CONTENT,
        }.toCell(),
        nftItemCode: build("NftItem"),
        royaltyParams: RoyaltyParams {
            numerator: 5,
            denominator: 100,
            royaltyAddress: admin,
        }.toCell(),
    };
}

fun deployNftCollectionContract(
    deployer: Wallet,
    collectionMetadataUri: string,
): NftCollectionContract {
    val collection = NftCollectionContract.fromStorage(
        makeNftCollectionStorage(deployer.address, collectionMetadataUri),
    );
    val res = collection.deploy(deployer.address, { value: ton("0.05"), bounce: false });
    res.wait();
    return collection;
}

fun deployNftItemContract(
    collection: NftCollectionContract,
    deployer: Wallet,
    owner: address,
    itemContent: string,
): NftItemContract {
    val itemIndex = collection.getCollectionData().nextItemIndex;
    val res = collection.sendDeployNft(
        deployer.address,
        1,
        itemIndex,
        ton("0.03"),
        { ownerAddress: owner, content: itemContent },
        { value: ton("0.05"), bounce: true },
    );
    res.wait();
    return NftItemContract.fromAddress(collection.getNftAddressByIndex(itemIndex));
}

fun deployNftBatch(
    collection: NftCollectionContract,
    deployer: Wallet,
    owner: address,
    count: int,
): SendResultList {
    var deployList: map<uint64, BatchDeployDictItem> = [];
    var i = 0;
    val nextItemIndex = collection.getCollectionData().nextItemIndex;

    while (i < count) {
        val index = (nextItemIndex + i);
        deployList.set(
            index,
            BatchDeployDictItem {
                attachTonAmount: ton("0.03"),
                initParams: NftItemInitAtDeployment {
                    ownerAddress: owner,
                    content: NFT_DEFAULT_BATCH_CONTENT_PREFIX.concat(NFT_DEFAULT_ITEM_CONTENT),
                }.toCell(),
            },
        );
        i += 1;
    }

    return collection.sendBatchDeployNfts(
        deployer.address,
        2,
        deployList,
        { value: ton("0.15"), bounce: true },
    );
}

fun printNftCollectionInfo(collection: NftCollectionContract, label: string) {
    val data = collection.getCollectionData();
    val royalty = collection.royaltyParams();
    println("{} COLLECTION_ADDRESS={}", label, collection.address);
    println("{} ADMIN_ADDRESS={}", label, data.adminAddress);
    println("{} NEXT_ITEM_INDEX={}", label, data.nextItemIndex);
    println("{} COLLECTION_METADATA_HASH={}", label, data.collectionMetadata.hash());
    println("{} ROYALTY_ADDRESS={}", label, royalty.royaltyAddress);
    println("{} ROYALTY_NUMERATOR={}", label, royalty.numerator);
    println("{} ROYALTY_DENOMINATOR={}", label, royalty.denominator);
    println(
        "{} NFT_CONTENT_HASH={}",
        label,
        collection.getNftContent(0, NFT_DEFAULT_ITEM_CONTENT).hash(),
    );
}

fun printNftItemInfo(item: NftItemContract, label: string) {
    val data = item.getNftData();
    println("{} ITEM_ADDRESS={}", label, item.address);
    println("{} INITIALIZED={}", label, data.isInitialized);
    println("{} INDEX={}", label, data.itemIndex);
    println("{} COLLECTION_ADDRESS={}", label, data.collectionAddress);
    println("{} OWNER_ADDRESS={}", label, data.ownerAddress);
    println("{} CONTENT={}", label, data.content);
}
