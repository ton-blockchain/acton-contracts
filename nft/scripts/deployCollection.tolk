import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "utils/common"

fun main() {
    val deployer = nftWallet();
    val info = nftCollectionInfo();

    println1("DEPLOYER_WALLET={}", nftWalletName());
    println1("NFT_COLLECTION={}", info);

    val collection = deployNftCollectionContract(deployer, info);

    printNftCollectionInfo(collection, "NFT");
}
