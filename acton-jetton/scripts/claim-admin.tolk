import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "../tests/wrappers/JettonMinter"

fun main() {
    val walletName = "deployer";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr<int>("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr<string>(
        "JETTON_METADATA_URI",
        "https://ton.org/download/ton_symbol.svg",
    );
    val nextAdmin = envOr<address>("JETTON_NEXT_ADMIN", deployer.address);
    val claimSender = envOr<address>("JETTON_PENDING_ADMIN_ADDRESS", nextAdmin);
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
    println1("Admin before claim: {}", minter.getAdminAddress());
    println1("Claim sender: {}", claimSender);

    val claimRes = minter.sendClaimAdmin(claimSender);
    if (!claimRes.wait()) {
        println("Claim admin failed");
        return;
    }

    println1("Admin after claim: {}", minter.getAdminAddress());
}
