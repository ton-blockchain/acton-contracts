import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../tests/wrappers/JettonMinter"
import "../tests/wrappers/JettonWallet"

fun main() {
    val walletName = "deployer";
    val deployer = net.wallet(walletName);
    val initialSupply = envOr("JETTON_INITIAL_SUPPLY", 0);
    val metadataUri = envOr("JETTON_METADATA_URI", "https://ton.org/download/ton_symbol.svg");
    val transferRecipient = envOr(
        "JETTON_TRANSFER_RECIPIENT",
        net.wallet("jetton-recipient-1").address,
    );
    val transferAmount = envOr("JETTON_TRANSFER_AMOUNT", ton("0.1"));
    val value = envOr("JETTON_TRANSFER_VALUE", ton("0.08"));
    val forwardTonAmount = envOr("JETTON_FORWARD_TON_AMOUNT", ton("0.01"));
    val prefundMintAmount = envOr("JETTON_PREFUND_MINT_AMOUNT", ton("0.5"));
    val prefundMintTonAmount = envOr("JETTON_PREFUND_MINT_TON_AMOUNT", ton("0.08"));
    val deployValue = envOr("JETTON_DEPLOY_VALUE", ton("0.05"));

    val expectedMinter = JettonMinter.fromStorage({
        totalSupply: initialSupply,
        adminAddress: deployer.address,
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

    val senderWallet = JettonWallet { address: minter.getWalletAddress(deployer.address) };
    val senderWalletDeployed = net.isDeployed(senderWallet.address);
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
        if (!prefundRes.wait()) {
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
    if (!transferRes.wait()) {
        println("Transfer failed");
        return;
    }

    val recipientWallet = JettonWallet { address: minter.getWalletAddress(transferRecipient) };

    println("Sender balance after: {}", senderWallet.getJettonBalance());
    println("Recipient wallet: {}", recipientWallet.address);
    println("Recipient balance: {}", recipientWallet.getJettonBalance());
}
