import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "utils/common"

fun main() {
    val deployer = nftWallet();
    val info = nftCollectionInfo();
    val itemContent = envOr("NFT_ITEM_CONTENT", NFT_DEFAULT_ITEM_CONTENT);
    val newOwner = nftAddressOr("NFT_NEW_OWNER_ADDRESS", net.treasury("nft-new-owner").address);

    val collection = resolveOrDeployCollection(deployer, info);
    val item = resolveOrDeployItem(collection, deployer, itemContent);

    println1("DEPLOYER_WALLET={}", nftWalletName());
    println1("COLLECTION_ADDRESS={}", collection.address);
    println1("ITEM_ADDRESS={}", item.address);
    println1("NFT_NEW_OWNER_ADDRESS={}", newOwner);

    val res = item.sendAskToChangeOwnership(
        deployer.address,
        0,
        newOwner,
        null,
        emptySlice(),
        0,
        emptySlice(),
        { value: ton("0.05"), bounce: true },
    );
    res.wait();

    printNftItemInfo(item, "NFT");
}
