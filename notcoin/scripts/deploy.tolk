import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/build/build"
import "@acton/emulation/network"
import "../tests/wrappers/JettonMinter"

fun main() {
    val supply = envOr<int>("JETTON_SUPPLY", 1000000000);

    val deployer = net.wallet("deployer");

    val minter = JettonMinter.fromStorage({
        totalSupply: supply,
        adminAddress: deployer.address,
        jettonWalletCode: build("notcoin_wallet"),
        metadataUri: "https://ton.org/download/ton_symbol.svg",
        nextAdminAddress: null,
    });

    println("Deploying Jetton contract...");
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.03") });
    deployRes.wait();

    println1("Minting tokens: {}", supply);
    val mintRes = minter.sendMint(
        deployer.address,
        deployer.address,
        supply,
        ton("0.01"),
        ton("0.02")
    );
    if (!mintRes.wait()) {
        return;
    }

    println(format2("Succesfully minted and transfered {} tokens to {}", supply, deployer.address));
}
