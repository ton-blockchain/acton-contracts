import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "../tests/wrappers/JettonMinter"

fun main() {
    val walletName = "deployer-1";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr<int>("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr<string>(
        "JETTON_METADATA_URI",
        "https://ton.org/download/ton_symbol.svg",
    );
    val nextAdmin = envOr<address>("JETTON_NEXT_ADMIN", deployer.address);
    val deployValue = envOr<int>("JETTON_DEPLOY_VALUE", ton("0.05"));

    val expectedMinter = JettonMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
        jettonWalletCode: build("notcoin_wallet"),
        metadataUri,
        nextAdminAddress: null,
    });
    var minter = expectedMinter;
    val minterAddress = env<address>("JETTON_MINTER_ADDRESS");
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
    println1("Current admin: {}", minter.getAdminAddress());
    println1("Requested next admin: {}", nextAdmin);

    val changeRes = minter.sendChangeAdmin(deployer.address, nextAdmin);
    if (!changeRes.wait()) {
        println("Change admin failed");
        return;
    }

    println1("Admin handoff requested by {}", deployer.address);
    println1("Admin after request remains: {}", minter.getAdminAddress());
}
