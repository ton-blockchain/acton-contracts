import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "utils/common"

fun main() {
    val deployer = nftWallet();
    val info = nftCollectionInfo();
    val newAdmin = nftAddressOr("NFT_NEW_ADMIN_ADDRESS", net.treasury("nft-new-admin").address);

    val collection = resolveOrDeployCollection(deployer, info);

    println1("DEPLOYER_WALLET={}", nftWalletName());
    println1("COLLECTION_ADDRESS={}", collection.address);
    println1("NFT_NEW_ADMIN_ADDRESS={}", newAdmin);

    val res = collection.sendChangeCollectionAdmin(
        deployer.address,
        0,
        newAdmin,
        { value: ton("0.05"), bounce: true },
    );
    res.wait();

    printNftCollectionInfo(collection, "NFT");
}
