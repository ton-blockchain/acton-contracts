import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"
import "../tests/wrappers/NftCollectionContract"
import "../tests/wrappers/NftItemContract"

fun main() {
    val deployer = nftWallet();
    val collectionMetadataUri = nftString(
        "NFT_COLLECTION_METADATA_URI",
        NFT_DEFAULT_COLLECTION_METADATA_URI,
    );
    val itemContent = nftString("NFT_ITEM_CONTENT", NFT_DEFAULT_ITEM_CONTENT);

    val collectionAddress = nftAddressOrNull("COLLECTION_ADDRESS");
    val itemAddress = nftAddressOrNull("ITEM_ADDRESS");

    val collection = collectionAddress == null
        ? deployNftCollectionContract(deployer, collectionMetadataUri)
        : NftCollectionContract.fromAddress(collectionAddress);

    val item = itemAddress == null
        ? deployNftItemContract(collection, deployer, deployer.address, itemContent)
        : NftItemContract.fromAddress(itemAddress);

    println1("DEPLOYER_WALLET={}", nftWalletName());
    println1("COLLECTION_ADDRESS={}", collection.address);
    println1("ITEM_ADDRESS={}", item.address);

    printNftCollectionInfo(collection, "NFT");
    printNftItemInfo(item, "NFT");
}
