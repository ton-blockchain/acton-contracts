import "@stdlib/reflection"
import "@acton/env"
import "@acton/fmt"
import "@acton/emulation/network"
import "@acton/promts/prompts"
import "@acton/vm/vm"
import "utils/common"


fun main() {
    val deployer = net.wallet(promptWallet("Select NFT Deployer"));
    val info = nftCollectionInfo();
    val itemContent = prompt("Enter item content path", NFT_DEFAULT_ITEM_CONTENT);
    val owner = vm.convertAddress(prompt("Enter NFT Item owner", format("{}", deployer.address)));

    val collection = resolveOrDeployCollection(deployer, info);

    // println("DEPLOYER_WALLET={}", nftWalletName());
    // println("COLLECTION_ADDRESS={}", collection.address);
    // println("NFT_ITEM_CONTENT={}", itemContent);
    // println("NFT_OWNER_ADDRESS={}", owner);

    val item = deployNftItemContract(collection, deployer, owner, itemContent);

    printNftItemInfo(item, "NFT");
}
