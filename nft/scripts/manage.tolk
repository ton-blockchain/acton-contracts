import "@stdlib/tvm-dicts"
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
    val newAdminMaybe = nftAddressOrNull("NFT_NEW_ADMIN_ADDRESS");
    val newAdmin = newAdminMaybe == null ? net.treasury("nft-new-admin").address : newAdminMaybe;
    val newOwnerMaybe = nftAddressOrNull("NFT_NEW_OWNER_ADDRESS");
    val newOwner = newOwnerMaybe == null ? net.treasury("nft-new-owner").address : newOwnerMaybe;
    val batchOwnerMaybe = nftAddressOrNull("NFT_BATCH_OWNER_ADDRESS");
    val batchOwner = batchOwnerMaybe == null ? deployer.address : batchOwnerMaybe;
    val batchCount = envOr<int>("NFT_BATCH_COUNT", 3);

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
    println1("NFT_NEW_ADMIN_ADDRESS={}", newAdmin);
    println1("NFT_NEW_OWNER_ADDRESS={}", newOwner);

    val batchRes = deployNftBatch(collection, deployer, batchOwner, batchCount);
    batchRes.wait();

    val changeAdminRes = collection.sendChangeCollectionAdmin(
        deployer.address,
        3,
        newAdmin,
        { value: ton("0.05"), bounce: true },
    );
    changeAdminRes.wait();

    val transferRes = item.sendAskToChangeOwnership(
        deployer.address,
        4,
        newOwner,
        null,
        createEmptyDict(),
        0,
        beginCell().storeBool(false).toSlice(),
        { value: ton("0.05"), bounce: true },
    );
    transferRes.wait();

    printNftCollectionInfo(collection, "NFT");
    printNftItemInfo(item, "NFT");
}
