import "@stdlib/strings"
import "@acton/env"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "../../contracts/messages"
import "../../contracts/types"
import "../../tests/wrappers/NftCollectionContract"
import "../../tests/wrappers/NftItemContract"

const ONCHAIN_CONTENT_PREFIX = 0x00
const SNAKE_PREFIX = 0x00

const NFT_DEFAULT_COLLECTION_NAME = "SomeNFT"
const NFT_DEFAULT_COLLECTION_DESCRIPTION = "Some NFT collection"
const NFT_DEFAULT_COLLECTION_IMAGE = "https://ton.org/download/ton_symbol.svg"
const NFT_DEFAULT_COMMON_CONTENT = "https://example.com/nft/"
const NFT_DEFAULT_ITEM_CONTENT = "item-0.json"
const NFT_DEFAULT_BATCH_CONTENT_PREFIX = "batch-"

struct NftCollectionInfo {
    name: string
    description: string
    image: string
}

fun string.toSnakeString(self): cell {
    return beginCell().storeUint(SNAKE_PREFIX, 8).storeSlice(self.beginParse()).endCell();
}

fun buildOnchainMetadata(info: NftCollectionInfo): cell {
    var dict: map<uint256, cell> = [];
    dict.set("name".sha256(), info.name.toSnakeString());
    dict.set("description".sha256(), info.description.toSnakeString());
    dict.set("image".sha256(), info.image.toSnakeString());
    return beginCell()
        .storeUint(ONCHAIN_CONTENT_PREFIX, 8)
        .storeDict(dict.toLowLevelDict())
        .endCell();
}

fun nftWalletName(): string {
    return envOr("DEPLOYER_WALLET", "deployer");
}

fun nftWallet(): Wallet {
    return net.wallet(nftWalletName());
}

fun nftAddressOrNull(key: string): address? {
    return env(key);
}

fun nftAddressOr(key: string, fallback: address): address {
    val v = nftAddressOrNull(key);
    return v == null ? fallback : v;
}

fun nftCollectionInfo(): NftCollectionInfo {
    return {
        name: envOr("NFT_COLLECTION_NAME", NFT_DEFAULT_COLLECTION_NAME),
        description: envOr("NFT_COLLECTION_DESCRIPTION", NFT_DEFAULT_COLLECTION_DESCRIPTION),
        image: envOr("NFT_COLLECTION_IMAGE", NFT_DEFAULT_COLLECTION_IMAGE),
    };
}

fun makeNftCollectionStorage(admin: address, info: NftCollectionInfo): NftCollectionStorage {
    return {
        adminAddress: admin,
        nextItemIndex: 0,
        content: CollectionContent {
            collectionMetadata: buildOnchainMetadata(info),
            commonContent: NFT_DEFAULT_COMMON_CONTENT,
        }.toCell(),
        nftItemCode: build("nft_item"),
        royaltyParams: RoyaltyParams {
            numerator: 5,
            denominator: 100,
            royaltyAddress: admin,
        }.toCell(),
    };
}

fun deployNftCollectionContract(
    deployer: Wallet,
    info: NftCollectionInfo,
): NftCollectionContract {
    val collection = NftCollectionContract.fromStorage(
        makeNftCollectionStorage(deployer.address, info),
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
        0,
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
                    content: NFT_DEFAULT_BATCH_CONTENT_PREFIX.concat(index.toDecimalString()).concat(".json"),
                }.toCell(),
            },
        );
        i += 1;
    }

    return collection.sendBatchDeployNfts(
        deployer.address,
        0,
        deployList,
        { value: ton("0.15"), bounce: true },
    );
}

fun resolveOrDeployCollection(deployer: Wallet, info: NftCollectionInfo): NftCollectionContract {
    val addr = nftAddressOrNull("COLLECTION_ADDRESS");
    return addr == null
        ? deployNftCollectionContract(deployer, info)
        : NftCollectionContract.fromAddress(addr);
}

fun resolveOrDeployItem(
    collection: NftCollectionContract,
    deployer: Wallet,
    content: string,
): NftItemContract {
    val addr = nftAddressOrNull("ITEM_ADDRESS");
    return addr == null
        ? deployNftItemContract(collection, deployer, deployer.address, content)
        : NftItemContract.fromAddress(addr);
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
