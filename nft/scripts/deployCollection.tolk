import "@acton/emulation/scripts"
import "utils/common"

fun main() {
    val deployer2 = scripts.wallet("dfdfs");
    val deployer = promptNftWallet("Select NFT Deployer");
    val info = promptNftCollectionInfo();

    val collection = deployNftCollection(deployer, info);

    printNftCollectionInfo(collection, "NFT");
}
