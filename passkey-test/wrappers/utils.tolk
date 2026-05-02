import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/types/message"
import "PasskeyWallet.gen"
import "../contracts/messages"

// Send a passkey-signed external message to the wallet. The body is just the
// raw cell whose layout matches `ExternalRequest` in contracts/messages.tolk;
// the off-chain signing is done by `passkey-test/scripts/gen-wallet-vector.mjs`,
// and the test bakes the resulting bytes in.
fun PasskeyWallet.sendPasskeyExternal(self, externalBody: cell): SendResultList? {
    val msg = net.createExternalMessage(self.address, externalBody);
    return net.sendExternal(msg);
}
