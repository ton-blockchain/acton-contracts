import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "../contracts/types"
import "../tests/wrappers/JettonMinter"

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
    val walletName = "deployer-1";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr<int>("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr<string>(
        "JETTON_METADATA_URI",
        "https://ton.org/download/ton_symbol.svg",
    );
    val newMetadataUri = envOr<string>(
        "JETTON_NEW_METADATA_URI",
        "https://ton.org/download/ton_symbol.svg?updated=1",
    );
    val deployValue = envOr<int>("JETTON_DEPLOY_VALUE", ton("0.05"));

    val expectedMinter = JettonMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
        metadataUri,
        nextAdminAddress: null,
    });
    val minterAddress = env<address>("JETTON_MINTER_ADDRESS");
    var minter = expectedMinter;
    if (minterAddress != null) {
        minter = JettonMinter {
            address: minterAddress,
            init: expectedMinter.init,
        };
    }

    if (minterAddress == null) {
        if (!net.isDeployed(minter.address)) {
            val deployRes = minter.sendDeploy(deployer.address, { value: deployValue });
            if (!deployRes.wait()) {
                println("Deployment failed");
                return;
            }
        }
    } else if (!net.isBroadcasting() && !net.isDeployed(minter.address)) {
        println1("Minter is not deployed at {}", minter.address);
        return;
    }

    println1("Minter address: {}", minter.address);

    val oldUri = metadataUriFromContent(minter.getContent());
    if (oldUri == null) {
        println("Current metadata URI: <unavailable>");
    } else {
        println1("Current metadata URI: {}", oldUri);
    }
    println1("New metadata URI: {}", newMetadataUri);

    val changeRes = minter.sendChangeMetadata(deployer.address, newMetadataUri);
    if (!changeRes.wait()) {
        println("Change metadata failed");
        return;
    }

    val updatedUri = metadataUriFromContent(minter.getContent());
    if (updatedUri == null) {
        println("Updated metadata URI: <unavailable>");
    } else {
        println1("Updated metadata URI: {}", updatedUri);
    }
}
