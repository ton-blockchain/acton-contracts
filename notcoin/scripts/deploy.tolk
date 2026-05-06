import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"
import "../wrappers/NotcoinMinter.gen"
import "../wrappers/NotcoinWallet.gen"
import "../wrappers/utils"

fun main() {
    val walletName = "deployer";
    val deployer = scripts.wallet(walletName);
    val initialSupply = envOr("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr("JETTON_METADATA_URI", "https://ton.org/download/ton_symbol.svg");
    val deployValue = envOr("JETTON_DEPLOY_VALUE", ton("0.05"));

    println("Using wallet: {}", walletName);
    println("Broadcast mode: {}", net.isBroadcasting());
    println("Metadata URI: {}", metadataUri);
    println("Deploy value: {}", deployValue);

    val minter = NotcoinMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
        jettonWalletCode: build("NotcoinWallet"),
        metadataUri,
        nextAdminAddress: null,
    });
    println("Prepared minter address: {}", minter.address);

    val deployRes = minter.sendDeploy(deployer.address, { value: deployValue });
    if (deployRes.waitForFirstTransaction() == null) {
        println("Deployment failed");
        return;
    }

    val adminWallet = NotcoinWallet { address: minter.getWalletAddress(deployer.address) };
    val adminWalletDeployed = scripts.isContractDeployed(adminWallet.address);

    println("Deployed notcoin minter at {}", minter.address);
    println("JETTON_MINTER_ADDRESS={}", minter.address);
    println("MINTER_ADDRESS={}", minter.address);
    println("Admin: {}", deployer.address);
    println("ADMIN_WALLET_ADDRESS={}", adminWallet.address);
    println("Admin wallet: {}", adminWallet.address);
    if (net.isBroadcasting()) {
        println("Admin wallet getters are skipped in broadcast mode; rerun info after minting if needed.");
    } else {
        println("ADMIN_WALLET_DEPLOYED={}", adminWalletDeployed);
        if (adminWalletDeployed) {
            println("Admin wallet balance: {}", adminWallet.getJettonBalance());
        } else {
            println("Admin wallet balance: <unavailable>");
        }
    }
    println("Total supply: {}", minter.getTotalSupply());
    println("Mintable: {}", minter.getJettonData().mintable);
}
