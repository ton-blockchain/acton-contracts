import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "../../contracts/messages"
import "../../contracts/storage"
import "../../contracts/types"

struct JettonWallet {
    address: address
}

fun JettonWallet.getJettonBalance(self): coins {
    if (!net.isDeployed(self.address)) {
        return 0;
    }

    val result: JettonWalletDataReply = net.runGetMethod(self.address, "get_wallet_data");
    return result.jettonBalance;
}

fun JettonWallet.sendTransfer(
    self,
    from: address,
    value: int,
    jettonAmount: int,
    recepient: address,
    responseAddress: address,
    customPayload: cell?,
    forwardTonAmount: int,
    forwardPayload: cell?,
) {
    val msg = createMessage({
        bounce: true,
        value,
        dest: self.address,
        body: AskToTransfer {
            queryId: 0,
            jettonAmount,
            transferRecipient: recepient,
            sendExcessesTo: responseAddress,
            customPayload,
            forwardTonAmount,
            forwardPayload: beginCell().storeMaybeRef(forwardPayload.toCell()).endCell()
                .beginParse(),
        },
    });
    return net.send(from, msg, SEND_MODE_PAY_FEES_SEPARATELY);
}

fun JettonWallet.sendBurn(
    self,
    from: address,
    value: int,
    jettonAmount: int,
    responseAddress: address,
    customPayload: cell?,
) {
    val msg = createMessage({
        bounce: false,
        value,
        dest: self.address,
        body: AskToBurn {
            queryId: 0,
            jettonAmount,
            sendExcessesTo: responseAddress,
            customPayload,
        },
    });
    return net.send(from, msg, SEND_MODE_PAY_FEES_SEPARATELY);
}
