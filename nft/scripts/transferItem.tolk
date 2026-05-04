import "@acton/io"
import "@acton/emulation/network"
import "utils/common"
import "../wrappers/utils"

fun main() {
    val deployer = promptNftWallet("Select NFT Deployer");
    val item = promptNftItem("Enter NFT Item address");
    val newOwner = promptNftAddress("Enter new owner address");

    val res = item.sendTransferPayloadInline(
        deployer.address,
        0,
        newOwner,
        null,
        null,
        0,
        createEmptySlice(),
        { value: ton("0.05"), bounce: true },
    );
    println(res.waitForTrace());

    printNftItemInfo(item, "NFT");
}
