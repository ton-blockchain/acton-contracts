import "@acton/build"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"
import "../contracts/types"
import "../wrappers/JettonMinter"
import "../wrappers/JettonWallet"

fun metadataUriFromContent(contentCell: cell): string? {
    val metadata = OnchainMetadataReply.fromCell(contentCell);
    val uriCell = metadata.contentDict.get("uri".sha256());
    if (!uriCell.isFound) {
        return null;
    }

    val uri = uriCell.loadValue().load();
    return uri.string;
}

fun getWalletStatus(wallet: JettonWallet): int {
    return net.runGetMethod(wallet.address, "get_status");
}

fun main() {
    val walletName = "deployer";
    val deployer = scripts.wallet(walletName);
    val initialSupply = envOr("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr("JETTON_METADATA_URI", "https://ton.org/download/ton_symbol.svg");
    val minterAddress: address? = env("JETTON_MINTER_ADDRESS");
    val ownerAddress = envOr("JETTON_OWNER_ADDRESS", deployer.address);

    val expectedMinter = JettonMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
        jettonWalletCode: build("NotcoinWallet"),
        metadataUri,
        nextAdminAddress: null,
    });
    var minter = expectedMinter;
    if (minterAddress != null) {
        minter = JettonMinter {
            address: minterAddress,
            init: expectedMinter.init,
        };
    }

    println("Expected minter address: {}", minter.address);
    if (minterAddress == null && !scripts.isContractDeployed(minter.address)) {
        val deployValue = envOr("JETTON_DEPLOY_VALUE", ton("0.05"));
        println("Deploying local minter for inspection with value {}", deployValue);
        val deployRes = minter.sendDeploy(deployer.address, { value: deployValue });
        if (!deployRes.wait()) {
            println("Deployment failed");
            return;
        }
    } else if (
        minterAddress != null && !net.isBroadcasting() &&
        !scripts.isContractDeployed(minter.address)
    ) {
        println("Minter is not deployed at {}", minter.address);
        return;
    }

    val data = minter.getJettonData();
    val uri = metadataUriFromContent(data.jettonContent);
    val wallet = JettonWallet { address: minter.getWalletAddress(ownerAddress) };
    val walletDeployed = scripts.isContractDeployed(wallet.address);

    println("Total supply: {}", data.totalSupply);
    println("Mintable: {}", data.mintable);
    println("Admin address: {}", data.adminAddress);
    if (uri == null) {
        println("Metadata URI: <unavailable>");
    } else {
        println("Metadata URI: {}", uri);
    }
    println("Owner address: {}", ownerAddress);
    println("Owner wallet: {}", wallet.address);
    if (envOr("JETTON_SHOW_WALLET_DETAILS", 0) == 0) {
        println("ActonWallet detail getters skipped by default. Set JETTON_SHOW_WALLET_DETAILS=1 to query wallet state.");
        return;
    }
    println("Owner wallet deployed: {}", walletDeployed);
    if (walletDeployed) {
        println("Owner wallet balance: {}", wallet.getJettonBalance());
        println("Owner wallet status: {}", getWalletStatus(wallet));
    } else {
        println("Owner wallet balance: <unavailable>");
        println("Owner wallet status: <unavailable>");
    }
}
