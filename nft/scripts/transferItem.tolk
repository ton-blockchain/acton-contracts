import "@stdlib/tvm-dicts"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/NftItemContract"

fun main() {
    val deployer = promptNftWallet("Select NFT Deployer");
    val item = promptNftItemContract("Enter NFT Item address");
    val newOwner = promptNftAddress(
        "Enter new owner address",
        scripts.wallet("nft-new-owner").address,
    );

    val res = item.sendAskToChangeOwnership(
        deployer.address,
        0,
        newOwner,
        null,
        createEmptyDict(),
        0,
        createEmptySlice(),
        { value: ton("0.05"), bounce: true },
    );
    res.wait();

    printNftItemInfo(item, "NFT");
}
