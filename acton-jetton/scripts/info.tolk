import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "../contracts/types"
import "../tests/wrappers/JettonMinter"
import "../tests/wrappers/JettonWallet"

fun metadataUriFromContent(contentCell: cell): string? {
    val metadata = OnchainMetadataReply.fromCell(contentCell);
    val uriCell = metadata.contentDict.get("uri".sha256());
    if (!uriCell.isFound) {
        return null;
    }

    val uri = uriCell.loadValue().load();
    return uri.string;
}

fun main() {
    val walletName = "deployer";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr<int>("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr<string>(
        "JETTON_METADATA_URI",
        "https://ton.org/download/ton_symbol.svg",
    );
    val minterAddress = env<address>("JETTON_MINTER_ADDRESS");
    val ownerAddress = envOr<address>("JETTON_OWNER_ADDRESS", deployer.address);

    val expectedMinter = JettonMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
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

    println1("Expected minter address: {}", minter.address);
    if (minterAddress == null && !net.isDeployed(minter.address)) {
        val deployValue = envOr<int>("JETTON_DEPLOY_VALUE", ton("0.05"));
        println1("Deploying local minter for inspection with value {}", deployValue);
        val deployRes = minter.sendDeploy(deployer.address, { value: deployValue });
        if (!deployRes.wait()) {
            println("Deployment failed");
            return;
        }
    } else if (minterAddress != null && !net.isBroadcasting() && !net.isDeployed(minter.address)) {
        println1("Minter is not deployed at {}", minter.address);
        return;
    }

    val data = minter.getJettonData();
    val uri = metadataUriFromContent(data.jettonContent);
    val wallet = JettonWallet { address: minter.getWalletAddress(ownerAddress) };
    val walletDeployed = net.isDeployed(wallet.address);

    println1("Total supply: {}", data.totalSupply);
    println1("Mintable: {}", data.mintable);
    println1("Admin address: {}", data.adminAddress);
    if (uri == null) {
        println("Metadata URI: <unavailable>");
    } else {
        println1("Metadata URI: {}", uri);
    }
    println1("Owner address: {}", ownerAddress);
    println1("Owner wallet: {}", wallet.address);
    if (envOr<int>("JETTON_SHOW_WALLET_DETAILS", 0) == 0) {
        println("Wallet detail getters skipped by default. Set JETTON_SHOW_WALLET_DETAILS=1 to query wallet state.");
        return;
    }
    println1("Owner wallet deployed: {}", walletDeployed);
    if (walletDeployed) {
        println1("Owner wallet balance: {}", wallet.getJettonBalance());
    } else {
        println("Owner wallet balance: <unavailable>");
    }
}
