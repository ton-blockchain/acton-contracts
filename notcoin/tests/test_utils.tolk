import "wrappers/JettonMinter"
import "wrappers/JettonWallet"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/messages"
import "../contracts/storage"

// Common values used across tests (nanotons for TON amounts)
const TEST_JETTON_UNIT = 1
const DEFAULT_MINTED_JETTONS = ton("5") // 5 TON in jetton units
const DEFAULT_TRANSFER_MSG_VALUE = 300000000 // 0.3 TON
const LOW_TRANSFER_MSG_VALUE = 200000000 // 0.2 TON
const DEFAULT_BURN_MSG_VALUE = 200000000 // 0.2 TON
const DEFAULT_FORWARD_TON_AMOUNT = 50000000 // 0.05 TON
const MIN_EDGE_DELTA = 1
const CONFIG_SCALE_X10 = 10
const GAS_SCALE_X3 = 3
const TRANSFER_MIN_PROBE_LIMIT = 10000

fun makeTinyForwardPayload() {
    return beginCell().storeUint(0, 1).toSlice();
}

fun makeRichForwardPayload() {
    return beginCell().storeMaybeRef(beginCell().storeUint(0x123456789abcdef, 128).endCell())
        .endCell().beginParse();
}

fun buildTransferBody(
    jettonAmount: int,
    forwardTonAmount: int,
    transferRecipient: address,
    sendExcessesTo: address,
    forwardPayload: slice,
    customPayload: cell? = null,
): AskToTransfer {
    return AskToTransfer {
        queryId: 0,
        jettonAmount,
        transferRecipient,
        sendExcessesTo,
        customPayload,
        forwardTonAmount,
        forwardPayload,
    };
}

fun estimateBodyForwardFee<T>(body: T) {
    val estMsg = createMessage({
        body,
        dest: net.randomAddress(),
        bounce: true,
        value: ton("1"),
    });

    return estMsg.estimateFeeWithoutSending(SEND_MODE_REGULAR);
}

fun sendRawTransferPayload(
    from: address,
    wallet: address,
    body: cell,
    value: int = DEFAULT_TRANSFER_MSG_VALUE,
) {
    val msg = createMessage({
        bounce: true,
        value,
        dest: wallet,
        body,
    });
    return net.send(from, msg, SEND_MODE_PAY_FEES_SEPARATELY);
}

fun slice.toSnakeString(self): Cell<SnakeString> {
    return self.toCell();
}

fun userWallet(minter: JettonMinter, userAddress: address): JettonWallet {
    val address = minter.getWalletAddress(userAddress);
    return JettonWallet { address };
}

fun setup_test(initial_supply: int = 0): (JettonMinter, Treasury, Treasury) {
    val deployer = net.treasury("deployer");
    val not_deployer = net.treasury("not_deployer");

    val minter = JettonMinter.fromStorage(MinterStorage {
        totalSupply: initial_supply,
        adminAddress: deployer.address,
        jettonWalletCode: build("notcoin_wallet"),
        metadataUri: "link".toSnakeString(),
        nextAdminAddress: null,
    });

    val transactions = minter.sendDeploy(deployer.address, { value: ton("10") });
    expect(transactions).toHaveSuccessfulDeploy({ to: minter.address });

    return (minter, deployer, not_deployer);
}

fun mintTo(minter: JettonMinter, admin: Treasury, recipient: address, amount: coins): JettonWallet {
    val supply_before = minter.getTotalSupply();
    val wallet = userWallet(minter, recipient);

    val mintResult = minter.sendMint(admin.address, recipient, amount, ton("0.05"), ton("0.3"));
    expect(mintResult).toHaveSuccessfulTx<MintNewJettons>({
        from: admin.address,
        to: minter.address,
    });

    expect(wallet.getJettonBalance()).toEqual(amount);
    expect(minter.getTotalSupply()).toEqual(supply_before + amount);
    return wallet;
}
