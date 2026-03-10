import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "../contracts/storage"
import "../tests/wrappers/JettonMinter"

fun main() {
    val supply = envOr<int>("JETTON_SUPPLY", 1000000000);
    val metadataUri = "https://ton.org/download/ton_symbol.svg";
    val walletName = "deployer-1";

    println(format1("Using wallet: {}", walletName));
    println(format1("Metadata URI: {}", metadataUri));
    println1("Broadcast mode: {}", net.isBroadcasting());

    val deployer = net.wallet(walletName);
    println1("Resolved deployer address: {}", deployer.address);

    val minter = JettonMinter.fromStorage({
        totalSupply: supply,
        adminAddress: deployer.address,
        metadataUri,
        nextAdminAddress: null,
    });
    println1("Prepared minter address: {}", minter.address);

    println1("Deploying acton_jetton_minter at {}", minter.address);
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.05") });
    if (!deployRes.wait()) {
        println("Deployment failed");
        return;
    }

    println1("Minting tokens to deployer: {}", supply);
    val mintRes = minter.sendMint(
        deployer.address,
        deployer.address,
        supply,
        ton("0.01"),
        ton("0.03"),
    );
    if (!mintRes.wait()) {
        println("Mint failed");
        return;
    }

    println1("Deployed Jetton Minter: {}", minter.address);
    println1("Admin: {}", deployer.address);
}
