import "@acton/env"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "../wrappers/JettonMinter"

fun main() {
    val walletName = "deployer";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr("JETTON_METADATA_URI", "https://ton.org/download/ton_symbol.svg");
    val deployValue = envOr("JETTON_DEPLOY_VALUE", ton("0.05"));

    val expectedMinter = JettonMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
        jettonWalletCode: build("NotcoinWallet"),
        metadataUri,
        nextAdminAddress: null,
    });
    val minterAddress: address? = env("JETTON_MINTER_ADDRESS");
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
        println("Minter is not deployed at {}", minter.address);
        return;
    }

    println("Minter address: {}", minter.address);
    println("Admin before claim: {}", minter.getAdminAddress());

    val claimRes = minter.sendClaimAdmin(deployer.address);
    if (!claimRes.wait()) {
        println("Claim admin failed");
        return;
    }

    println("Admin after claim: {}", minter.getAdminAddress());
}
