import "@acton/io"
import "@acton/emulation/network"
import "@acton/types/big_array"
import "@wrappers/SimpleExtension"
import "common"
import "../vendor/w5/contracts/messages"
import "../vendor/w5/wrappers/WalletV5Contract"

fun main() {
    val deployer: Wallet = net.wallet("deployer-2");

    val extension = SimpleExtension.fromAddress(
        address("kQABAJ-xOZrjiLOlIFxTptQKrUQdQjOO4Pj3WywRefnb-MnT"),
    );

    val wallet = WalletV5Contract { address: deployer.address };

    val res = wallet.getExtensions();

    println(res);

    if (res.exists(extension.address.getWorkchainAndHash().1)) {
        println("already exist");
        return;
    }

    val seqno = wallet.getSeqno();
    var extraActions: array<ExtraAction> = [];
    extraActions.push(AddExtensionExtraAction { addr: extension.address });

    val body = buildSignedExtensionActions(deployer, seqno, extraActions);
    val msg = createExternalMessage(wallet.address, body);
    val result2 = net.sendExternal(msg);

    if (result2 == null) {
        println("asd");
        return;
    }

    println(result2.size());

    while (seqno == wallet.getSeqno()) {
        // wait
    }

    val ext2: map<uint256, bool> = wallet.getExtensions();
    println(ext2);
}
