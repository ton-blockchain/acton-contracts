import "test_utils"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/tlb/maybe"
import "../contracts/errors"
import "../contracts/messages"

get fun `test wallet: owner can send jettons`() {
    val (minter, deployer, not_deployer) = setup_test();
    val transferAmount = ton("5");
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("20"));
    val receiverWallet = userWallet(minter, not_deployer.address);

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        transferAmount,
        not_deployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        null,
    );
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });

    expect(senderWallet.getJettonBalance()).toEqual(ton("15"));
    expect(receiverWallet.getJettonBalance()).toEqual(transferAmount);
}

get fun `test wallet: non-owner cannot send jettons`() {
    val (minter, deployer, not_deployer) = setup_test();
    val wallet = mintTo(minter, deployer, deployer.address, ton("7"));
    val balanceBefore = wallet.getJettonBalance();

    val res = wallet.sendTransfer(
        not_deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        ton("3"),
        not_deployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        null,
    );
    expect(res).toHaveFailedTx<AskToTransfer>({
        from: not_deployer.address,
        to: wallet.address,
        exitCode: ERROR_NOT_OWNER,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
}

get fun `test wallet: cannot send more jettons than balance`() {
    val (minter, deployer, not_deployer) = setup_test();
    val wallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val balanceBefore = wallet.getJettonBalance();

    val res = wallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        ton("5"),
        not_deployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        null,
    );
    expect(res).toHaveFailedTx<AskToTransfer>({
        from: deployer.address,
        to: wallet.address,
        exitCode: ERROR_BALANCE_ERROR,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
}

get fun `test wallet: zero forward ton means no transfer notification`() {
    val (minter, deployer, not_deployer) = setup_test();
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val receiverWallet = userWallet(minter, not_deployer.address);

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        ton("1"),
        not_deployer.address,
        deployer.address,
        null,
        0,
        null,
    );
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });
    expect(res).toNotHaveTx<TransferNotificationForRecipient>({
        from: receiverWallet.address,
        to: not_deployer.address,
    });
}

get fun `test wallet: transfer notification should preserve forward payload`() {
    val (minter, deployer, not_deployer) = setup_test();
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val receiverWallet = userWallet(minter, not_deployer.address);
    val sentAmount = ton("0.5");
    val forwardPayload = beginCell().storeUint(0x1234567890abcdef, 128).endCell();

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        sentAmount,
        not_deployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        forwardPayload,
    );
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });

    val notificationTx = res.findTransaction<TransferNotificationForRecipient>({
        from: receiverWallet.address,
        to: not_deployer.address,
        success: true,
        exitCode: 0,
    });
    expect(notificationTx).toBeDefined();

    val notification = notificationTx.unwrap().loadBody<TransferNotificationForRecipient>();
    var payloadSlice = notification.forwardPayload;
    val payloadRef = payloadSlice.loadMaybeRef();
    expect(payloadRef).toBeNotNull();
    if (payloadRef == null) {
        return;
    }

    var payloadBody = payloadRef.beginParse();
    if (
        payloadBody.remainingBitsCount() == 1 && payloadBody.preloadUint(1) == 1 &&
        payloadBody.remainingRefsCount() == 1
    ) {
        payloadBody.loadUint(1);
        expect(payloadBody.loadRef().hash()).toEqual(forwardPayload.hash());
    } else {
        expect(payloadRef.hash()).toEqual(forwardPayload.hash());
    }
}

get fun `test wallet: transfer to undeployed recipient wallet should still work`() {
    val (minter, deployer, _) = setup_test();
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val recipientOwner = net.randomAddress();
    val recipientWallet = userWallet(minter, recipientOwner);
    val sentAmount = ton("0.5");

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        sentAmount,
        recipientOwner,
        deployer.address,
        null,
        0,
        null,
    );

    expect(res).toHaveAllSuccessfulTxs();
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });
    expect(recipientWallet.getJettonBalance()).toEqual(sentAmount);
}

get fun `test wallet: owner can burn jettons`() {
    val (minter, deployer, _) = setup_test();
    val burnAmount = ton("3");
    val wallet = mintTo(minter, deployer, deployer.address, ton("10"));
    val supplyBefore = minter.getTotalSupply();

    val res = wallet.sendBurn(
        deployer.address,
        DEFAULT_BURN_MSG_VALUE,
        burnAmount,
        deployer.address,
        null,
    );
    expect(res).toHaveSuccessfulTx<AskToBurn>({ from: deployer.address, to: wallet.address });

    expect(wallet.getJettonBalance()).toEqual(ton("7"));
    expect(minter.getTotalSupply()).toEqual(supplyBefore - burnAmount);
}

get fun `test wallet: non-owner cannot burn jettons`() {
    val (minter, deployer, not_deployer) = setup_test();
    val wallet = mintTo(minter, deployer, deployer.address, ton("6"));
    val balanceBefore = wallet.getJettonBalance();
    val supplyBefore = minter.getTotalSupply();

    val res = wallet.sendBurn(
        not_deployer.address,
        DEFAULT_BURN_MSG_VALUE,
        ton("2"),
        deployer.address,
        null,
    );
    expect(res).toHaveFailedTx<AskToBurn>({
        from: not_deployer.address,
        to: wallet.address,
        exitCode: ERROR_NOT_OWNER,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
    expect(minter.getTotalSupply()).toEqual(supplyBefore);
}

get fun `test wallet: cannot burn more jettons than balance`() {
    val (minter, deployer, _) = setup_test();
    val wallet = mintTo(minter, deployer, deployer.address, ton("1"));
    val balanceBefore = wallet.getJettonBalance();
    val supplyBefore = minter.getTotalSupply();

    val res = wallet.sendBurn(
        deployer.address,
        DEFAULT_BURN_MSG_VALUE,
        ton("5"),
        deployer.address,
        null,
    );
    expect(res).toHaveFailedTx<AskToBurn>({
        from: deployer.address,
        to: wallet.address,
        exitCode: ERROR_BALANCE_ERROR,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
    expect(minter.getTotalSupply()).toEqual(supplyBefore);
}
