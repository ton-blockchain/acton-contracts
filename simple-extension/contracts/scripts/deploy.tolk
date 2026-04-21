import "@acton/io"
import "@acton/emulation/network"
import "common"
import "@wrappers/SimpleExtension"

fun main() {
    val deployer = net.wallet(extensionWalletName());
    val extension = buildExtensionForDeployer(deployer);
    val res = extension.deploy(deployer.address, {
        value: extensionDeployValue(),
        bounce: false,
    });

    if (!res.wait()) {
        return;
    }

    println("Deployed simple extension to {}", extension.address);
    println("Configured wallet address {}", extension.extensionInfo().walletAddress);
}
