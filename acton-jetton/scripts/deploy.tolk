import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "../tests/wrappers/JettonMinter"
import "../tests/wrappers/JettonWallet"

fun main() {
    val walletName = "deployer-1";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr<int>("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr<string>(
        "JETTON_METADATA_URI",
        "https://ton.org/download/ton_symbol.svg",
    );
    val deployValue = envOr<int>("JETTON_DEPLOY_VALUE", ton("0.05"));

    println1("Using wallet: {}", walletName);
    println1("Broadcast mode: {}", net.isBroadcasting());
    println1("Metadata URI: {}", metadataUri);
    println1("Deploy value: {}", deployValue);

    val minter = JettonMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
        metadataUri,
        nextAdminAddress: null,
    });
    println1("Prepared minter address: {}", minter.address);

    val deployRes = minter.sendDeploy(deployer.address, { value: deployValue });
    if (!deployRes.wait()) {
        println("Deployment failed");
        return;
    }

    val adminWallet = JettonWallet { address: minter.getWalletAddress(deployer.address) };
    val adminWalletDeployed = net.isDeployed(adminWallet.address);

    println1("Deployed acton_jetton_minter at {}", minter.address);
    println1("JETTON_MINTER_ADDRESS={}", minter.address);
    println1("MINTER_ADDRESS={}", minter.address);
    println1("Admin: {}", deployer.address);
    println1("ADMIN_WALLET_ADDRESS={}", adminWallet.address);
    println1("Admin wallet: {}", adminWallet.address);
    if (net.isBroadcasting()) {
        println("Admin wallet getters are skipped in broadcast mode; rerun info after minting if needed.");
    } else {
        println1("ADMIN_WALLET_DEPLOYED={}", adminWalletDeployed);
        if (adminWalletDeployed) {
            println1("Admin wallet balance: {}", adminWallet.getJettonBalance());
        } else {
            println("Admin wallet balance: <unavailable>");
        }
    }
    println1("Total supply: {}", minter.getTotalSupply());
    println1("Mintable: {}", minter.getJettonData().mintable);
}
