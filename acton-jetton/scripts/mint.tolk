import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "../tests/wrappers/JettonMinter"
import "../tests/wrappers/JettonWallet"

fun main() {
    val walletName = "deployer";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr<int>("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr<string>(
        "JETTON_METADATA_URI",
        "https://ton.org/download/ton_symbol.svg",
    );
    val mintRecipient = envOr<address>("JETTON_MINT_RECIPIENT", deployer.address);
    val mintAmount = envOr<int>("JETTON_MINT_AMOUNT", ton("0.5"));
    val forwardTonAmount = envOr<int>("JETTON_FORWARD_TON_AMOUNT", ton("0.01"));
    val totalTonAmount = envOr<int>("JETTON_MINT_TON_AMOUNT", ton("0.08"));
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
    println1("Mint recipient: {}", mintRecipient);
    println1("Mint amount: {}", mintAmount);
    println1("Mint TON value: {}", totalTonAmount);

    val mintRes = minter.sendMint(
        deployer.address,
        mintRecipient,
        mintAmount,
        forwardTonAmount,
        totalTonAmount,
    );
    if (!mintRes.wait()) {
        println("Mint failed");
        return;
    }

    val recipientWallet = JettonWallet { address: minter.getWalletAddress(mintRecipient) };

    println1("Total supply: {}", minter.getTotalSupply());
    println1("Recipient wallet: {}", recipientWallet.address);
    println1("Recipient wallet balance: {}", recipientWallet.getJettonBalance());
}
