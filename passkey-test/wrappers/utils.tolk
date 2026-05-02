import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/types/message"
import "PasskeyWallet.gen"
import "../contracts/messages"

// Send a passkey-signed external message to the wallet.
fun PasskeyWallet.sendPasskeyExternal(self, req: ExternalRequest): SendResultList? {
    val msg = net.createExternalMessage(self.address, req);
    return net.sendExternal(msg);
}
