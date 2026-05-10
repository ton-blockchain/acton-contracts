import "@acton/build"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "common"
import "../wrappers/NotcoinMinter.gen"
import "../wrappers/NotcoinWallet.gen"
import "../wrappers/utils"

fun main() {
    val walletName = "deployer";
    val deployer = scripts.wallet(walletName);
    val initialSupply = envOr("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr("JETTON_METADATA_URI", "https://ton-blockchain.github.io/acton/logo.png");
    val transferRecipient = envOr(
        "JETTON_TRANSFER_RECIPIENT",
        scripts.wallet("jetton-recipient-1").address,
    );
    val transferAmount = envOr("JETTON_TRANSFER_AMOUNT", ton("0.1"));
    val value = envOr("JETTON_TRANSFER_VALUE", ton("0.08"));
    val forwardTonAmount = envOr("JETTON_FORWARD_TON_AMOUNT", ton("0.01"));
    val prefundMintAmount = envOr("JETTON_PREFUND_MINT_AMOUNT", ton("0.5"));
    val prefundMintTonAmount = envOr("JETTON_PREFUND_MINT_TON_AMOUNT", ton("0.08"));
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

    val senderWallet = NotcoinWallet { address: minter.getWalletAddress(deployer.address) };
    val senderWalletDeployed = scripts.isContractDeployed(senderWallet.address);
    val senderBalanceBefore = senderWalletDeployed ? senderWallet.getJettonBalance() : 0 as coins;
    if (!senderWalletDeployed || senderBalanceBefore < transferAmount) {
        println("Prefunding sender wallet with {}", prefundMintAmount);
        val prefundRes = minter.sendMint(
            deployer.address,
            deployer.address,
            prefundMintAmount,
            forwardTonAmount,
            prefundMintTonAmount,
        );
        if (prefundRes.waitForFirstTransaction() == null) {
            println("Prefund mint failed");
            return;
        }
    }

    println("Minter address: {}", minter.address);
    println("Sender wallet: {}", senderWallet.address);
    println("Sender balance before: {}", senderWallet.getJettonBalance());
    println("Transfer recipient: {}", transferRecipient);
    println("Transfer amount: {}", transferAmount);

    val transferRes = senderWallet.sendTransfer(
        deployer.address,
        value,
        transferAmount,
        transferRecipient,
        deployer.address,
        null,
        forwardTonAmount,
        null,
    );
    if (transferRes.waitForFirstTransaction() == null) {
        println("Transfer failed");
        return;
    }

    val recipientWallet = NotcoinWallet { address: minter.getWalletAddress(transferRecipient) };

    println("Sender balance after: {}", senderWallet.getJettonBalance());
    println("Recipient wallet: {}", recipientWallet.address);
    println("Recipient balance: {}", recipientWallet.getJettonBalance());
}
