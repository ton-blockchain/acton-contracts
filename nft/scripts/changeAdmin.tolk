import "@acton/io"
import "@acton/emulation/network"
import "utils/common"
import "../wrappers/NftCollection.gen"

fun main() {
    val deployer = promptNftWallet("Select NFT Deployer");
    val collection = promptNftCollection("Enter NFT Collection address");
    val newAdmin = promptNftAddress("Enter new admin address");

    val res = collection.sendChangeCollectionAdmin(
        deployer.address,
        0,
        newAdmin,
        { value: ton("0.05"), bounce: true },
    );
    println(res.waitForTrace());

    printNftCollectionInfo(collection, "NFT");
}
