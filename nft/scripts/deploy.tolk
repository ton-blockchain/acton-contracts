import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "common"

fun main() {
    val deployer = nftWallet();
    val collectionMetadataUri = nftString(
        "NFT_COLLECTION_METADATA_URI",
        NFT_DEFAULT_COLLECTION_METADATA_URI,
    );
    val singleContent = nftString("NFT_ITEM_CONTENT", NFT_DEFAULT_ITEM_CONTENT);
    val ownerMaybe = nftAddressOrNull("NFT_OWNER_ADDRESS");
    val owner = ownerMaybe == null ? deployer.address : ownerMaybe;
    val batchOwnerMaybe = nftAddressOrNull("NFT_BATCH_OWNER_ADDRESS");
    val batchOwner = batchOwnerMaybe == null ? owner : batchOwnerMaybe;
    val batchCount = envOr("NFT_BATCH_COUNT", 3);

    println("DEPLOYER_WALLET={}", nftWalletName());
    println("NFT_COLLECTION_METADATA_URI={}", collectionMetadataUri);
    println("NFT_ITEM_CONTENT={}", singleContent);
    println("NFT_BATCH_COUNT={}", batchCount);

    val collection = deployNftCollectionContract(deployer, collectionMetadataUri);
    val item = deployNftItemContract(collection, deployer, owner, singleContent);
    val batchRes = deployNftBatch(collection, deployer, batchOwner, batchCount);
    batchRes.wait();

    printNftCollectionInfo(collection, "NFT");
    printNftItemInfo(item, "NFT");
}
