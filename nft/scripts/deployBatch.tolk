import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "utils/common"

fun main() {
    val deployer = nftWallet();
    val info = nftCollectionInfo();
    val batchOwner = nftAddressOr("NFT_BATCH_OWNER_ADDRESS", deployer.address);
    val batchCount = envOr("NFT_BATCH_COUNT", 3);

    val collection = resolveOrDeployCollection(deployer, info);

    println1("DEPLOYER_WALLET={}", nftWalletName());
    println1("COLLECTION_ADDRESS={}", collection.address);
    println1("NFT_BATCH_OWNER_ADDRESS={}", batchOwner);
    println1("NFT_BATCH_COUNT={}", batchCount);

    val res = deployNftBatch(collection, deployer, batchOwner, batchCount);
    res.wait();

    printNftCollectionInfo(collection, "NFT");
}
