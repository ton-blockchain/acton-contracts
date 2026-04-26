import "@acton/build"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"
import "../wrappers/JettonMinter"
import "../wrappers/JettonWallet"

fun main() {
    val walletName = "deployer";
    val deployer = scripts.wallet(walletName);
    val initialSupply = envOr("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr("JETTON_METADATA_URI", "https://ton.org/download/ton_symbol.svg");
    val mintRecipient = envOr("JETTON_MINT_RECIPIENT", deployer.address);
    val mintAmount = envOr("JETTON_MINT_AMOUNT", ton("0.5"));
    val forwardTonAmount = envOr("JETTON_FORWARD_TON_AMOUNT", ton("0.01"));
    val totalTonAmount = envOr("JETTON_MINT_TON_AMOUNT", ton("0.08"));
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
    println("Mint recipient: {}", mintRecipient);
    println("Mint amount: {}", mintAmount);
    println("Mint TON value: {}", totalTonAmount);

    val mintRes = minter.sendMint(
        deployer.address,
        mintRecipient,
        mintAmount,
        forwardTonAmount,
        totalTonAmount,
    );
    if (mintRes.waitForFirstTransaction() == null) {
        println("Mint failed");
        return;
    }

    val recipientWallet = JettonWallet { address: minter.getWalletAddress(mintRecipient) };

    println("Total supply: {}", minter.getTotalSupply());
    println("Recipient wallet: {}", recipientWallet.address);
    println("Recipient wallet balance: {}", recipientWallet.getJettonBalance());
}
