import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@acton/prompts"
import "utils/common"

fun main() {
    val deployer = promptNftWallet("Select NFT Deployer");
    val info = promptNftCollectionInfo();

    val collection = deployNftCollectionContract(deployer, info);

    printNftCollectionInfo(collection, "NFT");
}
