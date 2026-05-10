import "@acton/build"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"
import "../contracts/storage"
import "../wrappers/NotcoinMinter.gen"
import "../wrappers/utils"

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
    val deployer = scripts.wallet(walletName);
    val initialSupply = envOr("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr(
        "JETTON_METADATA_URI",
        "https://ton-blockchain.github.io/acton/logo.png",
    );
    val newMetadataUri = envOr(
        "JETTON_NEW_METADATA_URI",
        "https://ton-blockchain.github.io/acton/logo.png",
    );
    val deployValue = envOr("JETTON_DEPLOY_VALUE", ton("0.05"));

    val expectedMinter = NotcoinMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
        jettonWalletCode: build("NotcoinWallet"),
        metadataUri,
        nextAdminAddress: null,
    });
    val minterAddress: address? = env("JETTON_MINTER_ADDRESS");
    var minter = expectedMinter;
    if (minterAddress != null) {
        minter = NotcoinMinter {
            address: minterAddress,
            stateInit: expectedMinter.stateInit,
        };
    }

    if (minterAddress == null) {
        if (!scripts.isContractDeployed(minter.address)) {
            val deployRes = minter.sendDeploy(deployer.address, { value: deployValue });
            if (deployRes.waitForFirstTransaction() == null) {
                println("Deployment failed");
                return;
            }
        }
    } else if (!net.isBroadcasting() && !scripts.isContractDeployed(minter.address)) {
        println("Minter is not deployed at {}", minter.address);
        return;
    }

    println("Minter address: {}", minter.address);

    val oldUri = metadataUriFromContent(minter.getContent());
    if (oldUri == null) {
        println("Current metadata URI: <unavailable>");
    } else {
        println("Current metadata URI: {}", oldUri);
    }
    println("New metadata URI: {}", newMetadataUri);

    val changeRes = minter.sendChangeMetadata(deployer.address, newMetadataUri);
    if (changeRes.waitForFirstTransaction() == null) {
        println("Change metadata failed");
        return;
    }

    val updatedUri = metadataUriFromContent(minter.getContent());
    if (updatedUri == null) {
        println("Updated metadata URI: <unavailable>");
    } else {
        println("Updated metadata URI: {}", updatedUri);
    }
}
