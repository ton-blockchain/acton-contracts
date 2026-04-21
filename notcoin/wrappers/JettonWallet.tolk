import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../contracts/messages"
import "../contracts/types"

struct JettonWallet {
    address: address
}

fun JettonWallet.getJettonBalance(self): coins {
    if (!scripts.isContractDeployed(self.address)) {
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
    val outMessage = createMessage({
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
            forwardPayload: beginCell()
                .storeMaybeRef(forwardPayload.toCell())
                .endCell()
                .beginParse(),
        },
    });
    return net.send(from, outMessage);
}

fun JettonWallet.sendBurn(
    self,
    from: address,
    value: int,
    jettonAmount: int,
    responseAddress: address,
    customPayload: cell?,
) {
    val outMessage = createMessage({
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
    return net.send(from, outMessage);
}
