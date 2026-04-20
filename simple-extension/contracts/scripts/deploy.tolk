import "@acton/io"
import "@acton/emulation/network"
import "@contracts/types"
import "@wrappers/SimpleExtension"

fun main() {
    val deployer = net.wallet("deployer");

    val extension = SimpleExtension.fromStorage(ExtensionStorage {
        walletAddress: deployer.address,
        admin: deployer.address,
        subscriptionAmount: ton("0.25"),
        lastPaymentTime: null,
        paymentTimeInterval: 3600,
    });
    val res = extension.deploy(deployer.address, { value: ton("0.5") });
    if (!res.wait()) {
        return;
    }

    println("Deployed simple extension to {}", extension.address);
    println("Configured wallet address {}", extension.extensionInfo().walletAddress);
}
