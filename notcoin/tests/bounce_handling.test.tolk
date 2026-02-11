import "test_utils"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/types/message"
import "../contracts/messages"

get fun `test minter restores supply on internal_transfer bounce`() {
    val (minter, deployer, _) = setup_test();
    val supplyBefore = minter.getTotalSupply();
    val mintAmount = ton("2");
    val forwardPayload = beginCell().storeMaybeRef(null).endCell().beginParse();

    val mint_msg = createMessage({
        bounce: false,
        value: ton("0.315"),
        dest: minter.address,
        body: MintNewJettons {
            queryId: 0,
            mintRecipient: deployer.address,
            tonAmount: ton("0.3"),
            internalTransferMsg: InternalTransferStep {
                queryId: 0,
                jettonAmount: mintAmount,
                transferInitiator: null,
                sendExcessesTo: minter.address,
                forwardTonAmount: ton("0.05"),
                forwardPayload,
            }.toCell(),
        },
    });

    val res = net.sendSingle(deployer.address, mint_msg);
    expect(minter.getTotalSupply()).toEqual(supplyBefore + mintAmount);

    val out_msg = res.outMessages.at<InternalTransferStep>(0);
    val out_body = out_msg.loadBody();
    val bounced_body = beginCell().storeUint(0xffffffff, 32).storeSlice(
        out_body.toCell().beginParse(),
    ).endCell();
    val wallet = userWallet(minter, deployer.address);
    val bounced_msg = createMessage({
        bounce: false,
        value: ton("0.95"),
        dest: minter.address,
        body: bounced_body,
    }).bounced();
    // todo: rich bounces
    net.sendSingle(wallet.address, bounced_msg);

    expect(minter.getTotalSupply()).toEqual(supplyBefore);
}

get fun `test wallet restores balance on internal_transfer bounce`() {
    val (minter, deployer, not_deployer) = setup_test();
    val sender_wallet = mintTo(minter, deployer, deployer.address, ton("5"));
    val balance_before = sender_wallet.getJettonBalance();
    val forward_payload = beginCell().storeMaybeRef(null).endCell().beginParse();

    val transfer_msg = createMessage({
        bounce: true,
        value: ton("0.3"),
        dest: sender_wallet.address,
        body: AskToTransfer {
            queryId: 0,
            jettonAmount: ton("2"),
            transferRecipient: not_deployer.address,
            sendExcessesTo: deployer.address,
            customPayload: null,
            forwardTonAmount: 0,
            forwardPayload: forward_payload,
        },
    });

    val res = net.sendSingle(deployer.address, transfer_msg);
    expect(sender_wallet.getJettonBalance()).toEqual(balance_before - ton("2"));

    val out_msg = res.outMessages.at<InternalTransferStep>(0);
    val out_body = out_msg.loadBody();
    val bounced_body = beginCell().storeUint(0xffffffff, 32).storeSlice(
        out_body.toCell().beginParse(),
    ).endCell();
    val receiver_wallet = userWallet(minter, not_deployer.address);
    val bounced_msg = createMessage({
        bounce: false,
        value: ton("0.95"),
        dest: sender_wallet.address,
        body: bounced_body,
    }).bounced();
    net.sendSingle(receiver_wallet.address, bounced_msg);

    expect(sender_wallet.getJettonBalance()).toEqual(balance_before);
}

get fun `test wallet restores balance on burn_notification bounce`() {
    val (minter, deployer, _) = setup_test();
    val wallet = mintTo(minter, deployer, deployer.address, ton("4"));
    val balance_before = wallet.getJettonBalance();

    val burn_msg = createMessage({
        bounce: false,
        value: ton("0.2"),
        dest: wallet.address,
        body: AskToBurn {
            queryId: 0,
            jettonAmount: ton("1"),
            sendExcessesTo: deployer.address,
            customPayload: null,
        },
    });
    val res = net.sendSingle(deployer.address, burn_msg);
    expect(wallet.getJettonBalance()).toEqual(balance_before - ton("1"));

    val out_msg = res.outMessages.at<BurnNotificationForMinter>(0);
    val out_body = out_msg.loadBody();
    val bounced_body = beginCell().storeUint(0xffffffff, 32).storeSlice(
        out_body.toCell().beginParse(),
    ).endCell();
    val bounced_msg = createMessage({
        bounce: false,
        value: ton("0.95"),
        dest: wallet.address,
        body: bounced_body,
    }).bounced();
    net.sendSingle(minter.address, bounced_msg);

    expect(wallet.getJettonBalance()).toEqual(balance_before);
}
